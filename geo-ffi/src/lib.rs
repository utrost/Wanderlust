//! # wanderlust-geo (geo-ffi)
//!
//! The IO + C ABI layer over [`geo_core`] that the Flutter surface links via
//! FFI (ADR-0003):
//!
//! - [`geojson`] — load a street network from GeoJSON (the tile/OSM pipeline's
//!   interchange format).
//! - [`api::Matcher`] — safe Rust: build from a network, run GPX/point walks.
//! - `ffi` — the `extern "C"` surface (JSON in/out) for `dart:ffi`.
//!
//! ```
//! use wanderlust_geo::api::Matcher;
//! use geo_core::MatchConfig;
//!
//! let geojson = r#"{"type":"FeatureCollection","features":[
//!   {"type":"Feature","id":1,"geometry":{"type":"LineString",
//!     "coordinates":[[13.4300,52.4950],[13.4315,52.4950]]}}]}"#;
//! let gpx = r#"<gpx><trkseg>
//!   <trkpt lat="52.4950" lon="13.4302"></trkpt>
//!   <trkpt lat="52.4950" lon="13.4313"></trkpt>
//! </trkseg></gpx>"#;
//! let m = Matcher::from_geojson(geojson).unwrap();
//! let r = m.match_gpx(gpx, MatchConfig::default());
//! assert_eq!(m.walked_ids(&r), vec![1]);
//! ```

pub mod api;
pub mod ffi;
pub mod geojson;

pub use api::Matcher;
pub use ffi::*;
