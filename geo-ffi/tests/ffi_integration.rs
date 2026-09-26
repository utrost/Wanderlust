//! End-to-end: a real-coordinate GeoJSON street network + a GPX walk in →
//! correct walked segment ids out, through both the safe API and the C ABI.
//! This is the "import a GPX, watch real streets light up" path in miniature.

use std::ffi::{CStr, CString};

use geo_core::MatchConfig;
use wanderlust_geo::api::Matcher;
use wanderlust_geo::{
    wanderlust_match_gpx, wanderlust_matcher_free, wanderlust_matcher_from_geojson,
    wanderlust_string_free,
};

const GEOJSON: &str = include_str!("../fixtures/kreuzberg-sample.geojson");
const GPX: &str = include_str!("../fixtures/walk-goerli.gpx");
const EXPECTED: &str = include_str!("../fixtures/expected_walk_ids.json");

fn expected_ids() -> Vec<u64> {
    serde_json::from_str(EXPECTED).unwrap()
}

#[test]
fn safe_api_matches_walk_to_the_expected_streets() {
    let matcher = Matcher::from_geojson(GEOJSON).expect("load network");
    let result = matcher.match_gpx(GPX, MatchConfig::default()).unwrap();
    assert_eq!(matcher.walked_ids(&result), expected_ids());
    // A clean walk down connected streets: nothing should be rejected.
    assert_eq!(result.gaps_rejected, 0);
}

#[test]
fn c_abi_round_trips_geojson_and_gpx_to_json() {
    let geojson = CString::new(GEOJSON).unwrap();
    let gpx = CString::new(GPX).unwrap();

    unsafe {
        let matcher = wanderlust_matcher_from_geojson(geojson.as_ptr());
        assert!(!matcher.is_null(), "matcher should build");

        let out = wanderlust_match_gpx(matcher, gpx.as_ptr());
        assert!(!out.is_null(), "match should return JSON");

        let json = CStr::from_ptr(out).to_str().unwrap();
        let v: serde_json::Value = serde_json::from_str(json).unwrap();
        let walked: Vec<u64> = v["walked"]
            .as_array()
            .unwrap()
            .iter()
            .map(|x| x.as_u64().unwrap())
            .collect();
        assert_eq!(walked, expected_ids());
        assert_eq!(v["gaps_rejected"].as_u64(), Some(0));

        wanderlust_string_free(out);
        wanderlust_matcher_free(matcher);
    }
}

#[test]
fn c_abi_is_null_safe() {
    unsafe {
        assert!(wanderlust_matcher_from_geojson(std::ptr::null()).is_null());
        assert!(wanderlust_match_gpx(std::ptr::null_mut(), std::ptr::null()).is_null());
        // Freeing nulls must not crash.
        wanderlust_matcher_free(std::ptr::null_mut());
        wanderlust_string_free(std::ptr::null_mut());
    }
}

#[test]
fn malformed_gpx_returns_an_error_over_the_abi() {
    unsafe {
        let network = CString::new(GEOJSON).unwrap();
        let matcher = wanderlust_matcher_from_geojson(network.as_ptr());
        let input = CString::new("<gpx>").unwrap();
        let out = wanderlust_match_gpx(matcher, input.as_ptr());
        assert!(!out.is_null());
        let json: serde_json::Value =
            serde_json::from_str(CStr::from_ptr(out).to_str().unwrap()).unwrap();
        assert!(json["error"].as_str().unwrap().contains("invalid GPX"));
        wanderlust_string_free(out);
        wanderlust_matcher_free(matcher);
    }
}
