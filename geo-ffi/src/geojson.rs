//! Load a street network from GeoJSON — the interchange format the tile/OSM
//! pipeline (tools/) will emit. Supports `LineString` and `MultiLineString`
//! features; each becomes one or more [`Segment`]s. A feature's integer `id` is
//! used as the segment id when present (so counts tie back to OSM), otherwise
//! ids are assigned from a high auto-range to avoid colliding with real ones.

use geo_core::geometry::LngLat;
use geo_core::graph::Segment;
use serde_json::Value;

const AUTO_ID_BASE: u64 = 1_000_000_000;

pub fn segments_from_geojson(src: &str) -> Result<Vec<Segment>, String> {
    let v: Value = serde_json::from_str(src).map_err(|e| format!("invalid JSON: {e}"))?;
    let features = v
        .get("features")
        .and_then(Value::as_array)
        .ok_or("GeoJSON has no `features` array")?;

    let mut out = Vec::new();
    let mut auto = 0u64;
    let mut next_auto = || {
        auto += 1;
        AUTO_ID_BASE + auto
    };

    for f in features {
        let geom = match f.get("geometry") {
            Some(g) => g,
            None => continue,
        };
        let gtype = geom.get("type").and_then(Value::as_str).unwrap_or("");
        let coords = geom.get("coordinates");
        let fid = f.get("id").and_then(Value::as_u64);

        match gtype {
            "LineString" => {
                if let Some(line) = coords.and_then(parse_line) {
                    if line.len() >= 2 {
                        out.push(Segment::new(fid.unwrap_or_else(&mut next_auto), line));
                    }
                }
            }
            "MultiLineString" => {
                if let Some(parts) = coords.and_then(Value::as_array) {
                    for (k, part) in parts.iter().enumerate() {
                        if let Some(line) = parse_line(part) {
                            if line.len() >= 2 {
                                // Derive distinct ids for parts of one feature.
                                let base = fid.unwrap_or_else(&mut next_auto);
                                let id = base.wrapping_mul(16).wrapping_add(k as u64);
                                out.push(Segment::new(id, line));
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if out.is_empty() {
        return Err("no LineString/MultiLineString features found".into());
    }
    Ok(out)
}

fn parse_line(v: &Value) -> Option<Vec<LngLat>> {
    let arr = v.as_array()?;
    let mut pts = Vec::with_capacity(arr.len());
    for p in arr {
        let pair = p.as_array()?;
        let lng = pair.first()?.as_f64()?;
        let lat = pair.get(1)?.as_f64()?;
        pts.push(LngLat::new(lng, lat));
    }
    Some(pts)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_linestrings_with_ids() {
        let gj = r#"{"type":"FeatureCollection","features":[
            {"type":"Feature","id":7,"geometry":{"type":"LineString",
              "coordinates":[[13.43,52.495],[13.4315,52.495]]}}
        ]}"#;
        let segs = segments_from_geojson(gj).unwrap();
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].id, 7);
        assert_eq!(segs[0].polyline.len(), 2);
    }

    #[test]
    fn rejects_featureless_input() {
        assert!(segments_from_geojson("{}").is_err());
    }
}
