use geo_core::{
    gpx::TrackPoint, graph::StreetInfo, matcher::match_gpx_tracks, Graph, LngLat, MatchConfig,
    Segment,
};

fn p(x: f64, y: f64) -> LngLat {
    LngLat::new(x / 111195., y / 111195.)
}
fn edge(id: u64, a: (f64, f64), b: (f64, f64), name: &str, kind: &str) -> Segment {
    let mut s = Segment::new(id, vec![p(a.0, a.1), p(b.0, b.1)]);
    s.street = StreetInfo {
        name: name.into(),
        highway: kind.into(),
        ..StreetInfo::default()
    };
    s
}
fn track(coords: &[(f64, f64)], seconds: i64) -> Vec<TrackPoint> {
    let t = chrono::DateTime::parse_from_rfc3339("2026-10-07T10:00:00Z").unwrap();
    coords
        .iter()
        .enumerate()
        .map(|(i, &(x, y))| TrackPoint {
            pos: p(x, y),
            time: Some(t + chrono::Duration::seconds(i as i64 * seconds)),
            accuracy_m: Some(10.),
        })
        .collect()
}
fn cfg() -> MatchConfig {
    MatchConfig {
        cycling: true,
        max_speed_mps: 15.,
        ..MatchConfig::default()
    }
}

#[test]
fn parallel_carriageways_credit_one_coherent_street_not_both_lanes() {
    let g = Graph::build(vec![
        edge(1, (0., 0.), (120., 0.), "Main", "secondary"),
        edge(2, (0., 12.), (120., 12.), "Main", "secondary"),
    ]);
    let t = track(
        &[
            (10., 6.),
            (25., 6.),
            (40., 6.),
            (55., 6.),
            (70., 6.),
            (85., 6.),
        ],
        3,
    );
    let r = match_gpx_tracks(&g, &[t], cfg());
    assert_eq!(r.walked.len(), 1);
    assert!(r.inferred.is_empty());
    assert!(r.unmatched.is_empty());
}

#[test]
fn shared_name_does_not_merge_separate_levels_or_distant_roads() {
    for (separation, bridge) in [(12., true), (40., false)] {
        let a = edge(1, (0., 0.), (120., 0.), "Main", "secondary");
        let mut b = edge(2, (0., separation), (120., separation), "Main", "secondary");
        if bridge {
            b.street.bridge = "yes".into();
            b.street.layer = "1".into();
        }
        let g = Graph::build(vec![a, b]);
        let t = track(
            &[
                (10., separation / 2.),
                (25., separation / 2.),
                (40., separation / 2.),
                (55., separation / 2.),
            ],
            5,
        );
        let r = match_gpx_tracks(&g, &[t], cfg());
        assert!(r.walked.is_empty());
        assert!(!r.unmatched.is_empty());
    }
}

#[test]
fn unrelated_parallel_streets_remain_ambiguous() {
    let g = Graph::build(vec![
        edge(1, (0., 0.), (120., 0.), "Main", "secondary"),
        edge(2, (0., 12.), (120., 12.), "Other", "secondary"),
    ]);
    let r = match_gpx_tracks(
        &g,
        &[track(&[(10., 6.), (25., 6.), (40., 6.), (55., 6.)], 5)],
        cfg(),
    );
    assert!(r.walked.is_empty());
}

#[test]
fn same_street_short_sections_use_continuous_movement_without_crediting_spurs() {
    let mut edges: Vec<_> = (0..8)
        .map(|i| {
            edge(
                i + 1,
                (i as f64 * 12., 0.),
                ((i + 1) as f64 * 12., 0.),
                "Main",
                "secondary",
            )
        })
        .collect();
    edges.push(edge(99, (48., 0.), (48., 40.), "Main", "secondary"));
    let g = Graph::build(edges);
    let coords: Vec<_> = (0..8).map(|i| (6. + i as f64 * 12., 3.)).collect();
    let r = match_gpx_tracks(&g, &[track(&coords, 3)], cfg());
    assert_eq!(r.walked.len(), 8);
    assert!(!r.walked.contains(&8));
    assert!(r.inferred.is_empty());
}

