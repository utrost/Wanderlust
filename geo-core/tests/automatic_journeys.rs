use geo_core::{
    automatic::match_automatic_tracks, gpx::TrackPoint, walked_ids, Graph, LngLat, MatchConfig,
    Segment,
};
fn p(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111195., y / 111195.)
}
fn points(coords: &[(f64, f64, i64)]) -> Vec<TrackPoint> {
    let t = chrono::DateTime::parse_from_rfc3339("2026-10-08T10:00:00Z").unwrap();
    coords
        .iter()
        .map(|&(x, y, s)| TrackPoint {
            pos: p(x, y),
            time: Some(t + chrono::Duration::seconds(s)),
            accuracy_m: Some(6.),
        })
        .collect()
}
#[test]
fn mixed_journey_preserves_fast_and_slow_sections() {
    let g = Graph::build(vec![
        Segment::new(1, vec![p(0., 0.), p(100., 0.)]),
        Segment::new(2, vec![p(100., 0.), p(400., 0.)]),
        Segment::new(3, vec![p(400., 0.), p(1200., 0.)]),
    ]);
    let t = points(&[
        (0., 0., 0),
        (5., 0., 5),
        (10., 0., 10),
        (15., 0., 15),
        (40., 0., 18),
        (65., 0., 21),
        (90., 0., 24),
        (120., 0., 27),
        (160., 0., 30),
        (200., 0., 33),
        (260., 0., 36),
        (320., 0., 39),
        (390., 0., 42),
        (460., 0., 45),
        (530., 0., 48),
        (600., 0., 51),
        (670., 0., 54),
    ]);
    let r = match_automatic_tracks(&g, &[t], MatchConfig::default());
    assert_eq!(walked_ids(&g, &r), vec![1, 2, 3]);
}
#[test]
fn reliable_fast_travel_off_network_stays_visible() {
    let g = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(1200., 0.)])]);
    let t = points(&[
        (0., 100., 0),
        (60., 100., 3),
        (120., 100., 6),
        (180., 100., 9),
        (240., 100., 12),
    ]);
    let r = match_automatic_tracks(&g, &[t], MatchConfig::default());
    assert!(r.walked.is_empty());
    assert_eq!(r.unmatched, vec![1, 2, 3, 4]);
}
#[test]
fn spike_outage_and_segment_breaks_do_not_become_routes() {
    let g = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(1200., 0.)])]);
    let t = points(&[
        (0., 100., 0),
        (5., 100., 5),
        (80., 180., 6),
        (10., 100., 7),
        (15., 100., 12),
        (200., 100., 90),
        (205., 100., 95),
    ]);
    let r = match_automatic_tracks(
        &g,
        &[t, points(&[(400., 100., 100), (405., 100., 105)])],
        MatchConfig::default(),
    );
    assert_eq!(r.unmatched, vec![1, 4, 6, 8]);
    assert!(r.walked.is_empty());
}
#[test]
fn short_out_and_back_and_label_free_slow_movement_survive() {
    let g = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(100., 0.)])]);
    let r = match_automatic_tracks(
        &g,
        &[points(&[
            (0., 100., 0),
            (10., 100., 5),
            (20., 100., 10),
            (10., 100., 15),
            (0., 100., 20),
        ])],
        MatchConfig::default(),
    );
    assert_eq!(r.unmatched, vec![1, 2, 3, 4]);
}

#[test]
fn genuine_out_and_back_with_time_to_turn_is_not_a_spike() {
    let g = Graph::build(vec![Segment::new(1, vec![p(0., 0.), p(100., 0.)])]);
    let r = match_automatic_tracks(
        &g,
        &[points(&[(0., 100., 0), (60., 100., 30), (0., 100., 60)])],
        MatchConfig::default(),
    );
    assert_eq!(r.unmatched, vec![1, 2]);
}
