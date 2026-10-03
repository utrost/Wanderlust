use geo_core::{gpx::TrackPoint, matcher::match_gpx_tracks, Graph, LngLat, MatchConfig, Segment};

fn pos(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111_195., y / 111_195.)
}
fn points(coords: &[(f64, f64)]) -> Vec<TrackPoint> {
    let time = chrono::DateTime::parse_from_rfc3339("2026-10-03T10:00:00Z").unwrap();
    coords
        .iter()
        .enumerate()
        .map(|(i, &(x, y))| TrackPoint {
            pos: pos(x, y),
            time: Some(time + chrono::Duration::seconds(i as i64 * 5)),
            accuracy_m: Some(6.),
        })
        .collect()
}
fn graph() -> Graph {
    Graph::build(vec![Segment::new(1, vec![pos(0., 0.), pos(100., 0.)])])
}

#[test]
fn reliable_off_network_movement_is_a_trail_not_street_credit() {
    let result = match_gpx_tracks(
        &graph(),
        &[points(&[(0., 40.), (5., 40.), (10., 40.)])],
        MatchConfig::default(),
    );
    assert!(result.walked.is_empty());
    assert_eq!(result.unmatched, vec![1, 2]);
}
#[test]
fn confirmed_street_has_no_duplicate_gps_trail() {
    let result = match_gpx_tracks(
        &graph(),
        &[points(&[(10., 0.), (20., 0.), (30., 0.)])],
        MatchConfig::default(),
    );
    assert_eq!(result.walked.len(), 1);
    assert!(result.unmatched.is_empty());
}
#[test]
fn trails_break_at_outages_bad_accuracy_jumps_and_segment_boundaries() {
    let a = points(&[(0., 40.), (5., 40.), (10., 40.)]);
    let mut bad = a.clone();
    bad[1].accuracy_m = Some(26.);
    assert!(match_gpx_tracks(&graph(), &[bad], MatchConfig::default())
        .unmatched
        .is_empty());
    let mut gap = a.clone();
    gap[1].time = gap[1].time.map(|t| t + chrono::Duration::seconds(60));
    assert!(match_gpx_tracks(&graph(), &[gap], MatchConfig::default())
        .unmatched
        .is_empty());
    let mut jump = a.clone();
    jump[1].pos = pos(100., 40.);
    assert!(match_gpx_tracks(&graph(), &[jump], MatchConfig::default())
        .unmatched
        .is_empty());
    let result = match_gpx_tracks(
        &graph(),
        &[a[..2].to_vec(), a[2..].to_vec()],
        MatchConfig::default(),
    );
    assert_eq!(result.unmatched, vec![1]);
    let mut untimed = a;
    for p in &mut untimed {
        p.time = None;
    }
    assert!(
        match_gpx_tracks(&graph(), &[untimed], MatchConfig::default())
            .unmatched
            .is_empty()
    );
}
#[test]
fn short_crossing_waits_for_exit_evidence_without_colouring_side_branch() {
    let graph = Graph::build(vec![
        Segment::new(1, vec![pos(0., 0.), pos(15., 0.)]),
        Segment::new(2, vec![pos(15., 0.), pos(21., 0.)]),
        Segment::new(3, vec![pos(21., 0.), pos(50., 0.)]),
        Segment::new(4, vec![pos(15., 0.), pos(15., 40.)]),
    ]);
    let track = points(&[
        (2., 0.),
        (6., 0.),
        (10., 0.),
        (18., 0.),
        (26., 0.),
        (31., 0.),
        (36., 0.),
    ]);
    let early = match_gpx_tracks(&graph, &[track[..5].to_vec()], MatchConfig::default());
    assert!(!early.walked.contains(&1));
    let full = match_gpx_tracks(&graph, &[track], MatchConfig::default());
    assert!(full.walked.contains(&1));
    assert!(full.inferred.contains(&1));
    assert!(!full.walked.contains(&3));
}
