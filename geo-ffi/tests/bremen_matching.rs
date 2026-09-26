//! Real OSM geometry, explicitly synthetic traces. This is a regression check,
//! not a claim of real GPS accuracy. Expected edges come from an independent
//! OSM-node route builder in tools/evaluate_matching.py.
use geo_core::MatchConfig;
use wanderlust_geo::api::Matcher;

#[test]
fn bremen_clean_routes_have_no_phantom_edges_and_useful_coverage() {
    let matcher = Matcher::from_geojson(include_str!(
        "../../app/assets/geo/bremen-center.streets.geojson"
    ))
    .unwrap();
    for (gpx, expected) in [
        (
            include_str!("../../data/bremen/evaluation/market-to-wall.synthetic.gpx"),
            include_str!("../../data/bremen/evaluation/market-to-wall.expected.json"),
        ),
        (
            include_str!("../../data/bremen/evaluation/schlachte.synthetic.gpx"),
            include_str!("../../data/bremen/evaluation/schlachte.expected.json"),
        ),
        (
            include_str!("../../data/bremen/evaluation/ostertor.synthetic.gpx"),
            include_str!("../../data/bremen/evaluation/ostertor.expected.json"),
        ),
    ] {
        let expected: Vec<u64> = serde_json::from_str(expected).unwrap();
        let result = matcher.match_gpx(gpx, MatchConfig::default()).unwrap();
        let actual = matcher.walked_ids(&result);
        assert!(
            actual.iter().all(|id| expected.contains(id)),
            "phantom streets: {actual:?}"
        );
        assert!(
            actual.len() * 2 >= expected.len(),
            "less than half the expected edges matched"
        );
    }
}
