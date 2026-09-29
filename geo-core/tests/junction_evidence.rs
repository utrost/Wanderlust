use geo_core::{
    gpx::TrackPoint, matcher::match_gpx_tracks, walked_ids, Graph, LngLat, MatchConfig, Segment,
};

fn pos(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111_195.0, y / 111_195.0)
}

fn junction() -> Graph {
    Graph::build(vec![
        Segment::new(1, vec![pos(-60.0, 0.0), pos(0.0, 0.0)]),
        Segment::new(2, vec![pos(0.0, 0.0), pos(60.0, 0.0)]),
        Segment::new(3, vec![pos(0.0, 0.0), pos(0.0, 60.0)]),
    ])
}

fn matched(points: &[(f64, f64)]) -> Vec<u64> {
    matched_interval(points, 5)
}

fn matched_interval(points: &[(f64, f64)], seconds: i64) -> Vec<u64> {
    let origin = chrono::DateTime::parse_from_rfc3339("2026-09-29T09:00:00Z").unwrap();
    let track = points
        .iter()
        .enumerate()
        .map(|(i, &(x, y))| TrackPoint {
            pos: pos(x, y),
            time: Some(origin + chrono::Duration::seconds(i as i64 * seconds)),
            accuracy_m: Some(8.0),
        })
        .collect();
    let graph = junction();
    walked_ids(
        &graph,
        &match_gpx_tracks(&graph, &[track], MatchConfig::default()),
    )
}

#[test]
fn sustained_junction_bias_does_not_paint_a_perpendicular_street() {
    let points = [
        (-45., 0.),
        (-35., 1.),
        (-25., 2.),
        (-15., 3.),
        (-4., 10.),
        (0., 12.),
        (4., 13.),
        (15., 2.),
        (25., 0.),
        (35., 0.),
    ];
    // Multiple consecutive fixes are closer to the branch, yet their travel
    // direction remains across it. Check live prefixes, not only the final trace.
    for end in 2..=points.len() {
        assert!(
            !matched(&points[..end]).contains(&3),
            "false branch at prefix {end}"
        );
    }
    assert_eq!(matched(&points), vec![1, 2]);
}

#[test]
fn stationary_jitter_does_not_explore_a_street() {
    assert!(matched(&[(0., 8.), (1., 10.), (-1., 12.), (0., 9.), (1., 8.)]).is_empty());
}

#[test]
fn real_turn_still_paints_the_branch() {
    assert_eq!(
        matched(&[
            (-45., 0.),
            (-35., 0.),
            (-25., 0.),
            (-15., 0.),
            (-5., 0.),
            (0., 5.),
            (0., 15.),
            (0., 25.),
            (0., 35.)
        ]),
        vec![1, 3]
    );
}

#[test]
fn reversing_direction_still_counts_the_walked_street_once() {
    assert_eq!(
        matched(&[
            (-45., 0.),
            (-35., 0.),
            (-25., 0.),
            (-15., 0.),
            (-25., 0.),
            (-35., 0.)
        ]),
        vec![1]
    );
}

#[test]
fn poor_accuracy_fixes_do_not_confirm_streets_or_bridge_gaps() {
    let graph = junction();
    let gpx = "<gpx xmlns:wl='https://wanderlust.local/gpx/1'><trk><trkseg>
        <trkpt lat='0.0001' lon='0'><time>2026-09-29T09:00:00Z</time><extensions><wl:accuracy>60</wl:accuracy></extensions></trkpt>
        <trkpt lat='0.0002' lon='0'><time>2026-09-29T09:00:05Z</time><extensions><wl:accuracy>60</wl:accuracy></extensions></trkpt>
        <trkpt lat='0.0003' lon='0'><time>2026-09-29T09:00:10Z</time><extensions><wl:accuracy>60</wl:accuracy></extensions></trkpt>
        </trkseg></trk></gpx>";
    let tracks = geo_core::gpx::parse_tracks(gpx).unwrap();
    assert!(match_gpx_tracks(&graph, &tracks, MatchConfig::default())
        .walked
        .is_empty());
}

#[test]
fn dense_sampling_does_not_make_a_false_branch_confirm_faster() {
    let coarse = [
        (-45., 0.),
        (-35., 1.),
        (-25., 2.),
        (-15., 3.),
        (-4., 10.),
        (0., 12.),
        (4., 13.),
        (15., 2.),
        (25., 0.),
        (35., 0.),
    ];
    let mut dense = Vec::new();
    for pair in coarse.windows(2) {
        for step in 0..5 {
            let t = step as f64 / 5.0;
            dense.push((
                pair[0].0 + (pair[1].0 - pair[0].0) * t,
                pair[0].1 + (pair[1].1 - pair[0].1) * t,
            ));
        }
    }
    for end in 2..=dense.len() {
        assert!(!matched_interval(&dense[..end], 1).contains(&3));
    }
    assert_eq!(matched_interval(&dense, 1), vec![1, 2]);
}
