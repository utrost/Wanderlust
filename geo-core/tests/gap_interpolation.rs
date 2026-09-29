use geo_core::{
    gpx::TrackPoint, matcher::match_gpx_tracks, walked_ids, Graph, LngLat, MatchConfig, Segment,
};
fn pos(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111_195.0, y / 111_195.0)
}
fn network(alternative: bool) -> Graph {
    let mut edges = vec![
        Segment::new(1, vec![pos(0., 0.), pos(30., 0.)]),
        Segment::new(2, vec![pos(30., 0.), pos(60., 0.)]),
        Segment::new(3, vec![pos(60., 0.), pos(100., 0.)]),
        Segment::new(4, vec![pos(30., 0.), pos(30., 40.)]),
    ];
    if alternative {
        edges.push(Segment::new(
            5,
            vec![pos(30., 0.), pos(45., 10.), pos(60., 0.)],
        ));
    }
    Graph::build(edges)
}
fn track() -> Vec<TrackPoint> {
    let origin = chrono::DateTime::parse_from_rfc3339("2026-09-29T09:00:00Z").unwrap();
    [
        (5., 0),
        (15., 5),
        (25., 10),
        (45., 20),
        (65., 30),
        (75., 35),
        (85., 40),
    ]
    .into_iter()
    .map(|(x, t)| TrackPoint {
        pos: pos(x, 0.),
        time: Some(origin + chrono::Duration::seconds(t)),
        accuracy_m: Some(6.),
    })
    .collect()
}
fn ids(graph: &Graph, tracks: &[Vec<TrackPoint>], enabled: bool) -> Vec<u64> {
    walked_ids(
        graph,
        &match_gpx_tracks(
            graph,
            tracks,
            MatchConfig {
                fill_small_gaps: enabled,
                ..MatchConfig::default()
            },
        ),
    )
}
#[test]
fn opt_in_fills_only_the_missing_connector_after_both_anchors_are_confirmed() {
    let graph = network(false);
    let points = track();
    assert_eq!(
        ids(&graph, std::slice::from_ref(&points), false),
        vec![1, 3]
    );
    assert_eq!(
        ids(&graph, std::slice::from_ref(&points), true),
        vec![1, 2, 3]
    );
    for end in 1..=5 {
        assert!(!ids(&graph, &[points[..end].to_vec()], true).contains(&2));
    }
    assert_eq!(ids(&graph, &[points[..6].to_vec()], true), vec![1, 2, 3]);
}
#[test]
fn plausible_alternative_route_is_not_guessed() {
    assert_eq!(ids(&network(true), &[track()], true), vec![1, 3]);
}
#[test]
fn rejects_outages_bad_accuracy_untimed_traces_and_segment_boundaries() {
    let graph = network(false);
    let mut poor = track();
    poor[3].accuracy_m = Some(60.);
    assert_eq!(ids(&graph, &[poor], true), vec![1, 3]);
    let mut outage = track();
    for p in &mut outage[3..] {
        p.time = p.time.map(|t| t + chrono::Duration::seconds(60));
    }
    assert_eq!(ids(&graph, &[outage], true), vec![1, 3]);
    let mut untimed = track();
    for p in &mut untimed {
        p.time = None;
    }
    assert_eq!(ids(&graph, &[untimed], true), vec![1, 3]);
    let points = track();
    assert_eq!(
        ids(&graph, &[points[..3].to_vec(), points[3..].to_vec()], true),
        vec![1, 3]
    );
    let mut backwards = track();
    backwards[3].time = backwards[1].time;
    assert_eq!(ids(&graph, &[backwards], true), vec![1, 3]);
}
#[test]
fn rejects_a_geometric_detour_even_when_it_is_the_only_graph_route() {
    let graph = Graph::build(vec![
        Segment::new(1, vec![pos(0., 0.), pos(30., 0.)]),
        Segment::new(2, vec![pos(30., 0.), pos(45., 25.), pos(60., 0.)]),
        Segment::new(3, vec![pos(60., 0.), pos(100., 0.)]),
    ]);
    assert_eq!(ids(&graph, &[track()], true), vec![1, 3]);
}
#[test]
fn full_projected_route_cost_and_disconnected_topology_are_respected() {
    let graph = network(false);
    // Intermediate edge alone is 30m, but the complete connector is 80m.
    assert!(graph
        .unique_connection(0, 2, pos(5., 0.), pos(85., 0.), 75.)
        .is_none());
    let separated = Graph::build(vec![
        Segment::new(1, vec![pos(0., 0.), pos(30., 0.)]).with_nodes(1, 2),
        Segment::new(2, vec![pos(30., 0.), pos(60., 0.)]).with_nodes(3, 4),
        Segment::new(3, vec![pos(60., 0.), pos(100., 0.)]).with_nodes(5, 6),
    ]);
    assert_eq!(ids(&separated, &[track()], true), vec![1, 3]);
}

#[test]
fn off_route_excursion_does_not_become_a_straight_connection() {
    let graph = network(false);
    let mut points = track();
    points[3].pos = pos(45., 25.);
    points[3].time = points[3].time.map(|t| t + chrono::Duration::seconds(2));
    for p in &mut points[4..] {
        p.time = p.time.map(|t| t + chrono::Duration::seconds(4));
    }
    assert_eq!(ids(&graph, &[points], true), vec![1, 3]);
}

#[test]
fn review_provenance_distinguishes_inference_and_direct_evidence_across_segments() {
    let graph = network(false);
    let config = MatchConfig {
        fill_small_gaps: true,
        ..MatchConfig::default()
    };
    let result = match_gpx_tracks(&graph, &[track()], config);
    assert_eq!(result.inferred, [1usize].into_iter().collect());
    assert!(result.inferred.is_subset(&result.walked));
    let mut sparse = track();
    sparse.remove(3);
    let default_fill = match_gpx_tracks(&graph, &[sparse], MatchConfig::default());
    assert_eq!(default_fill.inferred, [1usize].into_iter().collect());
    // Later direct observations of the middle street override its earlier inference.
    let mut middle = track();
    for (i, p) in middle.iter_mut().enumerate() {
        p.pos = pos(34. + i as f64 * 3., 0.);
    }
    let result = match_gpx_tracks(&graph, &[track(), middle], config);
    assert!(result.inferred.is_empty());
}
