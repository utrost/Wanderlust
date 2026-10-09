use geo_core::{
    automatic::match_automatic_tracks, gpx::TrackPoint, walked_ids, Graph, LngLat, MatchConfig,
    Segment,
};

fn p(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111195., y / 111195.)
}
fn edge(id: u64, y: f64, highway: &str) -> Segment {
    let mut s = Segment::new(id, vec![p(0., y), p(1000., y)]);
    s.street.highway = highway.into();
    s
}
fn track(step: f64, seconds: i64) -> Vec<TrackPoint> {
    let start = chrono::DateTime::parse_from_rfc3339("2026-10-09T12:00:00Z").unwrap();
    (0..10)
        .map(|i| TrackPoint {
            pos: p(30. + i as f64 * step, 0.),
            time: Some(start + chrono::Duration::seconds(i * seconds)),
            accuracy_m: Some(10.),
        })
        .collect()
}
#[test]
fn dense_rails_do_not_crowd_a_walking_path_out_of_candidates() {
    let mut edges: Vec<_> = (1..=12)
        .map(|id| edge(id, id as f64 * 0.5, "railway"))
        .collect();
    edges.push(edge(100, -12., "footway"));
    let g = Graph::build(edges);
    let r = match_automatic_tracks(&g, &[track(10., 5)], MatchConfig::default());
    assert_eq!(walked_ids(&g, &r), vec![100]);
    assert!(r.unmatched.is_empty());
}
#[test]
fn vehicle_travel_can_still_match_rail_beside_dense_footpaths() {
    let mut edges: Vec<_> = (1..=12)
        .map(|id| edge(id, id as f64 * 0.5, "footway"))
        .collect();
    edges.push(edge(100, -12., "railway"));
    let g = Graph::build(edges);
    let r = match_automatic_tracks(&g, &[track(60., 3)], MatchConfig::default());
    assert_eq!(walked_ids(&g, &r), vec![100]);
    assert!(r.unmatched.is_empty());
}
#[test]
fn equally_plausible_streets_remain_unresolved_beside_rails() {
    let g = Graph::build(vec![
        edge(1, 0., "railway"),
        edge(2, -10., "footway"),
        edge(3, 10., "footway"),
    ]);
    let r = match_automatic_tracks(&g, &[track(10., 5)], MatchConfig::default());
    assert!(r.walked.is_empty());
    assert_eq!(r.unmatched.len(), 9);
}

#[test]
fn nearby_rail_does_not_redraw_a_short_pair_beside_confirmed_path() {
    let g = Graph::build(vec![edge(1, 0., "railway"), edge(100, -5., "footway")]);
    let first = track(10., 5);
    let mut short = track(5., 5);
    short.truncate(2); // Too short to establish its own direction baseline.
    let r = match_automatic_tracks(&g, &[first, short], MatchConfig::default());
    assert_eq!(walked_ids(&g, &r), vec![100]);
    assert!(r.unmatched.is_empty());
}

#[test]
fn unconfirmed_parallel_path_still_keeps_its_gps_evidence() {
    let g = Graph::build(vec![
        edge(1, -20., "footway"),
        edge(2, 0., "footway"),
        edge(3, 1., "railway"),
    ]);
    let mut first = track(10., 5);
    for fix in &mut first {
        fix.pos.lat = -20. / 111195.;
    }
    let mut short = track(5., 5);
    short.truncate(2);
    let r = match_automatic_tracks(&g, &[first, short], MatchConfig::default());
    assert_eq!(walked_ids(&g, &r), vec![1]);
    assert_eq!(r.unmatched, vec![11]);
}
