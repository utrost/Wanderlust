//! Minimal GPX track-point reader for the Phase 0 spike.
//!
//! Deliberately tiny and dependency-free: it scans for `<trkpt>` elements and
//! pulls their `lat`/`lon` attributes (and optional `<time>`). It is enough to
//! feed real Strava/Komoot/Garmin exports into the matcher for validation. It
//! is NOT a general GPX parser — routes, waypoints, extensions and namespaces
//! are ignored — and should be replaced by a proper parser before shipping.

use crate::geometry::LngLat;

/// One parsed track point. `time` is the raw RFC3339 string if present.
#[derive(Debug, Clone)]
pub struct TrackPoint {
    pub pos: LngLat,
    pub time: Option<String>,
}

/// Parse the `<trkpt>` sequence out of a GPX document, in file order.
pub fn parse_trackpoints(xml: &str) -> Vec<TrackPoint> {
    let mut out = Vec::new();
    let bytes = xml.as_bytes();
    let mut i = 0;
    while let Some(rel) = find(&xml[i..], "<trkpt") {
        let start = i + rel;
        // The opening tag runs to the next '>'.
        let tag_end = match find(&xml[start..], ">") {
            Some(r) => start + r,
            None => break,
        };
        let tag = &xml[start..tag_end];
        if let (Some(lat), Some(lon)) = (attr(tag, "lat"), attr(tag, "lon")) {
            let time = extract_time(xml, tag_end, bytes.len());
            out.push(TrackPoint {
                pos: LngLat::new(lon, lat),
                time,
            });
        }
        i = tag_end + 1;
    }
    out
}

/// Convenience: positions only, for straight into the matcher.
pub fn parse_positions(xml: &str) -> Vec<LngLat> {
    parse_trackpoints(xml).into_iter().map(|p| p.pos).collect()
}

fn find(haystack: &str, needle: &str) -> Option<usize> {
    haystack.find(needle)
}

/// Read a numeric XML attribute value (`name="..."`) out of an opening tag.
fn attr(tag: &str, name: &str) -> Option<f64> {
    let key = format!("{name}=");
    let at = tag.find(&key)? + key.len();
    let rest = &tag[at..];
    let quote = rest.chars().next()?;
    if quote != '"' && quote != '\'' {
        return None;
    }
    let rest = &rest[1..];
    let end = rest.find(quote)?;
    rest[..end].trim().parse().ok()
}

/// If a `<time>...</time>` appears before the trackpoint closes, capture it.
fn extract_time(xml: &str, from: usize, _len: usize) -> Option<String> {
    let close = find(&xml[from..], "</trkpt>").map(|r| from + r)?;
    let window = &xml[from..close];
    let t0 = find(window, "<time>")? + "<time>".len();
    let t1 = find(&window[t0..], "</time>")?;
    Some(window[t0..t0 + t1].trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_lat_lon_and_time() {
        let gpx = r#"<gpx><trk><trkseg>
            <trkpt lat="52.4990" lon="13.4200"><time>2026-07-11T09:00:00Z</time></trkpt>
            <trkpt lat="52.5000" lon="13.4210"></trkpt>
        </trkseg></trk></gpx>"#;
        let pts = parse_trackpoints(gpx);
        assert_eq!(pts.len(), 2);
        assert!((pts[0].pos.lat - 52.499).abs() < 1e-9);
        assert!((pts[0].pos.lng - 13.42).abs() < 1e-9);
        assert_eq!(pts[0].time.as_deref(), Some("2026-07-11T09:00:00Z"));
        assert_eq!(pts[1].time, None);
    }
}
