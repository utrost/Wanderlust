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
    /// OSM topology when available; never merge distinct nodes by proximity.
    pub node_ids: Option<[u64; 2]>,
    /// Original street edge for artificial coverage subdivisions.
    pub coverage_parent: Option<u64>,
    /// Optional OSM evidence; missing tags never imply permission or identity.
    pub street: StreetInfo,
}

#[derive(Debug, Clone, Default)]
pub struct StreetInfo {
    pub way_id: Option<u64>,
    pub name: String,
    pub highway: String,
    pub bicycle: String,
    pub foot: String,
    pub access: String,
    pub footway: String,
    pub layer: String,
    pub bridge: String,
    pub tunnel: String,
}

impl StreetInfo {
    fn road(&self) -> bool {
        matches!(
            self.highway.as_str(),
            "primary" | "secondary" | "tertiary" | "unclassified" | "residential" | "living_street"
        )
    }

    /// Soft evidence only: recordings can include dismounting or stale OSM tags.
    pub(crate) fn activity_cost(&self, cycling: bool) -> f64 {
        let allowed = |s: &str| matches!(s, "yes" | "designated" | "permissive" | "official");
        let specific = if cycling { &self.bicycle } else { &self.foot };
        if allowed(specific) {
            return 0.0;
        }
        if matches!(specific.as_str(), "no" | "private") {
            return 2.0;
        }
        if matches!(self.access.as_str(), "no" | "private") {
            return 1.5;
        }
        if cycling && matches!(self.highway.as_str(), "steps" | "footway" | "pedestrian") {
            return if self.highway == "steps" { 1.5 } else { 0.4 };
        }
        if !cycling && self.highway == "cycleway" {
            return 0.4;
        }
        0.0
    }

    pub(crate) fn movement_cost(&self, cycling: bool, motorized: bool) -> f64 {
        if motorized {
            return if matches!(
                self.highway.as_str(),
                "footway" | "path" | "steps" | "pedestrian" | "cycleway" | "bridleway"
            ) {
                3.0
            } else {
                0.0
            };
        }
        if self.highway == "railway"
            || matches!(
                self.highway.as_str(),
                "motorway" | "motorway_link" | "trunk" | "trunk_link"
            )
        {
            return 3.0;
        }
        self.activity_cost(cycling)
    }

    fn same_level(&self, other: &Self) -> bool {
        let a_layer = if self.layer.is_empty() {
            "0"
        } else {
            &self.layer
        };
        let b_layer = if other.layer.is_empty() {
            "0"
        } else {
            &other.layer
        };
        let structure = |s: &str| !s.is_empty() && s != "no";
        a_layer == b_layer
            && structure(&self.bridge) == structure(&other.bridge)
            && structure(&self.tunnel) == structure(&other.tunnel)
    }

    fn same_identity(&self, other: &Self) -> bool {
        self.way_id.is_some() && self.way_id == other.way_id
            || (!self.name.is_empty() && self.name == other.name)
    }
}

impl Segment {
    pub fn new(id: u64, polyline: Vec<LngLat>) -> Self {
        Self {
            id,
            polyline,
            node_ids: None,
            coverage_parent: None,
            street: StreetInfo::default(),
        }
    }

    pub fn with_nodes(mut self, from: u64, to: u64) -> Self {
        self.node_ids = Some([from, to]);
        self
    }

    /// Length along the polyline, metres.
    pub fn length_m(&self) -> f64 {
        self.polyline
            .windows(2)
            .map(|w| haversine_m(w[0], w[1]))
            .sum()
    }

