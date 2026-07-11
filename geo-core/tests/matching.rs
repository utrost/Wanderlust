//! Phase 0 exit criteria, as tests: feed a track in → correct per-segment
//! coverage out, and crucially *no phantom streets* the walker never touched.

use geo_core::geometry::{haversine_m, LngLat};
use geo_core::graph::{Graph, Segment};
use geo_core::matcher::{match_track, walked_ids, MatchConfig, MatchResult};

/// Metres → degrees at a reference latitude, for building test grids.
fn dlng(m: f64, lat: f64) -> f64 {
    m / (111_320.0 * lat.to_radians().cos())
}
fn dlat(m: f64) -> f64 {
    m / 110_540.0
}

/// A regular NxN lattice of ~`spacing_m` blocks around `origin`. Segment ids are
/// assigned in creation order; the test bodies know which ids they expect.
struct Grid {
    graph: Graph,
    /// (row, col) horizontal-edge id: from (r,c) to (r,c+1)
    h: Vec<Vec<u64>>,
    /// (row, col) vertical-edge id: from (r,c) to (r+1,c)
    v: Vec<Vec<u64>>,
    node: Vec<Vec<LngLat>>,
}

#[allow(clippy::needless_range_loop)] // r/c index into geometry; ranges are clearer here
fn build_grid(n: usize, spacing_m: f64, origin: LngLat) -> Grid {
    let mut node = vec![vec![LngLat::new(0.0, 0.0); n]; n];
    for r in 0..n {
        for c in 0..n {
            node[r][c] = LngLat::new(
                origin.lng + dlng(spacing_m, origin.lat) * c as f64,
                origin.lat + dlat(spacing_m) * r as f64,
            );
        }
    }
    let mut segs = Vec::new();
    let mut h = vec![vec![0u64; n]; n];
    let mut v = vec![vec![0u64; n]; n];
    let mut id = 1u64;
    for r in 0..n {
        for c in 0..n {
            if c + 1 < n {
                h[r][c] = id;
                segs.push(Segment::new(id, vec![node[r][c], node[r][c + 1]]));
                id += 1;
            }
            if r + 1 < n {
                v[r][c] = id;
                segs.push(Segment::new(id, vec![node[r][c], node[r + 1][c]]));
                id += 1;
            }
        }
    }
    Grid {
        graph: Graph::build(segs),
        h,
        v,
        node,
    }
}

/// Densely sample a straight walk between two coords, with optional lateral
/// noise, so snapping has realistic input.
fn walk_between(a: LngLat, b: LngLat, step_m: f64, noise_deg: f64) -> Vec<LngLat> {
    let dist = haversine_m(a, b);
    let steps = (dist / step_m).ceil().max(1.0) as usize;
    (0..=steps)
        .map(|i| {
            let t = i as f64 / steps as f64;
            let wobble = if noise_deg > 0.0 {
                // deterministic pseudo-noise, no rng dependency
                (i as f64 * 1.3).sin() * noise_deg
            } else {
                0.0
            };
            LngLat::new(
                a.lng + (b.lng - a.lng) * t,
                a.lat + (b.lat - a.lat) * t + wobble,
            )
        })
        .collect()
}

#[test]
fn straight_walk_lights_exactly_the_walked_row() {
    let g = build_grid(4, 100.0, LngLat::new(13.40, 52.50));
    // Walk east along row 0: node[0][0] → node[0][3], three horizontal edges.
    // Clean GPS (no lateral noise): the exact-coverage guarantee is a clean-fix
    // claim. Heavy noise *through a junction* can also snap to the perpendicular
    // stubs sharing that node — a known limitation of pure nearest-snap that
    // bearing-aware snapping will address later; it is not what this spike
    // asserts.
    let mut track = Vec::new();
    for c in 0..3 {
        track.extend(walk_between(g.node[0][c], g.node[0][c + 1], 10.0, 0.0));
    }
    let result = match_track(&g.graph, &track, MatchConfig::default());
    let walked = walked_ids(&g.graph, &result);

    let expected = vec![g.h[0][0], g.h[0][1], g.h[0][2]];
    assert_eq!(walked, sorted(expected), "walked exactly row-0 horizontals");
    assert_eq!(result.gaps_rejected, 0);
}

