//! # Wanderlust geo-core
//!
//! The platform-agnostic heart of Wanderlust (see ADR-0003): the two hard,
//! correctness-critical pieces — the routing graph and map-matching — plus the
//! local data model, in fast, portable Rust. The Flutter surface links this via
//! FFI; nothing here knows about UI or platform.
//!
//! Phase 0 status: the map-matching spike and its don't-paint-what-you-didn't-
//! walk guardrail (ADR-0001) are implemented and tested. Storage wiring, a real
//! spatial index, and the FFI bridge are deliberately still ahead.
//!
//! ```
//! use geo_core::geometry::LngLat;
//! use geo_core::graph::{Graph, Segment};
//! use geo_core::matcher::{match_track, MatchConfig};
//!
//! // Two connected streets meeting at a shared junction.
//! let graph = Graph::build(vec![
//!     Segment::new(1, vec![LngLat::new(13.400, 52.500), LngLat::new(13.401, 52.500)]),
//!     Segment::new(2, vec![LngLat::new(13.401, 52.500), LngLat::new(13.402, 52.500)]),
//! ]);
//! let track = vec![LngLat::new(13.4005, 52.5000), LngLat::new(13.4015, 52.5000)];
//! let result = match_track(&graph, &track, MatchConfig::default());
//! assert_eq!(result.walked.len(), 2);
//! ```

pub mod geometry;
pub mod gpx;
pub mod graph;
pub mod matcher;
pub mod schema;
mod sequence;

pub use geometry::LngLat;
pub use graph::{Graph, Segment};
pub use matcher::{match_track, walked_ids, MatchConfig, MatchResult};