#[test]
fn cycling_access_and_shared_paths_affect_candidates_without_changing_walks() {
    let mut path = edge(1, (0., 0.), (120., 0.), "", "footway");
    path.street.bicycle = "no".into();
    let road = edge(2, (0., 10.), (120., 10.), "Main", "secondary");
    let points = track(&[(10., 5.), (25., 5.), (40., 5.), (55., 5.)], 6);
    let g = Graph::build(vec![path.clone(), road.clone()]);
    assert_eq!(
        match_gpx_tracks(&g, std::slice::from_ref(&points), cfg()).walked,
        [1].into_iter().collect()
    );
    assert!(
        match_gpx_tracks(&g, std::slice::from_ref(&points), MatchConfig::default())
            .walked
            .is_empty()
    );
    path.street.bicycle = "designated".into();
    let g = Graph::build(vec![path, road]);
    let r = match_gpx_tracks(
        &g,
        &[track(&[(10., 1.), (25., 1.), (40., 1.), (55., 1.)], 3)],
        cfg(),
    );
    assert_eq!(r.walked, [0].into_iter().collect());
}

#[test]
fn corridor_evidence_never_bridges_long_outages_or_stationary_jitter() {
    let g = Graph::build(vec![
        edge(1, (0., 0.), (120., 0.), "Main", "secondary"),
        edge(2, (0., 12.), (120., 12.), "Main", "secondary"),
    ]);
    for (coords, interval) in [
        (vec![(10., 6.), (25., 6.), (40., 6.)], 60),
        (vec![(10., 6.), (11., 6.), (10., 6.)], 5),
    ] {
        let r = match_gpx_tracks(&g, &[track(&coords, interval)], cfg());
        assert!(r.walked.is_empty());
        assert!(r.inferred.is_empty());
    }
}

#[test]
fn named_roadside_cycle_path_can_resolve_street_identity_but_service_lane_cannot() {
    for (kind, expected) in [("cycleway", 1), ("service", 0)] {
        let g = Graph::build(vec![
            edge(1, (0., 0.), (120., 0.), "Main", "secondary"),
            edge(2, (0., 12.), (120., 12.), "Main", kind),
        ]);
        let r = match_gpx_tracks(
            &g,
            &[track(&[(10., 6.), (25., 6.), (40., 6.), (55., 6.)], 5)],
            cfg(),
        );
        assert_eq!(r.walked.len(), expected, "{kind}");
    }
}

#[test]
fn skipped_sections_are_estimates_between_supported_sections() {
    let g = Graph::build(
        (0..12)
            .map(|i| {
                edge(
                    i + 1,
                    (i as f64 * 10., 0.),
                    ((i + 1) as f64 * 10., 0.),
                    "Main",
                    "secondary",
                )
            })
            .collect(),
    );
    let r = match_gpx_tracks(
        &g,
        &[track(
            &[(5., 3.), (25., 3.), (45., 3.), (65., 3.), (85., 3.)],
            3,
        )],
        cfg(),
    );
    assert!(!r.walked.is_empty());
    assert_eq!(r.inferred, [1, 3, 5, 7].into_iter().collect());
    assert!(r.inferred.is_subset(&r.walked));
    assert!(!r.walked.contains(&9)); // Never extend beyond the final observation.
}

#[test]
fn endpoint_jitter_does_not_credit_an_untravelled_continuation() {
    let g = Graph::build(vec![
        edge(1, (-50., 0.), (0., 0.), "Main", "secondary"),
        edge(2, (0., 0.), (100., 0.), "Main", "secondary"),
    ]);
    let r = match_gpx_tracks(
        &g,
        &[track(&[(-1., 1.), (10., 1.), (25., 1.), (40., 1.)], 5)],
        cfg(),
    );
    assert_eq!(r.walked, [1].into_iter().collect());
}
