//! Local movement envelopes for mixed journeys. Labels never gate reliable GPS.
use crate::{
    geometry::haversine_m,
    gpx::TrackPoint,
    matcher::{match_gpx_tracks, match_gpx_tracks_supported},
    Graph, MatchConfig, MatchResult,
};

fn speed(a: &TrackPoint, b: &TrackPoint) -> Option<f64> {
    if !crate::sequence::usable(a) || !crate::sequence::usable(b) {
        return None;
    }
    let seconds = (b.time? - a.time?).num_milliseconds() as f64 / 1000.;
    (seconds > 0. && seconds <= 30.).then(|| haversine_m(a.pos, b.pos) / seconds)
}

/// Each pair gets a locally supported ceiling. A mode change shares its boundary
/// fix between runs, so neither movement nor unmatched-pair indices disappear.
pub fn match_automatic_tracks(
    graph: &Graph,
    tracks: &[Vec<TrackPoint>],
    cfg: MatchConfig,
) -> MatchResult {
    let mut result = MatchResult::default();
    let mut offset = 0;
    let mut reliable_pairs = Vec::new();
    let mut supported_pairs = std::collections::HashSet::new();
    let mut direct = std::collections::HashSet::new();
    for track in tracks {
        let mut spike = vec![false; track.len()];
        for i in 1..track.len().saturating_sub(1) {
            if speed(&track[i - 1], &track[i]).is_none()
                || speed(&track[i], &track[i + 1]).is_none()
            {
                continue;
            }
            let a = haversine_m(track[i - 1].pos, track[i].pos);
            let b = haversine_m(track[i].pos, track[i + 1].pos);
            let across = haversine_m(track[i - 1].pos, track[i + 1].pos);
            let uncertainty = track[i].accuracy_m.unwrap_or(8.).max(8.);
            // Ordinary turns and short out-and-back walks remain valid. Reject
            // an isolated large excursion with an immediate return instead.
            let duration = track[i + 1]
                .time
                .zip(track[i - 1].time)
                .map_or(0, |(b, a)| (b - a).num_milliseconds());
            spike[i] = duration <= 10000
                && a.min(b) > (uncertainty * 3.).max(40.)
                && a + b > across * 3. + 60.;
        }
        let speeds: Vec<_> = (1..track.len())
            .map(|i| {
                if spike[i - 1] || spike[i] {
                    None
                } else {
                    speed(&track[i - 1], &track[i])
                }
            })
            .collect();
        let mut profiles = Vec::new();
        for (i, v) in speeds.iter().enumerate() {
            // Do not borrow evidence across an outage or rejected fix.
            let mut nearby = Vec::new();
            if let Some(v) = v {
                nearby.push(*v);
            }
            for j in (i.saturating_sub(2)..i).rev() {
                match speeds[j] {
                    Some(v) => nearby.push(v),
                    None => break,
                }
            }
            for v in speeds.iter().take((i + 3).min(speeds.len())).skip(i + 1) {
                match v {
                    Some(v) => nearby.push(*v),
                    None => break,
                }
            }
            nearby.sort_by(f64::total_cmp);
            let median = nearby.get(nearby.len() / 2).copied().unwrap_or(0.);
            let accepted = v.is_some_and(|v| v <= (median * 2. + 2.).clamp(3., 70.));
            // Mode comes from net progress over a wider baseline, not the
            // distance added by zigzagging GPS noise between individual fixes.
            let mut left = i;
            let mut right = i + 1;
            while left > i.saturating_sub(4) && speeds[left - 1].is_some() {
                left -= 1;
            }
            while right < (i + 6).min(track.len()) && speeds[right - 1].is_some() {
                if right == track.len() - 1 {
                    break;
                }
                if speeds[right].is_none() {
                    break;
                }
                right += 1;
            }
            let elapsed = track[right]
                .time
                .zip(track[left].time)
                .map_or(0., |(b, a)| (b - a).num_milliseconds() as f64 / 1000.);
            let sustained = if elapsed > 0. {
                haversine_m(track[left].pos, track[right].pos) / elapsed
            } else {
                0.
            };
            profiles.push(if !accepted {
                None
            } else if sustained > 12. {
                Some(70)
            } else if sustained > 3. {
                Some(15)
            } else {
                Some(3)
            });
        }
        for (i, profile) in profiles.iter().enumerate() {
            if profile.is_some()
                && track[i].accuracy_m.is_none_or(|a| a <= 25.)
                && track[i + 1].accuracy_m.is_none_or(|a| a <= 25.)
                && haversine_m(track[i].pos, track[i + 1].pos) >= 2.
            {
                reliable_pairs.push((
                    offset + i + 1,
                    track[i].pos,
                    track[i + 1].pos,
                    profile.unwrap(),
                ));
            }
        }
        let mut start = 0;
        while start < profiles.len() {
            let Some(limit) = profiles[start] else {
                start += 1;
                continue;
            };
            let mut end = start + 1;
            while end < profiles.len() && profiles[end] == Some(limit) {
                end += 1;
            }
            let local = MatchConfig {
                max_speed_mps: limit as f64,
                cycling: limit == 15,
                ..cfg
            };
            let (matched, supported) =
                match_gpx_tracks_supported(graph, &[track[start..=end].to_vec()], local);
            supported_pairs.extend(supported.into_iter().map(|i| offset + start + i));
            direct.extend(matched.walked.difference(&matched.inferred).copied());
            result.walked.extend(matched.walked);
            result.inferred.extend(matched.inferred);
            // Recompute fallback from the accepted pair profiles below. The
            // generic matcher has no movement-aware nearest-edge context.
            result.gaps_filled += matched.gaps_filled;
            result.gaps_rejected += matched.gaps_rejected;
            start = end;
        }
        // Untimed imports retain the existing conservative walking matcher.
        if track.iter().all(|p| p.time.is_none()) {
            let matched = match_gpx_tracks(graph, std::slice::from_ref(track), cfg);
            direct.extend(matched.walked.difference(&matched.inferred).copied());
            result.walked.extend(matched.walked);
            result.inferred.extend(matched.inferred);
        }
        offset += track.len();
    }
    // Sparse fast fixes can skip several short coverage sections. Check the
    // entire interval, not only endpoints/midpoint, before hiding recorded GPS.
    for (index, a, b, profile) in reliable_pairs {
        // A coherent, confirmed street sequence is stronger evidence than the
        // nearest edge to an individual noisy fix. Do not redraw its raw GPS.
        if supported_pairs.contains(&index) {
            continue;
        }
        let steps = (haversine_m(a, b) / 5.).ceil().max(1.) as usize;
        let covered = (0..=steps).all(|i| {
            let t = i as f64 / steps as f64;
            let p = crate::LngLat::new(a.lng + (b.lng - a.lng) * t, a.lat + (b.lat - a.lat) * t);
            graph
                .nearest_movement_segment(p, 12., profile == 15, profile == 70)
                .is_some_and(|(edge, _)| result.walked.contains(&edge))
        });
        if !covered {
            result.unmatched.push(index);
        }
    }
    result.inferred.retain(|edge| !direct.contains(edge));
    result.unmatched.sort_unstable();
    result.unmatched.dedup();
    result
}
