//! Pragmatic map-matching: snap GPS points to the nearest street edge, then
//! fill the gaps between consecutive matches with the shortest path — *but only
//! when that path is plausible*. Per ADR-0001, a street lit that you never
//! walked is worse than a street left dark, so the guardrail refuses to fill a
//! gap when the connecting route is an implausible detour relative to how far
//! the GPS actually moved. See ADR-0001 for the rationale.

use std::collections::HashSet;

use crate::geometry::{haversine_m, point_to_segment_m, LngLat};
use crate::graph::Graph;

/// Tunables for a matching run.
#[derive(Debug, Clone, Copy)]
pub struct MatchConfig {
    /// A GPS point further than this from any street is treated as unmatched
    /// (noise / off-network), not snapped.
    pub snap_radius_m: f64,
    /// Opt-in interpolation across short unconfirmed runs between strong anchors.
    pub fill_small_gaps: bool,
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
            fill_small_gaps: false,
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
/// fixes, along-edge movement and compatible travel direction. Untimed GPX
/// remains usable, but receives no inferred fill.
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
            .map(|p| {
                if reliable(p) {
                    graph.nearest_unambiguous_segment(p.pos, cfg.snap_radius_m)
                } else {
                    None
                }
            })
            .collect();
        let mut confirmed = vec![false; track.len()];
        let mut start = 0;
        while start < track.len() {
            let Some((edge, _)) = snapped[start] else {
                start += 1;
                continue;
            };
            let mut end = start + 1;
            while end < track.len()
                && snapped[end].is_some_and(|(e, _)| e == edge)
                && continuous(&track[end - 1], &track[end])
            {
                end += 1;
            }
            let segment = graph.segment(edge);
            let required_progress = (segment.length_m() * 0.2).clamp(2.0, 4.0);
            let mut low = f64::INFINITY;
            let mut high = f64::NEG_INFINITY;
            let mut supported = false;
            for i in start..end {
                if let Some((along, tangent)) = segment.project(track[i].pos) {
                    low = low.min(along);
                    high = high.max(along);
                    if i > start
                        && high - low >= required_progress
                        && direction_supports(track, i, segment, tangent)
                    {
                        supported = true;
                    }
                }
            }
            if supported {
                confirmed[start..end].fill(true);
            }
            start = end;
        }
        for (i, observation) in snapped.iter().enumerate() {
            if confirmed[i] {
                if let Some((edge, _)) = observation {
                    total.walked.insert(*edge);
                }
            }
        }
        if cfg.fill_small_gaps {
            interpolate_gaps(graph, track, &snapped, &confirmed, &mut total);
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

/// Only infer between consecutive confirmed anchors within this GPX segment.
/// Never join unrelated walks or bridge bad accuracy, outages or speed jumps.
fn interpolate_gaps(
    graph: &Graph,
    track: &[crate::gpx::TrackPoint],
    snapped: &[Option<(usize, f64)>],
    confirmed: &[bool],
    result: &mut MatchResult,
) {
    let mut anchor: Option<usize> = None;
    for i in 0..track.len() {
        if i > 0
            && (!reliable(&track[i - 1])
                || !reliable(&track[i])
                || continuous_seconds(&track[i - 1], &track[i]).is_none())
        {
            anchor = None;
        }
        if !confirmed[i] {
            continue;
        }
        if let Some(j) = anchor {
            let a = snapped[j].unwrap().0;
            let b = snapped[i].unwrap().0;
            // Adjacent fixes already have the default, stricter fill path.
            if i > j + 1 && a != b && !graph.adjacent(a, b) {
                let seconds = track[i]
                    .time
                    .zip(track[j].time)
                    .map(|(end, start)| (end - start).num_milliseconds() as f64 / 1000.0);
                if let Some(seconds) = seconds.filter(|&s| s > 0.0 && s <= 30.0) {
                    let distance = haversine_m(track[j].pos, track[i].pos);
                    let budget = 75.0_f64.min(seconds * 3.0).min(distance * 1.8);
                    if let Some(path) =
                        graph.unique_connection(a, b, track[j].pos, track[i].pos, budget)
                    {
                        let reference = track[j].pos.lat.to_radians();
                        // Geometry must follow the observed trace, not merely
                        // offer a short graph detour through an unwalked street.
                        let follows_trace = path.iter().all(|&edge| {
                            graph.segment(edge).polyline.iter().all(|&point| {
                                track[j..=i].windows(2).any(|pair| {
                                    point_to_segment_m(point, pair[0].pos, pair[1].pos, reference)
                                        <= 20.0
                                })
                            })
                        });
                        let stays_near_route = track[j..=i].iter().all(|fix| {
                            path.iter().copied().chain([a, b]).any(|edge| {
                                graph.segment(edge).polyline.windows(2).any(|pair| {
                                    point_to_segment_m(fix.pos, pair[0], pair[1], reference) <= 20.0
                                })
                            })
                        });
                        if follows_trace && stays_near_route {
                            result.walked.extend(path);
                            result.gaps_filled += 1;
                            anchor = Some(i);
                            continue;
                        }
                    }
                    result.gaps_rejected += 1;
                }
            }
        }
        anchor = Some(i);
    }
}

fn reliable(point: &crate::gpx::TrackPoint) -> bool {
    point.accuracy_m.is_none_or(|metres| metres <= 25.0)
}

fn continuous(a: &crate::gpx::TrackPoint, b: &crate::gpx::TrackPoint) -> bool {
    reliable(a)
        && reliable(b)
        && (continuous_seconds(a, b).is_some() || (a.time.is_none() && b.time.is_none()))
}

/// Estimate direction from spatial separation, not consecutive sample count.
/// This remains conservative when Detailed GPS produces many nearby readings.
/// Backward-only context gives the same decision during live and saved matching.
fn direction_supports(
    track: &[crate::gpx::TrackPoint],
    i: usize,
    segment: &crate::graph::Segment,
    tangent: (f64, f64),
) -> bool {
    let baseline = (segment.length_m() * 0.5).clamp(4.0, 12.0);
    let reference = segment.polyline[0].lat.to_radians();
    let (x, y) = track[i].pos.to_xy(reference);
    for j in (0..i).rev() {
        // Small sample-to-sample jumps can be GPS noise. Direction uses a wider
        // baseline; preserve time breaks and reject gross jumps, while direct
        // confirmation and gap filling retain their stricter speed checks.
        if !reliable(&track[j]) || !reliable(&track[j + 1]) {
            break;
        }
        if track[j].time.is_some()
            && track[j + 1].time.is_some()
            && haversine_m(track[j].pos, track[j + 1].pos) > 50.0
        {
            break;
        }
        match (track[j].time, track[j + 1].time) {
            (Some(a), Some(b)) if b <= a || (b - a).num_milliseconds() > 30_000 => break,
            (None, Some(_)) | (Some(_), None) => break,
            _ => (),
        }
        if let (Some(a), Some(b)) = (track[j].time, track[i].time) {
            if (b - a).num_seconds() > 60 {
                break;
            }
        }
        let (ax, ay) = track[j].pos.to_xy(reference);
        let (dx, dy) = (x - ax, y - ay);
        let length = dx.hypot(dy);
        if length + 1e-6 >= baseline {
            // Undirected streets support walking either way, but not across them.
            return ((dx * tangent.0 + dy * tangent.1) / length).abs() >= 0.707;
        }
        // Bound untimed imports too; dense recorded traces normally use time.
        if i - j >= 60 {
            break;
        }
    }
    false
}

fn continuous_seconds(a: &crate::gpx::TrackPoint, b: &crate::gpx::TrackPoint) -> Option<f64> {
    let seconds = (b.time? - a.time?).num_milliseconds() as f64 / 1000.0;
    (seconds > 0.0 && seconds <= 30.0 && haversine_m(a.pos, b.pos) <= seconds * 3.0)
        .then_some(seconds)
}
