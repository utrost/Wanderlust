//! Pragmatic map-matching: snap GPS points to the nearest street edge, then
//! fill the gaps between consecutive matches with the shortest path — *but only
//! when that path is plausible*. Per ADR-0001, a street lit that you never
//! walked is worse than a street left dark, so the guardrail refuses to fill a
//! gap when the connecting route is an implausible detour relative to how far
//! the GPS actually moved. See ADR-0001 for the rationale.

use std::collections::HashSet;

use crate::geometry::{haversine_m, LngLat};
use crate::graph::Graph;

/// Tunables for a matching run.
#[derive(Debug, Clone, Copy)]
pub struct MatchConfig {
    /// A GPS point further than this from any street is treated as unmatched
    /// (noise / off-network), not snapped.
    pub snap_radius_m: f64,
    /// Refuse to fill a gap whose shortest connecting path exceeds this multiple
    /// of the straight-line distance the walker actually moved.
    pub max_fill_detour_ratio: f64,
    /// Absolute ceiling on a single gap fill, metres — caps damage from a wild
    /// GPS jump even when the ratio would allow it.
    pub max_fill_len_m: f64,
}

impl Default for MatchConfig {
    fn default() -> Self {
        Self {
            snap_radius_m: 25.0,
            max_fill_detour_ratio: 2.5,
            max_fill_len_m: 300.0,
        }
    }
}

/// The outcome of matching one track: the set of segment *indices* the walker
/// plausibly traversed, and a tally of how many gaps the guardrail rejected
/// (useful as a health signal — lots of rejections means bad GPS or a graph
/// hole, not necessarily a bug).
#[derive(Debug, Default, Clone)]
pub struct MatchResult {
    pub walked: HashSet<usize>,
    pub gaps_filled: usize,
    pub gaps_rejected: usize,
}

/// Match one ordered GPS track against `graph`. Each traversed segment is
/// reported once, regardless of how many points fell on it or how many times
/// the walker doubled back within this single track — a segment is either
/// walked this session or it isn't. Accumulating counts across sessions is the
/// caller's job (add 1 per segment in `walked` to the persistent tally).
pub fn match_track(graph: &Graph, points: &[LngLat], cfg: MatchConfig) -> MatchResult {
    // 1. Snap each point; keep the snapped point's position for gap sizing.
    //    Compress runs of the same segment so a slow walk down one street is a
    //    single entry, not hundreds.
    let mut seq: Vec<(usize, LngLat)> = Vec::new();
    for &p in points {
        if let Some((seg, _dist)) = graph.nearest_segment(p, cfg.snap_radius_m) {
            if seq.last().is_none_or(|&(last, _)| last != seg) {
                seq.push((seg, p));
            }
        }
    }

    let mut result = MatchResult::default();
    if seq.is_empty() {
        return result;
    }

    // 2. Every directly-observed segment is walked.
    for &(seg, _) in &seq {
        result.walked.insert(seg);
    }

    // 3. Bridge consecutive observations, guarding against phantom detours.
    for pair in seq.windows(2) {
        let (a, pa) = pair[0];
        let (b, pb) = pair[1];
        if a == b || graph.adjacent(a, b) {
            continue; // already connected; nothing to fill.
        }
        let gap_m = haversine_m(pa, pb).max(1.0);
        match graph.shortest_path(a, b) {
            Some((intermediate, len))
                if len <= cfg.max_fill_len_m && len <= cfg.max_fill_detour_ratio * gap_m =>
            {
                for seg in intermediate {
                    result.walked.insert(seg);
                }
                result.gaps_filled += 1;
            }
            _ => {
                // Implausible or impossible: leave the gap dark rather than
                // paint streets the walker may never have set foot on.
                result.gaps_rejected += 1;
            }
        }
    }

    result
}

/// Convenience: return traversed segment *ids* (not indices).
pub fn walked_ids(graph: &Graph, result: &MatchResult) -> Vec<u64> {
    let mut ids: Vec<u64> = result
        .walked
        .iter()
        .map(|&idx| graph.segment(idx).id)
        .collect();
    ids.sort_unstable();
    ids
}
