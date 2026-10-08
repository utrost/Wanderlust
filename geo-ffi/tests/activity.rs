use geo_core::MatchConfig;
use wanderlust_geo::api::Matcher;
#[test]
fn explicit_cycle_metadata_selects_policy_without_leaking_between_calls() {
    let network = r#"{"type":"FeatureCollection","features":[{"type":"Feature","id":1,"properties":{},"geometry":{"type":"LineString","coordinates":[[0,0],[0.01,0]]}}]}"#;
    let matcher = Matcher::from_geojson(network).unwrap();
    let gpx = r#"<gpx xmlns:wl="https://wanderlust.local/gpx/1"><trk><trkseg>
    <trkpt lon="0.001" lat="0"><time>2026-10-04T10:00:00Z</time></trkpt>
    <trkpt lon="0.0013" lat="0"><time>2026-10-04T10:00:05Z</time></trkpt>
    <trkpt lon="0.0016" lat="0"><time>2026-10-04T10:00:10Z</time></trkpt>
    </trkseg></trk>ACTIVITY</gpx>"#;
    for (extension, count) in [
        ("", 0),
        (
            "<extensions><wl:activity>cycle</wl:activity></extensions>",
            1,
        ),
        ("<extensions><activity>cycle</activity></extensions>", 0),
        (
            "<extensions><wl:activity>walk</wl:activity></extensions>",
            0,
        ),
    ] {
        let r = matcher
            .match_gpx(&gpx.replace("ACTIVITY", extension), MatchConfig::default())
            .unwrap();
        assert_eq!(r.walked.len(), count);
    }
}

#[test]
fn road_tags_reach_matching_and_activity_does_not_leak_between_calls() {
    let network = r#"{"type":"FeatureCollection","features":[
      {"type":"Feature","id":1,"properties":{"highway":"footway","bicycle":"no"},"geometry":{"type":"LineString","coordinates":[[0,0],[0.001,0]]}},
      {"type":"Feature","id":2,"properties":{"highway":"secondary"},"geometry":{"type":"LineString","coordinates":[[0,0.00009],[0.001,0.00009]]}}
    ]}"#;
    let matcher = Matcher::from_geojson(network).unwrap();
    let gpx = r#"<gpx xmlns:wl="https://wanderlust.local/gpx/1"><extensions><wl:activity>ACTIVITY</wl:activity></extensions><trk><trkseg>
      <trkpt lon="0.0001" lat="0.000045"><time>2026-10-07T10:00:00Z</time><extensions><wl:accuracy>10</wl:accuracy></extensions></trkpt>
      <trkpt lon="0.0002" lat="0.000045"><time>2026-10-07T10:00:05Z</time><extensions><wl:accuracy>10</wl:accuracy></extensions></trkpt>
      <trkpt lon="0.0003" lat="0.000045"><time>2026-10-07T10:00:10Z</time><extensions><wl:accuracy>10</wl:accuracy></extensions></trkpt>
    </trkseg></trk></gpx>"#;
    for (activity, expected) in [("walk", vec![]), ("cycle", vec![2]), ("walk", vec![])] {
        let r = matcher
            .match_gpx(&gpx.replace("ACTIVITY", activity), MatchConfig::default())
            .unwrap();
        assert_eq!(matcher.walked_ids(&r), expected);
    }
}

#[test]
fn automatic_matching_overrides_legacy_labels_without_mutating_them() {
    let network = r#"{"type":"FeatureCollection","features":[{"type":"Feature","id":1,"properties":{},"geometry":{"type":"LineString","coordinates":[[0,0],[0.01,0]]}}]}"#;
    let matcher = Matcher::from_geojson(network).unwrap();
    for label in ["walk", "cycle", "auto"] {
        let xml = format!(
            r#"<gpx xmlns:wl="https://wanderlust.local/gpx/1"><extensions><wl:activity>{label}</wl:activity><wl:matching>auto</wl:matching></extensions><trk><trkseg>
        <trkpt lon="0.001" lat="0"><time>2026-10-08T10:00:00Z</time></trkpt>
        <trkpt lon="0.0015" lat="0"><time>2026-10-08T10:00:03Z</time></trkpt>
        <trkpt lon="0.002" lat="0"><time>2026-10-08T10:00:06Z</time></trkpt>
        <trkpt lon="0.0025" lat="0"><time>2026-10-08T10:00:09Z</time></trkpt>
        </trkseg></trk></gpx>"#
        );
        assert_eq!(
            matcher.walked_ids(&matcher.match_gpx(&xml, MatchConfig::default()).unwrap()),
            vec![1]
        );
    }
}
