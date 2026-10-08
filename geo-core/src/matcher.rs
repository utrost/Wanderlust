//! Pragmatic map-matching: snap GPS points to the nearest street edge, then
//! fill the gaps between consecutive matches with the shortest path — *but only
//! when that path is plausible*. Per ADR-0001, a street lit that you never
//! walked is worse than a street left dark, so the guardrail refuses to fill a
//! gap when the connecting route is an implausible detour relative to how far
//! the GPS actually moved. See ADR-0001 for the rationale.

use std::collections::HashSet;

use crate::geometry::{haversine_m, point_to_segment_m, LngLat};
use crate::graph::Graph;
use crate::sequence::continuous;

/// Tunables for a matching run.
#[derive(Debug, Clone, Copy)]
pub struct MatchConfig {
    /// A GPS point further than this from any street is treated as unmatched
    /// (noise / off-network), not snapped.
    pub snap_radius_m: f64,
    /// Activity-specific plausibility ceiling (m/s), never a target speed.
    pub max_speed_mps: f64,
    /// Activity affects candidate evidence independently of the speed ceiling.
    pub cycling: bool,
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
            max_speed_mps: 3.0,
            cycling: false,
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
    /// Walked edges supported only by route inference, not direct observations.
    pub inferred: HashSet<usize>,
    /// End indices of reliable GPS pairs not covered by matched geometry.
    /// Indices refer to the flattened GPX points; segment boundaries never join.
    pub unmatched: Vec<usize>,
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
    let mut direct = HashSet::new();
    let mut supported_pairs = HashSet::new();
    let mut track_offset = 0;
    for track in tracks {
        let snapped = crate::sequence::match_sequence(
            graph,
            track,
            cfg.snap_radius_m,
            cfg.max_speed_mps,
            cfg.cycling,
        );
        let mut confirmed = vec![false; track.len()];
        let mut start = 0;
        while start < track.len() {
            let Some((edge, _)) = snapped[start] else {
                start += 1;
                continue;
            };
            let mut end = start + 1;
            while end < track.len()
                && snapped[end].is_some_and(|(e, _)| {
                    graph.same_street_run(snapped[end - 1].unwrap().0, e, track[end].pos)
                })
                && continuous(&track[end - 1], &track[end], cfg.max_speed_mps)
            {
                end += 1;
            }
            let segment = graph.segment(edge);
            let uncertainty = track[start..end]
                .iter()
                .filter_map(|p| p.accuracy_m)
                .fold(0.0_f64, f64::max);
            let required_progress =
                (segment.length_m() * 0.2)
                    .clamp(2.0, 4.0)
                    .max(if uncertainty > 25.0 {
                        uncertainty * 0.5
                    } else {
                        0.0
                    });
            let mut low = f64::INFINITY;
            let mut high = f64::NEG_INFINITY;
            let mut supported = false;
            for i in start..end {
                let current = graph.segment(snapped[i].unwrap().0);
                if let Some((along, tangent)) = segment.project(track[i].pos) {
                    low = low.min(along);
                    high = high.max(along);
                    if i > start
                        && (high - low >= required_progress
                            || (edge != snapped[i].unwrap().0
                                && graph.same_street_run(
                                    snapped[i - 1].unwrap().0,
                                    snapped[i].unwrap().0,
                                    track[i].pos,
                                )
                                && haversine_m(track[start].pos, track[i].pos) >= 4.0))
                        && direction_supports(
                            track,
                            cfg.max_speed_mps,
                            i,
                            current,
                            current
                                .project(track[i].pos)
                                .map(|(_, t)| t)
                                .unwrap_or(tangent),
                        )
                    {
                        supported = true;
                    }
                }
            }
            // A turn into another street needs movement away from the previous
            // street beyond ordinary GPS wobble. In particular, a short refined
            // branch must not be confirmed just because a few fixes drift up it.
            if supported
                && start > 0
                && continuous(&track[start - 1], &track[start], cfg.max_speed_mps)
            {
                if let Some((previous, _)) = snapped[start - 1] {
                    let prior = graph.segment(previous);
                    let turning = prior
                        .project(track[start].pos)
                        .zip(segment.project(track[start].pos))
                        .is_some_and(|((_, a), (_, b))| (a.0 * b.0 + a.1 * b.1).abs() < 0.94);
                    if turning {
                        let reference = track[start].pos.lat.to_radians();
                        let distance = |p| {
                            prior
                                .polyline
                                .windows(2)
                                .map(|pair| point_to_segment_m(p, pair[0], pair[1], reference))
                                .fold(f64::INFINITY, f64::min)
                        };
                        let required = (uncertainty * 0.75).clamp(6.0, 15.0);
                        let initial = distance(track[start].pos);
                        supported = track[start..end]
                            .iter()
                            .any(|p| distance(p.pos) >= required.max(initial + 4.0));
                    }
                }
            }
            if supported {
                // Street-level continuity supports short pieces, but must not
                // credit a continuation touched only by endpoint jitter. Each
                // credited piece still needs projected progress in its own
                // geometry; neighbouring fixes can bracket a single sample.
                for i in start..end {
                    let current = graph.segment(snapped[i].unwrap().0);
                    let local_start = i.saturating_sub(2).max(start);
                    let local_end = (i + 3).min(end);
                    let local_uncertainty = track[local_start..local_end]
                        .iter()
                        .filter_map(|p| p.accuracy_m)
                        .fold(0.0_f64, f64::max);
                    let along: Vec<_> = track[local_start..local_end]
                        .iter()
                        .filter_map(|p| current.project(p.pos).map(|v| v.0))
                        .collect();
                    let progress = along.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                        - along.iter().copied().fold(f64::INFINITY, f64::min);
                    let required = (current.length_m() * 0.2).clamp(2.0, 4.0).max(
                        if local_uncertainty > 25.0 {
                            local_uncertainty * 0.5
                        } else {
                            0.0
                        },
                    );
                    confirmed[i] = progress >= required
                        && current.project(track[i].pos).is_some_and(|(_, t)| {
                            direction_supports(
                                track,
                                cfg.max_speed_mps,
                                (i + 1).min(end - 1),
                                current,
                                t,
                            )
                        });
                }
            }
            start = end;
        }
        for (i, observation) in snapped.iter().enumerate() {
            if confirmed[i] {
                if let Some((edge, _)) = observation {
                    total.walked.insert(*edge);
                    direct.insert(*edge);
                }
            }
        }
        interpolate_gaps(graph, track, &snapped, &confirmed, cfg, &mut total);
        for i in 1..track.len() {
            if !confirmed[i - 1]
                || !confirmed[i]
                || !continuous(&track[i - 1], &track[i], cfg.max_speed_mps)
            {
                continue;
            }
            let (a, b) = (snapped[i - 1].unwrap().0, snapped[i].unwrap().0);
            let budget = (haversine_m(track[i - 1].pos, track[i].pos) * 1.8 + 10.0).min(150.0);
            if a == b
                || graph
                    .unique_connection(a, b, track[i - 1].pos, track[i].pos, budget)
                    .is_some_and(|path| path.iter().all(|edge| total.walked.contains(edge)))
            {
                supported_pairs.insert(track_offset + i);
            }
        }
        track_offset += track.len();
    }
    let mut offset = 0;
    for track in tracks {
        for i in 1..track.len() {
            let a = &track[i - 1];
            let b = &track[i];
            if !reliable(a)
                || !reliable(b)
                || continuous_seconds(a, b, cfg.max_speed_mps).is_none()
                || haversine_m(a.pos, b.pos) < 2.0
            {
                continue;
            }
            // Require geometry near the entire pair, not just its endpoints.
            let middle = LngLat::new((a.pos.lng + b.pos.lng) / 2.0, (a.pos.lat + b.pos.lat) / 2.0);
            let covered = [a.pos, middle, b.pos].iter().all(|&point| {
                // Proximity to the end of a painted section must not hide a
                // neighbouring, unconfirmed short section's GPS evidence.
                graph
                    .nearest_segment(point, 12.0)
                    .is_some_and(|(edge, _)| total.walked.contains(&edge))
            });
            if !covered && !supported_pairs.contains(&(offset + i)) {
                total.unmatched.push(offset + i);
            }
        }
        offset += track.len();
    }
    total.inferred = total.walked.difference(&direct).copied().collect();
    total
}

