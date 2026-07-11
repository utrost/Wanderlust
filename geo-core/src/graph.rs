//! The routable street graph: OSM-style segments and the node adjacency built
//! from their shared endpoints, plus nearest-segment lookup and a Dijkstra
//! shortest path used to fill plausible gaps between GPS matches.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};

use crate::geometry::{haversine_m, point_to_segment_m, LngLat};

/// One walkable street edge — an ordered polyline of coordinates. `id` is the
/// stable identifier used for per-segment walk counts (in practice an OSM way /
/// sub-segment id).
#[derive(Debug, Clone)]
pub struct Segment {
    pub id: u64,
    pub polyline: Vec<LngLat>,
}

impl Segment {
    pub fn new(id: u64, polyline: Vec<LngLat>) -> Self {
        Self { id, polyline }
    }

    /// Length along the polyline, metres.
    pub fn length_m(&self) -> f64 {
        self.polyline
            .windows(2)
            .map(|w| haversine_m(w[0], w[1]))
            .sum()
    }

    fn start(&self) -> LngLat {
        self.polyline[0]
    }

    fn end(&self) -> LngLat {
        self.polyline[self.polyline.len() - 1]
    }
}

/// Quantised coordinate used to fuse coincident segment endpoints into one
/// graph node. ~1e-5 degrees ≈ 1 m, which is the tolerance for "these two
/// street ends are the same junction".
type NodeKey = (i64, i64);

fn node_key(p: LngLat) -> NodeKey {
    ((p.lng * 1e5).round() as i64, (p.lat * 1e5).round() as i64)
}

/// An undirected routing graph over a fixed set of segments.
pub struct Graph {
    segments: Vec<Segment>,
    ref_lat_rad: f64,
    /// For each segment index, its (start_node, end_node) ids.
    seg_nodes: Vec<(usize, usize)>,
    /// node id -> outgoing edges (neighbour_node, segment_index, length_m).
    adjacency: Vec<Vec<(usize, usize, f64)>>,
}

impl Graph {
    /// Build the graph, fusing endpoints within ~1 m into shared nodes.
    pub fn build(segments: Vec<Segment>) -> Self {
        let ref_lat_rad = if segments.is_empty() {
            0.0
        } else {
            let (sum, n) = segments.iter().fold((0.0, 0usize), |(s, n), seg| {
                (
                    s + seg.polyline.iter().map(|p| p.lat).sum::<f64>(),
                    n + seg.polyline.len(),
                )
            });
            (sum / n as f64).to_radians()
        };

        let mut node_ids: HashMap<NodeKey, usize> = HashMap::new();
        let mut seg_nodes = Vec::with_capacity(segments.len());
        let mut adjacency: Vec<Vec<(usize, usize, f64)>> = Vec::new();

        let mut intern = |key: NodeKey, adjacency: &mut Vec<Vec<(usize, usize, f64)>>| -> usize {
            if let Some(&id) = node_ids.get(&key) {
                id
            } else {
                let id = adjacency.len();
                node_ids.insert(key, id);
                adjacency.push(Vec::new());
                id
            }
        };

        for (i, seg) in segments.iter().enumerate() {
            let a = intern(node_key(seg.start()), &mut adjacency);
            let b = intern(node_key(seg.end()), &mut adjacency);
            let len = seg.length_m();
            seg_nodes.push((a, b));
            // Undirected: traversable either way.
            adjacency[a].push((b, i, len));
            if a != b {
                adjacency[b].push((a, i, len));
            }
        }

        Self {
            segments,
            ref_lat_rad,
            seg_nodes,
            adjacency,
        }
    }

    pub fn segments(&self) -> &[Segment] {
        &self.segments
    }

    pub fn segment(&self, idx: usize) -> &Segment {
        &self.segments[idx]
    }

    /// True if two segments share a junction node.
    pub fn adjacent(&self, a: usize, b: usize) -> bool {
        let (a0, a1) = self.seg_nodes[a];
        let (b0, b1) = self.seg_nodes[b];
        a0 == b0 || a0 == b1 || a1 == b0 || a1 == b1
    }

    /// Nearest segment to `p` within `max_dist_m`. Returns (segment_index,
    /// distance_m). O(n) scan — fine for the spike; a real deployment swaps in a
    /// spatial index (R-tree / grid).
    pub fn nearest_segment(&self, p: LngLat, max_dist_m: f64) -> Option<(usize, f64)> {
        let mut best: Option<(usize, f64)> = None;
        for (i, seg) in self.segments.iter().enumerate() {
            let mut d = f64::INFINITY;
            for w in seg.polyline.windows(2) {
                d = d.min(point_to_segment_m(p, w[0], w[1], self.ref_lat_rad));
            }
            if d <= max_dist_m && best.is_none_or(|(_, bd)| d < bd) {
                best = Some((i, d));
            }
        }
        best
    }

    /// Shortest connecting path between two segments, as the list of
    /// *intermediate* segment indices plus total length. Empty vec with cost 0
    /// means the two segments already share a node (adjacent). `None` means no
    /// path exists in the graph.
    pub fn shortest_path(&self, from: usize, to: usize) -> Option<(Vec<usize>, f64)> {
        if from == to {
            return Some((Vec::new(), 0.0));
        }
        let (t0, t1) = self.seg_nodes[to];

        // Dijkstra from both endpoints of `from`, targeting either endpoint of `to`.
        let n = self.adjacency.len();
        let mut dist = vec![f64::INFINITY; n];
        // prev[node] = (came_from_node, segment_index_used)
        let mut prev: Vec<Option<(usize, usize)>> = vec![None; n];
        let mut heap = BinaryHeap::new();

        for &s in &[self.seg_nodes[from].0, self.seg_nodes[from].1] {
            if s < n && dist[s] > 0.0 {
                dist[s] = 0.0;
                heap.push(HeapEntry { cost: 0.0, node: s });
            }
        }

        while let Some(HeapEntry { cost, node }) = heap.pop() {
            if cost > dist[node] {
                continue;
            }
            if node == t0 || node == t1 {
                return Some((self.reconstruct(node, &prev), cost));
            }
            for &(next, seg_idx, len) in &self.adjacency[node] {
                let nc = cost + len;
                if nc < dist[next] {
                    dist[next] = nc;
                    prev[next] = Some((node, seg_idx));
                    heap.push(HeapEntry {
                        cost: nc,
                        node: next,
                    });
                }
            }
        }
        None
    }

    fn reconstruct(&self, target: usize, prev: &[Option<(usize, usize)>]) -> Vec<usize> {
        let mut segs = Vec::new();
        let mut cur = target;
        while let Some((from_node, seg_idx)) = prev[cur] {
            segs.push(seg_idx);
            cur = from_node;
        }
        segs.reverse();
        segs
    }
}

/// Min-heap entry ordered by cost (f64 has no total `Ord`, so we implement it).
struct HeapEntry {
    cost: f64,
    node: usize,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.cost == other.cost && self.node == other.node
    }
}
impl Eq for HeapEntry {}
impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        // Reversed so BinaryHeap (a max-heap) yields the smallest cost first.
        other
            .cost
            .total_cmp(&self.cost)
            .then_with(|| self.node.cmp(&other.node))
    }
}
impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