    /// Closest projection: along-edge metres and local unit tangent. Endpoint
    /// clamping is intentional: moving past a junction is not travel up a spur.
    pub fn project(&self, point: LngLat) -> Option<(f64, (f64, f64))> {
        let reference = self.polyline.first()?.lat.to_radians();
        let (px, py) = point.to_xy(reference);
        let mut best_distance = f64::INFINITY;
        let mut best = None;
        let mut along = 0.0;
        for pair in self.polyline.windows(2) {
            let (ax, ay) = pair[0].to_xy(reference);
            let (bx, by) = pair[1].to_xy(reference);
            let (dx, dy) = (bx - ax, by - ay);
            let length = dx.hypot(dy);
            if length <= f64::EPSILON {
                continue;
            }
            let t = (((px - ax) * dx + (py - ay) * dy) / length.powi(2)).clamp(0.0, 1.0);
            let distance = (px - ax - t * dx).hypot(py - ay - t * dy);
            if distance < best_distance {
                best_distance = distance;
                best = Some((along + t * length, (dx / length, dy / length)));
            }
            along += length;
        }
        best
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
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum NodeKey {
    Osm(u64),
    Coordinate(i64, i64),
}

fn node_key(p: LngLat) -> NodeKey {
    NodeKey::Coordinate((p.lng * 1e5).round() as i64, (p.lat * 1e5).round() as i64)
}

/// An undirected routing graph over a fixed set of segments.
pub struct Graph {
    segments: Vec<Segment>,
    ref_lat_rad: f64,
    spatial: HashMap<(i64, i64), Vec<usize>>,
    unindexed: Vec<usize>,
    /// For each segment index, its (start_node, end_node) ids.
    seg_nodes: Vec<(usize, usize)>,
    /// node id -> outgoing edges (neighbour_node, segment_index, length_m).
    adjacency: Vec<Vec<(usize, usize, f64)>>,
}

impl Graph {
    /// Build with explicit OSM topology, or coordinate keys for legacy fixtures.
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
            let keys = seg
                .node_ids
                .map(|[a, b]| [NodeKey::Osm(a), NodeKey::Osm(b)])
                .unwrap_or_else(|| [node_key(seg.start()), node_key(seg.end())]);
            let a = intern(keys[0], &mut adjacency);
            let b = intern(keys[1], &mut adjacency);
            let len = seg.length_m();
            seg_nodes.push((a, b));
            // Undirected: traversable either way.
            adjacency[a].push((b, i, len));
            if a != b {
                adjacency[b].push((a, i, len));
            }
        }

        // A small metric grid keeps dense coverage sections cheap to query.
        let mut spatial: HashMap<(i64, i64), Vec<usize>> = HashMap::new();
        let mut unindexed = Vec::new();
        for (i, segment) in segments.iter().enumerate() {
            let coords: Vec<_> = segment
                .polyline
                .iter()
                .map(|p| p.to_xy(ref_lat_rad))
                .collect();
            let x0 =
                (coords.iter().map(|p| p.0).fold(f64::INFINITY, f64::min) / 50.0).floor() as i64;
            let x1 = (coords.iter().map(|p| p.0).fold(f64::NEG_INFINITY, f64::max) / 50.0).floor()
                as i64;
            let y0 =
                (coords.iter().map(|p| p.1).fold(f64::INFINITY, f64::min) / 50.0).floor() as i64;
            let y1 = (coords.iter().map(|p| p.1).fold(f64::NEG_INFINITY, f64::max) / 50.0).floor()
                as i64;
            if (x1 - x0 + 1).saturating_mul(y1 - y0 + 1) > 4096 {
                unindexed.push(i);
                continue;
            }
            for x in x0..=x1 {
                for y in y0..=y1 {
                    spatial.entry((x, y)).or_default().push(i);
                }
            }
        }
        Self {
            segments,
            ref_lat_rad,
            spatial,
            unindexed,
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

    pub fn same_coverage_parent(&self, a: usize, b: usize) -> bool {
        self.segments[a].coverage_parent.is_some()
            && self.segments[a].coverage_parent == self.segments[b].coverage_parent
    }

    /// Consecutive pieces of one street can support each other. This does not
    /// create routing links, nor combine an adjoining perpendicular branch.
    pub(crate) fn same_street_run(&self, a: usize, b: usize, at: LngLat) -> bool {
        if a == b || self.same_coverage_parent(a, b) {
            return true;
        }
        let (x, y) = (&self.segments[a], &self.segments[b]);
        if !x.street.same_level(&y.street)
            || !x.street.same_identity(&y.street)
            || x.street.highway != y.street.highway
            || !Self::parallel_at(x, y, at, 0.94)
        {
            return false;
        }
        self.adjacent(a, b)
            || self
                .unique_connection(a, b, at, at, 60.0)
                .is_some_and(|path| {
                    path.iter().all(|&edge| {
                        let s = &self.segments[edge];
                        x.street.same_identity(&s.street)
                            && x.street.same_level(&s.street)
                            && x.street.highway == s.street.highway
                            && Self::parallel_at(x, s, at, 0.94)
                    })
                })
    }

    fn parallel_at(a: &Segment, b: &Segment, at: LngLat, threshold: f64) -> bool {
        match (a.project(at), b.project(at)) {
            (Some((_, x)), Some((_, y))) => (x.0 * y.0 + x.1 * y.1).abs() >= threshold,
            _ => false,
        }
    }

    /// Same street corridor at this observation, not a routing connection.
    /// Require identity, compatible type/level, close parallel geometry and
    /// longitudinal overlap. A shared name alone is never sufficient.
    pub(crate) fn same_corridor(&self, a: usize, b: usize, at: LngLat) -> bool {
        if a == b || self.same_coverage_parent(a, b) {
            return true;
        }
        let (x, y) = (&self.segments[a], &self.segments[b]);
        if !x.street.same_level(&y.street)
            || !x.street.same_identity(&y.street)
            || !Self::parallel_at(x, y, at, 0.97)
        {
            return false;
        }
        if self.same_street_run(a, b, at) {
            return true;
        }
        let roadside = |s: &StreetInfo| {
            s.highway == "cycleway" || s.highway == "footway" && s.footway == "sidewalk"
        };
        if !(x.street.road() && y.street.road() && x.street.highway == y.street.highway
            || x.street.road() && roadside(&y.street)
            || y.street.road() && roadside(&x.street))
        {
            return false;
        }
        let reference = at.lat.to_radians();
        let close = |point, line: &Segment| {
            line.polyline
                .windows(2)
                .any(|p| point_to_segment_m(point, p[0], p[1], reference) <= 18.0)
        };
        // Requiring both ends of the shorter piece avoids grouping diverging
        // roads that merely pass close at an intersection.
        let (short, long) = if x.length_m() <= y.length_m() {
            (x, y)
        } else {
            (y, x)
        };
        if short.length_m() < 8.0 || !close(short.start(), long) || !close(short.end(), long) {
            return false;
        }
        let Some((start, _)) = long.project(short.start()) else {
            return false;
        };
        let Some((end, _)) = long.project(short.end()) else {
            return false;
        };
        (end - start).abs() >= short.length_m().min(10.0) * 0.7
    }

    /// True if two segments share a junction node.
    pub fn adjacent(&self, a: usize, b: usize) -> bool {
        let (a0, a1) = self.seg_nodes[a];
        let (b0, b1) = self.seg_nodes[b];
        a0 == b0 || a0 == b1 || a1 == b0 || a1 == b1
    }

    fn candidates(&self, p: LngLat, radius: f64) -> Vec<usize> {
        if !radius.is_finite() || radius < 0.0 {
            return Vec::new();
        }
        let (x, y) = p.to_xy(self.ref_lat_rad);
        let x0 = ((x - radius) / 50.0).floor() as i64;
        let x1 = ((x + radius) / 50.0).floor() as i64;
        let y0 = ((y - radius) / 50.0).floor() as i64;
        let y1 = ((y + radius) / 50.0).floor() as i64;
        if (x1 - x0 + 1).saturating_mul(y1 - y0 + 1) > 4096 {
            return (0..self.segments.len()).collect();
        }
        let mut result = self.unindexed.clone();
        for x in x0..=x1 {
            for y in y0..=y1 {
                if let Some(edges) = self.spatial.get(&(x, y)) {
                    result.extend(edges);
                }
            }
        }
        result.sort_unstable();
        result.dedup();
        result
    }

    /// Nearest segment to `p` within `max_dist_m`. Returns (segment_index,
    /// distance_m). Grid candidates retain source order for deterministic ties.
    pub fn nearest_segment(&self, p: LngLat, max_dist_m: f64) -> Option<(usize, f64)> {
        let mut best: Option<(usize, f64)> = None;
        for i in self.candidates(p, max_dist_m) {
            let seg = &self.segments[i];
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

    /// Bounded nearby candidates, ordered deterministically for sequence matching.
    pub fn nearby_segments(&self, point: LngLat, radius: f64) -> Vec<(usize, f64)> {
        let mut found = self.nearby_candidates(point, radius);
        found.truncate(8);
        found
    }

    /// Apply the same proximity and movement evidence as the sequence solver
    /// before limiting candidates. Dense rail geometry must not evict a nearby
    /// walking path, nor should footpaths evict a plausible rail journey.
    pub(crate) fn movement_candidates(
        &self,
        point: LngLat,
        radius: f64,
        accuracy: f64,
        cycling: bool,
        motorized: bool,
    ) -> Vec<(usize, f64)> {
        let mut found = self.nearby_candidates(point, radius);
        let sigma = accuracy.clamp(4.0, 50.0);
        let cost = |&(edge, distance): &(usize, f64)| {
            0.5 * (distance / sigma).powi(2)
                + self.segments[edge].street.movement_cost(cycling, motorized)
        };
        found.sort_by(|a, b| {
            cost(a)
                .total_cmp(&cost(b))
                .then(a.1.total_cmp(&b.1))
                .then(self.segments[a.0].id.cmp(&self.segments[b.0].id))
        });
        found.truncate(8);
        found
    }

    /// Closest geometry eligible for the current movement, for deciding whether
    /// recorded GPS still needs a fallback line beside the matched route.
    pub(crate) fn nearest_movement_segment(
        &self,
        point: LngLat,
        radius: f64,
        cycling: bool,
        motorized: bool,
    ) -> Option<(usize, f64)> {
        self.nearby_candidates(point, radius)
            .into_iter()
            .find(|&(edge, _)| self.segments[edge].street.movement_cost(cycling, motorized) < 3.0)
    }

    /// A local anchor must be unambiguous among geometry suitable for this
    /// movement. Rails/motorways cannot veto a walking anchor solely by being
    /// closer. Vehicle travel still compares roads and rails with each other.
    pub(crate) fn movement_anchor(
        &self,
        point: LngLat,
        radius: f64,
        cycling: bool,
        motorized: bool,
    ) -> Option<(usize, f64)> {
        let eligible: Vec<_> = self
            .nearby_candidates(point, radius + 3.0)
            .into_iter()
            .filter(|&(edge, _)| self.segments[edge].street.movement_cost(cycling, motorized) < 3.0)
            .collect();
        let best = *eligible.first()?;
        if best.1 > radius
            || eligible.iter().skip(1).any(|&(edge, distance)| {
                distance <= best.1 + 3.0 && !self.same_coverage_parent(edge, best.0)
            })
        {
            return None;
        }
        Some(best)
    }

    fn nearby_candidates(&self, point: LngLat, radius: f64) -> Vec<(usize, f64)> {
        let mut found: Vec<_> = self
            .candidates(point, radius)
            .into_iter()
            .filter_map(|i| {
                let distance = self.segments[i]
                    .polyline
                    .windows(2)
                    .map(|p| point_to_segment_m(point, p[0], p[1], self.ref_lat_rad))
                    .fold(f64::INFINITY, f64::min);
                (distance <= radius).then_some((i, distance))
            })
            .collect();
        found.sort_by(|a, b| {
            a.1.total_cmp(&b.1)
                .then(self.segments[a.0].id.cmp(&self.segments[b.0].id))
        });
        found
    }

    /// Network distance between projected observations, bounded by walking budget.
    /// Sparse search avoids allocating a full-city table for every transition.
    pub fn projected_distance(
        &self,
        from: usize,
        to: usize,
        start: LngLat,
        end: LngLat,
        budget: f64,
    ) -> Option<f64> {
        let a = self.segment(from);
        let b = self.segment(to);
        let x = a.project(start)?.0.min(a.length_m());
        let y = b.project(end)?.0.min(b.length_m());
        if from == to {
            return ((x - y).abs() <= budget).then_some((x - y).abs());
        }
        let mut dist = HashMap::new();
        let mut heap = BinaryHeap::new();
        for (node, cost) in [
            (self.seg_nodes[from].0, x),
            (self.seg_nodes[from].1, a.length_m() - x),
        ] {
            if cost <= budget && cost < *dist.get(&node).unwrap_or(&f64::INFINITY) {
                dist.insert(node, cost);
                heap.push(HeapEntry { node, cost });
            }
        }
        let mut best = f64::INFINITY;
        let mut visited = 0;
        while let Some(HeapEntry { node, cost }) = heap.pop() {
            if cost > *dist.get(&node).unwrap_or(&f64::INFINITY) || cost > best {
                continue;
            }
            visited += 1;
            if visited > 2048 {
                return None;
            }
            for (target, tail) in [
                (self.seg_nodes[to].0, y),
                (self.seg_nodes[to].1, b.length_m() - y),
            ] {
                if node == target && cost + tail <= budget {
                    best = best.min(cost + tail);
                }
            }
            for &(next, edge, length) in &self.adjacency[node] {
                if edge == from || edge == to {
                    continue;
                }
                let next_cost = cost + length;
                if next_cost <= budget && next_cost < *dist.get(&next).unwrap_or(&f64::INFINITY) {
                    dist.insert(next, next_cost);
                    heap.push(HeapEntry {
                        node: next,
                        cost: next_cost,
                    });
                }
            }
        }
        best.is_finite().then_some(best)
    }

    /// Avoid painting either candidate when the nearest two streets are within
    /// three metres of one another in snap distance (junctions/parallel paths).
    pub fn nearest_unambiguous_segment(&self, p: LngLat, max_dist_m: f64) -> Option<(usize, f64)> {
        if !p.lng.is_finite() || !p.lat.is_finite() || p.lng.abs() > 180.0 || p.lat.abs() > 90.0 {
            return None;
        }
        let best = self.nearest_segment(p, max_dist_m)?;
        for i in self.candidates(p, best.1 + 3.0) {
            let seg = &self.segments[i];
            if i == best.0 || self.same_coverage_parent(i, best.0) {
                continue;
            }
            let distance = seg
                .polyline
                .windows(2)
                .map(|w| point_to_segment_m(p, w[0], w[1], self.ref_lat_rad))
                .fold(f64::INFINITY, f64::min);
            if distance <= best.1 + 3.0 {
                return None;
            }
        }
        Some(best)
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

    /// A short connector between projected fixes, including the unwalked tails
    /// of the anchor edges. Reject it if another route fits the same budget.
    pub fn unique_connection(
        &self,
        from: usize,
        to: usize,
        start: LngLat,
        end: LngLat,
        budget: f64,
    ) -> Option<Vec<usize>> {
        let search = |blocked: Option<usize>| -> Option<Vec<usize>> {
            let a = self.segment(from);
            let b = self.segment(to);
            let start_along = a.project(start)?.0.min(a.length_m());
            let end_along = b.project(end)?.0.min(b.length_m());
            let mut dist = vec![f64::INFINITY; self.adjacency.len()];
            let mut prev = vec![None; self.adjacency.len()];
            let mut heap = BinaryHeap::new();
            for (node, cost) in [
                (self.seg_nodes[from].0, start_along),
                (self.seg_nodes[from].1, a.length_m() - start_along),
            ] {
                if cost < dist[node] {
                    dist[node] = cost;
                    heap.push(HeapEntry { node, cost });
                }
            }
            let mut best = budget + 1e-6;
            let mut target = None;
            while let Some(HeapEntry { node, cost }) = heap.pop() {
                if cost > dist[node] || cost > best {
                    continue;
                }
                for (end_node, tail) in [
                    (self.seg_nodes[to].0, end_along),
                    (self.seg_nodes[to].1, b.length_m() - end_along),
                ] {
                    if node == end_node && cost + tail < best {
                        best = cost + tail;
                        target = Some(node);
                    }
                }
                for &(next, edge, length) in &self.adjacency[node] {
                    if edge == from || edge == to || Some(edge) == blocked {
                        continue;
                    }
                    let next_cost = cost + length;
                    if next_cost < dist[next] && next_cost <= budget {
                        dist[next] = next_cost;
                        prev[next] = Some((node, edge));
                        heap.push(HeapEntry {
                            node: next,
                            cost: next_cost,
                        });
                    }
                }
            }
            Some(self.reconstruct(target?, &prev))
        };
        let path = search(None)?;
        if path.is_empty() || path.iter().any(|&edge| search(Some(edge)).is_some()) {
            return None;
        }
        Some(path)
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
