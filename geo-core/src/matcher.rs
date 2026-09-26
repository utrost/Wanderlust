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
    let mut seq: Vec<Option<(usize, LngLat)>> = Vec::new();
    for &p in points {
        if let Some((seg, _dist)) = graph.nearest_unambiguous_segment(p, cfg.snap_radius_m) {
            if let Some(Some((last, position))) = seq.last_mut() {
                if *last == seg {
                    *position = p;
                    continue;
                }
            }
            seq.push(Some((seg, p)));
        } else {
            // An off-network or ambiguous fix is a real break, never erase it.
            seq.push(None);
        }
    }

    let mut result = MatchResult::default();
    if seq.is_empty() {
        return result;
    }

    // 2. Every directly-observed segment is walked.
    for &(seg, _) in seq.iter().flatten() {
        result.walked.insert(seg);
    }

    // 3. Bridge consecutive observations, guarding against phantom detours.
    for pair in seq.windows(2) {
        let (Some((a, pa)), Some((b, pb))) = (pair[0], pair[1]) else {
            continue;
        };
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

/// Match separate GPX segments without bridging outages, backwards clocks, or
/// implausible speed. Each directly painted edge needs consecutive supporting
/// fixes. Untimed GPX remains usable, but receives no inferred fill.
pub fn match_gpx_tracks(
    graph: &Graph,
    tracks: &[Vec<crate::gpx::TrackPoint>],
    cfg: MatchConfig,
) -> MatchResult {
    let mut total = MatchResult::default();
    for track in tracks {
        // Snap once per fix. Single-fix excursions onto another street are
        // common with walking GPS and must not become permanent coverage.
        let snapped: Vec<_> = track
            .iter()
            .map(|p| graph.nearest_unambiguous_segment(p.pos, cfg.snap_radius_m))
            .collect();
        let mut confirmed = vec![false; track.len()];
        for i in 1..track.len() {
            if let (Some((a, _)), Some((b, _))) = (snapped[i - 1], snapped[i]) {
                let consecutive = continuous_seconds(&track[i - 1], &track[i]).is_some()
                    || (track[i - 1].time.is_none() && track[i].time.is_none());
                if a == b && consecutive {
                    confirmed[i - 1] = true;
                    confirmed[i] = true;
                }
            }
        }
        for (i, observation) in snapped.iter().enumerate() {
            if confirmed[i] {
                if let Some((edge, _)) = observation {
                    total.walked.insert(*edge);
                }
            }
        }
        for i in 1..track.len() {
            if !confirmed[i - 1] || !confirmed[i] {
                continue;
            }
            let (Some((a, _)), Some((b, _))) = (snapped[i - 1], snapped[i]) else {
                continue;
            };
            if a == b || graph.adjacent(a, b) {
                continue;
            }
            let Some(seconds) = continuous_seconds(&track[i - 1], &track[i]) else {
                continue;
            };
            let gap = haversine_m(track[i - 1].pos, track[i].pos).max(1.0);
            match graph.shortest_path(a, b) {
                Some((intermediate, len))
                    if len <= cfg.max_fill_len_m.min(seconds * 3.0)
                        && len <= cfg.max_fill_detour_ratio * gap =>
                {
                    total.walked.extend(intermediate);
                    total.gaps_filled += 1;
                }
                _ => total.gaps_rejected += 1,
            }
        }
    }
    total
}

fn continuous_seconds(a: &crate::gpx::TrackPoint, b: &crate::gpx::TrackPoint) -> Option<f64> {
    let seconds = (b.time? - a.time?).num_milliseconds() as f64 / 1000.0;
    (seconds > 0.0 && seconds <= 30.0 && haversine_m(a.pos, b.pos) <= seconds * 3.0)
        .then_some(seconds)
}
