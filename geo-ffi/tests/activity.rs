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