/// Only infer between consecutive confirmed anchors within this GPX segment.
/// Never join unrelated walks or bridge bad accuracy, outages or speed jumps.
fn interpolate_gaps(
    graph: &Graph,
    track: &[crate::gpx::TrackPoint],
    snapped: &[Option<(usize, f64)>],
    confirmed: &[bool],
    cfg: MatchConfig,
    result: &mut MatchResult,
) {
    let mut anchor: Option<usize> = None;
    for i in 0..track.len() {
        if i > 0
            && (!reliable(&track[i - 1])
                || !reliable(&track[i])
                || continuous_seconds(&track[i - 1], &track[i], cfg.max_speed_mps).is_none())
        {
            anchor = None;
        }
        if !confirmed[i] {
            continue;
        }
        if let Some(j) = anchor {
            let a = snapped[j].unwrap().0;
            let b = snapped[i].unwrap().0;
            // A short crossing may have no fix on its tiny connector. Wait for
            // confirmed evidence on both sides and require a unique route.
            if a != b && !graph.adjacent(a, b) {
                let seconds = track[i]
                    .time
                    .zip(track[j].time)
                    .map(|(end, start)| (end - start).num_milliseconds() as f64 / 1000.0);
                if let Some(seconds) = seconds.filter(|&s| s > 0.0 && s <= 30.0) {
                    let distance = haversine_m(track[j].pos, track[i].pos);
                    let limit = if i == j + 1 {
                        300.0_f64
                    } else if cfg.fill_small_gaps {
                        (25.0 * cfg.max_speed_mps).min(150.0)
                    } else {
                        20.0_f64
                    };
                    let budget = limit
                        .min(cfg.max_fill_len_m)
                        .min(seconds * cfg.max_speed_mps)
                        .min(distance * cfg.max_fill_detour_ratio.min(1.8));
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

/// Estimate direction from spatial separation, not consecutive sample count.
/// This remains conservative when Detailed GPS produces many nearby readings.
/// Backward-only context gives the same decision during live and saved matching.
fn direction_supports(
    track: &[crate::gpx::TrackPoint],
    max_speed: f64,
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
        if !crate::sequence::usable(&track[j]) || !crate::sequence::usable(&track[j + 1]) {
            break;
        }
        if track[j].time.is_some()
            && track[j + 1].time.is_some()
            && haversine_m(track[j].pos, track[j + 1].pos)
                > if max_speed > 3.0 { 450.0 } else { 50.0 }
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

fn continuous_seconds(
    a: &crate::gpx::TrackPoint,
    b: &crate::gpx::TrackPoint,
    max_speed: f64,
) -> Option<f64> {
    let seconds = (b.time? - a.time?).num_milliseconds() as f64 / 1000.0;
    (seconds > 0.0 && seconds <= 30.0 && haversine_m(a.pos, b.pos) <= seconds * max_speed)
        .then_some(seconds)
}
