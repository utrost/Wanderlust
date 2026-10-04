use geo_core::{gpx::TrackPoint, matcher::match_gpx_tracks, Graph, LngLat, MatchConfig, Segment};
fn p(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111195.0, y / 111195.0)
}
fn track(coords: &[(f64, f64)], accuracy: f64, interval: i64) -> Vec<TrackPoint> {
    let t = chrono::DateTime::parse_from_rfc3339("2026-10-04T10:00:00Z").unwrap();
    coords
        .iter()
        .enumerate()
        .map(|(i, &(x, y))| TrackPoint {
            pos: p(x, y),
            time: Some(t + chrono::Duration::seconds(i as i64 * interval)),
            accuracy_m: Some(accuracy),
        })
        .collect()
}
#[test]
fn later_clear_evidence_resolves_earlier_parallel_ambiguity() {
    let graph = Graph::build(vec![
        Segment::new(1, vec![p(0., 0.), p(100., 0.)]),
        Segment::new(2, vec![p(0., 10.), p(100., 10.)]),
    ]);
    let result = match_gpx_tracks(
        &graph,
        &[track(
            &[
                (5., 5.),
                (15., 5.),
                (25., 4.),
                (35., 1.),
                (45., 0.),
                (55., 0.),
            ],
            6.,
            10,
        )],
        MatchConfig::default(),
    );
    assert_eq!(result.walked, [0].into_iter().collect());
    assert!(result.inferred.is_empty());
}
#[test]
fn sustained_moderately_uncertain_movement_can_support_a_street() {
    let graph = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(100., 0.)])]);
    for accuracy in [24., 26., 35., 45.] {
        let result = match_gpx_tracks(
            &graph,
            &[track(
                &[(5., 2.), (15., 2.), (25., 2.), (35., 2.), (45., 2.)],
                accuracy,
                10,
            )],
            MatchConfig::default(),
        );
        assert_eq!(
            result.walked,
            [0].into_iter().collect(),
            "accuracy {accuracy}"
        );
    }
    let jitter = match_gpx_tracks(
        &graph,
        &[track(&[(5., 2.), (7., 2.), (5., 2.), (8., 2.)], 35., 5)],
        MatchConfig::default(),
    );
    assert!(jitter.walked.is_empty());
}
#[test]
fn walking_intervals_do_not_change_a_clear_route() {
    let graph = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(500., 0.)])]);
    for interval in [2, 5, 10, 20] {
        let coords: Vec<_> = (0..10)
            .map(|i| (5. + i as f64 * interval as f64 * 1.3, 2.))
            .collect();
        let result = match_gpx_tracks(
            &graph,
            &[track(&coords, 8., interval)],
            MatchConfig::default(),
        );
        assert_eq!(result.walked, [0].into_iter().collect());
    }
}
#[test]
fn geometric_crossing_cannot_create_a_network_transition() {
    let graph = Graph::build(vec![
        Segment::new(1, vec![p(0., 0.), p(100., 0.)]).with_nodes(1, 2),
        Segment::new(2, vec![p(50., -50.), p(50., 50.)]).with_nodes(3, 4),
    ]);
    assert!(graph
        .projected_distance(0, 1, p(45., 0.), p(50., 5.), 100.)
        .is_none());
}
