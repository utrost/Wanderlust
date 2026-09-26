//! GPX reader preserving segment boundaries and validated timestamps.
use crate::geometry::LngLat;

#[derive(Debug, Clone)]
pub struct TrackPoint {
    pub pos: LngLat,
    pub time: Option<chrono::DateTime<chrono::FixedOffset>>,
}

/// Reject malformed documents and invalid fixes instead of silently joining
/// the surrounding points. Namespaced GPX and self-closing points are supported.
pub fn parse_tracks(xml: &str) -> Result<Vec<Vec<TrackPoint>>, String> {
    let doc = roxmltree::Document::parse(xml).map_err(|e| format!("invalid GPX: {e}"))?;
    if doc.root_element().tag_name().name() != "gpx" {
        return Err("expected a GPX document".into());
    }
    let mut tracks = Vec::new();
    for segment in doc
        .descendants()
        .filter(|n| n.is_element() && n.tag_name().name() == "trkseg")
    {
        let mut points = Vec::new();
        for node in segment
            .children()
            .filter(|n| n.is_element() && n.tag_name().name() == "trkpt")
        {
            let coord = |key: &str, limit: f64| -> Result<f64, String> {
                let value: f64 = node
                    .attribute(key)
                    .ok_or_else(|| format!("missing {key}"))?
                    .parse()
                    .map_err(|_| format!("invalid {key}"))?;
                if !value.is_finite() || value.abs() > limit {
                    return Err(format!("invalid {key}"));
                }
                Ok(value)
            };
            let time = node
                .children()
                .find(|n| n.is_element() && n.tag_name().name() == "time")
                .map(|n| {
                    chrono::DateTime::parse_from_rfc3339(n.text().unwrap_or("").trim())
                        .map_err(|_| "invalid GPX timestamp".to_string())
                })
                .transpose()?;
            points.push(TrackPoint {
                pos: LngLat::new(coord("lon", 180.0)?, coord("lat", 90.0)?),
                time,
            });
        }
        if !points.is_empty() {
            tracks.push(points);
        }
    }
    if tracks.is_empty() {
        return Err("GPX contains no track points".into());
    }
    Ok(tracks)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_segments_namespaces_and_optional_time() {
        let tracks = parse_tracks(r#"<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk>
          <trkseg><trkpt lat="52" lon="13"/><trkpt lat="52" lon="13.1"><time>2026-07-11T09:00:00Z</time></trkpt></trkseg>
          <trkseg><trkpt lat="52" lon="13.2"/></trkseg></trk></gpx>"#).unwrap();
        assert_eq!(tracks.len(), 2);
        assert!(tracks[0][0].time.is_none());
        assert!(tracks[0][1].time.is_some());
    }
    #[test]
    fn rejects_bad_documents_and_fixes() {
        for xml in ["<gpx>", "<other/>", "<gpx/>",
            "<gpx><trk><trkseg><trkpt lat='NaN' lon='13'/></trkseg></trk></gpx>",
            "<gpx><trk><trkseg><trkpt lat='91' lon='13'/></trkseg></trk></gpx>",
            "<gpx><trk><trkseg><trkpt lat='52' lon='13'><time>bad</time></trkpt></trkseg></trk></gpx>"] {
            assert!(parse_tracks(xml).is_err(), "{xml}");
        }
    }
}
