//! Sequence inference over bounded street candidates, with an unresolved state.
//! Forward/backward costs use proximity, travel direction and network distance.
//! Similar-cost distinct streets stay unresolved instead of choosing by ID.
use crate::{geometry::haversine_m, gpx::TrackPoint, Graph};

type Candidate = Option<(usize, f64)>;

pub(crate) fn usable(p: &TrackPoint) -> bool {
    p.accuracy_m.is_none_or(|a| a <= 50.0)
}

pub(crate) fn match_sequence(graph: &Graph, track: &[TrackPoint], radius: f64) -> Vec<Candidate> {
    let mut result = vec![None; track.len()];
    let mut start = 0;
    for end in 0..=track.len() {
        let boundary = end == track.len()
            || !usable(&track[end])
            || (end > start && !continuous(&track[end - 1], &track[end]));
        if boundary {
            if end > start {
                solve(graph, &track[start..end], radius, &mut result[start..end]);
            }
            start = if end < track.len() && usable(&track[end]) {
                end
            } else {
                end + 1
            };
        }
    }
    result
}

pub(crate) fn continuous(a: &TrackPoint, b: &TrackPoint) -> bool {
    if !usable(a) || !usable(b) {
        return false;
    }
    match (a.time, b.time) {
        (Some(a_time), Some(b_time)) => {
            let seconds = (b_time - a_time).num_milliseconds() as f64 / 1000.0;
            seconds > 0.0 && seconds <= 30.0 && haversine_m(a.pos, b.pos) <= seconds * 3.0
        }
        (None, None) => true,
        _ => false,
    }
}

fn solve(graph: &Graph, points: &[TrackPoint], radius: f64, output: &mut [Candidate]) {
    let candidates: Vec<Vec<Candidate>> = points
        .iter()
        .map(|p| {
            let mut c: Vec<_> = graph
                .nearby_segments(p.pos, radius.max(p.accuracy_m.unwrap_or(0.0)).min(50.0))
                .into_iter()
                .map(Some)
                .collect();
            c.push(None);
            c
        })
        .collect();
    let emission: Vec<Vec<f64>> = points
        .iter()
        .enumerate()
        .map(|(i, p)| {
            candidates[i]
                .iter()
                .map(|c| {
                    let Some((edge, distance)) = c else {
                        return 3.0;
                    };
                    let sigma = p.accuracy_m.unwrap_or(8.0).clamp(4.0, 50.0);
                    let mut cost = 0.5 * (distance / sigma).powi(2);
                    // A spatial baseline avoids overweighting dense samples and tiny jitter.
                    if let Some((_, tangent)) = graph.segment(*edge).project(p.pos) {
                        for previous in points[..i].iter().rev().take(60) {
                            let separation = haversine_m(previous.pos, p.pos);
                            if separation >= 8.0 {
                                let reference = p.pos.lat.to_radians();
                                let (ax, ay) = previous.pos.to_xy(reference);
                                let (bx, by) = p.pos.to_xy(reference);
                                let length = (bx - ax).hypot(by - ay);
                                let agreement = (((bx - ax) * tangent.0 + (by - ay) * tangent.1)
                                    / length)
                                    .abs();
                                cost += 2.0 * (1.0 - agreement);
                                break;
                            }
                        }
                    }
                    cost
                })
                .collect()
        })
        .collect();
    let transitions: Vec<Vec<Vec<f64>>> = (1..points.len())
        .map(|i| {
            let observed = haversine_m(points[i - 1].pos, points[i].pos);
            let seconds = points[i]
                .time
                .zip(points[i - 1].time)
                .map(|(b, a)| (b - a).num_milliseconds() as f64 / 1000.0);
            let budget = (observed * 2.5 + 20.0)
                .min(seconds.map_or(150.0, |s| s * 3.0 + 10.0))
                .min(150.0);
            candidates[i - 1]
                .iter()
                .map(|a| {
                    candidates[i]
                        .iter()
                        .map(|b| match (a, b) {
                            (Some((from, _)), Some((to, _))) => graph
                                .projected_distance(
                                    *from,
                                    *to,
                                    points[i - 1].pos,
                                    points[i].pos,
                                    budget,
                                )
                                .map(|distance| (distance - observed).abs() / 10.0)
                                .unwrap_or(f64::INFINITY),
                            (None, None) => 0.0,
                            _ => 1.0,
                        })
                        .collect()
                })
                .collect()
        })
        .collect();
    let mut forward = emission.clone();
    for i in 1..points.len() {
        for b in 0..candidates[i].len() {
            forward[i][b] += (0..candidates[i - 1].len())
                .map(|a| forward[i - 1][a] + transitions[i - 1][a][b])
                .fold(f64::INFINITY, f64::min);
        }
    }
    let mut backward: Vec<Vec<f64>> = candidates.iter().map(|c| vec![0.0; c.len()]).collect();
    for i in (0..points.len().saturating_sub(1)).rev() {
        for a in 0..candidates[i].len() {
            backward[i][a] = (0..candidates[i + 1].len())
                .map(|b| transitions[i][a][b] + emission[i + 1][b] + backward[i + 1][b])
                .fold(f64::INFINITY, f64::min);
        }
    }
    for i in 0..points.len() {
        let costs: Vec<_> = (0..candidates[i].len())
            .map(|c| forward[i][c] + backward[i][c])
            .collect();
        let best = (0..costs.len())
            .min_by(|&a, &b| costs[a].total_cmp(&costs[b]))
            .unwrap();
        let Some((edge, _)) = candidates[i][best] else {
            continue;
        };
        let ambiguous = (0..costs.len()).any(|c| {
            c != best
                && costs[c] - costs[best] < std::f64::consts::LN_2
                && match candidates[i][c] {
                    Some((other, _)) => !graph.same_coverage_parent(edge, other),
                    None => true,
                }
        });
        // Clear local evidence can anchor a short sequence. Otherwise require
        // the sequence to prefer this street by at least a factor of two.
        let local_anchor = graph
            .nearest_unambiguous_segment(points[i].pos, radius)
            .is_some_and(|(local, _)| local == edge || graph.same_coverage_parent(local, edge));
        if !ambiguous || local_anchor {
            output[i] = candidates[i][best];
        }
    }
}
