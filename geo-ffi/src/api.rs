//! Safe Rust API over geo-core: build a matcher from a street network, then run
//! walks (GPX or raw points) through it. The C ABI in `ffi.rs` is a thin shell
//! over this; keeping the logic here means it is testable without `unsafe`.

use geo_core::graph::Graph;
use geo_core::{gpx, match_track, walked_ids, LngLat, MatchConfig, MatchResult};

use crate::geojson::segments_from_geojson;

/// A loaded, ready-to-query street network for one area.
pub struct Matcher {
    graph: Graph,
}

impl Matcher {
    /// Build from a GeoJSON street network (see [`segments_from_geojson`]).
    pub fn from_geojson(src: &str) -> Result<Self, String> {
        Ok(Self {
            graph: Graph::build(segments_from_geojson(src)?),
        })
    }

    /// Match a GPX track, returning traversed segments (once each).
    pub fn match_gpx(&self, gpx_xml: &str, cfg: MatchConfig) -> Result<MatchResult, String> {
        let tracks = gpx::parse_tracks(gpx_xml)?;
        Ok(geo_core::matcher::match_gpx_tracks(
            &self.graph,
            &tracks,
            cfg,
        ))
    }

    /// Match an ordered list of GPS points.
    pub fn match_points(&self, points: &[LngLat], cfg: MatchConfig) -> MatchResult {
        match_track(&self.graph, points, cfg)
    }

    /// Segment *ids* traversed in a result (sorted).
    pub fn walked_ids(&self, result: &MatchResult) -> Vec<u64> {
        walked_ids(&self.graph, result)
    }
}