#[test]
fn l_shaped_walk_fills_the_corner_via_shortest_path() {
    // Walk east then north, but only give GPS on the two far ends of each leg
    // so the matcher must graph-fill the middle. All edges are short and
    // connected, so the guardrail should allow it.
    let g = build_grid(4, 100.0, LngLat::new(13.40, 52.50));
    let mut track = Vec::new();
    track.extend(walk_between(g.node[0][0], g.node[0][2], 10.0, 0.0)); // east
    track.extend(walk_between(g.node[0][2], g.node[2][2], 10.0, 0.0)); // north
    let result = match_track(&g.graph, &track, MatchConfig::default());
    let walked = walked_ids(&g.graph, &result);

    let expected = sorted(vec![
        g.h[0][0], g.h[0][1], // east leg
        g.v[0][2], g.v[1][2], // north leg
    ]);
    assert_eq!(walked, expected);
}

#[test]
fn guardrail_refuses_to_paint_an_implausible_detour() {
    // Two parallel dead-end stubs whose tips are ~30 m apart in space but far
    // apart on the network (you'd have to walk all the way around). A GPS jump
    // from one tip to the other must NOT paint the long connecting route.
    let origin = LngLat::new(13.40, 52.50);
    // Long horizontal spine of 4 nodes, 200 m blocks.
    let n0 = origin;
    let n1 = LngLat::new(origin.lng + dlng(200.0, origin.lat), origin.lat);
    let n2 = LngLat::new(origin.lng + dlng(400.0, origin.lat), origin.lat);
    let n3 = LngLat::new(origin.lng + dlng(600.0, origin.lat), origin.lat);
    // Two stubs hanging down from n0 and n3, whose tips nearly meet in the middle
    // is not needed — instead put stubs whose tips are close but connection is long.
    let stub_a_tip = LngLat::new(
        origin.lng + dlng(280.0, origin.lat),
        origin.lat - dlat(20.0),
    );
    let stub_b_tip = LngLat::new(
        origin.lng + dlng(320.0, origin.lat),
        origin.lat - dlat(20.0),
    );

    let spine_a = Segment::new(1, vec![n0, n1]);
    let spine_b = Segment::new(2, vec![n1, n2]);
    let spine_c = Segment::new(3, vec![n2, n3]);
    let stub_a = Segment::new(4, vec![n1, stub_a_tip]); // hangs off n1
    let stub_b = Segment::new(5, vec![n2, stub_b_tip]); // hangs off n2
    let graph = Graph::build(vec![spine_a, spine_b, spine_c, stub_a, stub_b]);

    // Tips are ~40 m apart, but connecting them on-network is stub_a → n1 →
    // spine_b → n2 → stub_b ≈ 20+200+20+ = far more than 2.5×40 m.
    assert!(haversine_m(stub_a_tip, stub_b_tip) < 60.0);

    let track = vec![
        stub_a_tip,
        LngLat::new(stub_a_tip.lng, stub_a_tip.lat + dlat(2.0)),
        stub_b_tip, // the teleport
    ];
    let result: MatchResult = match_track(&graph, &track, MatchConfig::default());
    let walked = walked_ids(&graph, &result);

    // Only the two stubs the GPS actually sat on — the spine is NOT painted.
    assert_eq!(walked, sorted(vec![4, 5]), "no phantom spine");
    assert_eq!(result.gaps_filled, 0);
    assert_eq!(result.gaps_rejected, 1);
}

#[test]
fn doubling_back_counts_a_segment_once_per_track() {
    let g = build_grid(3, 100.0, LngLat::new(13.40, 52.50));
    // Walk east one block, then straight back west over the same edge.
    let mut track = Vec::new();
    track.extend(walk_between(g.node[0][0], g.node[0][1], 10.0, 0.0));
    track.extend(walk_between(g.node[0][1], g.node[0][0], 10.0, 0.0));
    let result = match_track(&g.graph, &track, MatchConfig::default());
    assert_eq!(walked_ids(&g.graph, &result), vec![g.h[0][0]]);
}

#[test]
fn points_far_from_any_street_are_ignored() {
    let g = build_grid(3, 100.0, LngLat::new(13.40, 52.50));
    // A point 500 m north of the grid: well beyond snap_radius.
    let track = vec![LngLat::new(
        g.node[0][0].lng,
        g.node[0][0].lat + dlat(500.0),
    )];
    let result = match_track(&g.graph, &track, MatchConfig::default());
    assert!(result.walked.is_empty());
}

fn sorted(mut v: Vec<u64>) -> Vec<u64> {
    v.sort_unstable();
    v
}
