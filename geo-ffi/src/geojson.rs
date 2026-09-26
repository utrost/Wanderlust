//! Strict street-network loader. Counts require explicit, unique, JSON-safe
//! edge ids; OSM networks also carry endpoint node ids to preserve topology.
use geo_core::geometry::LngLat;
use geo_core::graph::Segment;
use serde_json::Value;
use std::collections::{HashMap, HashSet};

const MAX_SAFE_INTEGER: u64 = (1_u64 << 53) - 1;

fn integer(v: Option<&Value>, label: &str) -> Result<u64, String> {
    v.and_then(Value::as_u64)
        .filter(|&id| id > 0 && id <= MAX_SAFE_INTEGER)
        .ok_or_else(|| format!("{label} must be a positive JSON-safe integer"))
}

pub fn segments_from_geojson(src: &str) -> Result<Vec<Segment>, String> {
    let v: Value = serde_json::from_str(src).map_err(|e| format!("invalid JSON: {e}"))?;
    if v["type"] != "FeatureCollection" {
        return Err("expected FeatureCollection".into());
    }
    let contract = v.get("wanderlust_network");
    if let Some(meta) = contract {
        if meta["version"] != 1 {
            return Err("unsupported network contract version".into());
        }
    }
    let features = v
        .get("features")
        .and_then(Value::as_array)
        .ok_or("missing features")?;
    let mut ids = HashSet::new();
    let mut nodes: HashMap<u64, (f64, f64)> = HashMap::new();
    let mut out = Vec::new();
    let mut explicit_nodes = None;
    for f in features {
        if f["type"] != "Feature" || f["geometry"]["type"] != "LineString" {
            return Err(
                "each edge must be a LineString Feature; normalize multi-part ways first".into(),
            );
        }
        let id = integer(f.get("id"), "edge id")?;
        if !ids.insert(id) {
            return Err(format!("duplicate edge id {id}"));
        }
        let line = f["geometry"]["coordinates"]
            .as_array()
            .ok_or("missing coordinates")?;
        if line.len() < 2 {
            return Err(format!("edge {id} needs two or more coordinates"));
        }
        let mut points = Vec::new();
        for value in line {
            let pair = value.as_array().ok_or("invalid coordinate")?;
            if pair.len() != 2 {
                return Err("coordinates must be longitude/latitude pairs".into());
            }
            let lng = pair[0].as_f64().ok_or("invalid longitude")?;
            let lat = pair[1].as_f64().ok_or("invalid latitude")?;
            if !lng.is_finite() || !lat.is_finite() || lng.abs() > 180.0 || lat.abs() > 90.0 {
                return Err("coordinate out of range".into());
            }
            points.push(LngLat::new(lng, lat));
        }
        let mut segment = Segment::new(id, points);
        if segment.length_m() < 0.01 {
            return Err(format!("degenerate edge {id}"));
        }
        let props = &f["properties"];
        let has_nodes = props.get("from_node").is_some() || props.get("to_node").is_some();
        if contract.is_some() && !has_nodes {
            return Err("OSM contract requires endpoint node ids".into());
        }
        if explicit_nodes.is_some_and(|mode| mode != has_nodes) {
            return Err("cannot mix explicit and coordinate-only topology".into());
        }
        explicit_nodes = Some(has_nodes);
        if has_nodes {
            let a = integer(props.get("from_node"), "from_node")?;
            let b = integer(props.get("to_node"), "to_node")?;
            for (node, pos) in [
                (a, segment.polyline[0]),
                (b, *segment.polyline.last().unwrap()),
            ] {
                if let Some(previous) = nodes.insert(node, (pos.lng, pos.lat)) {
                    if previous != (pos.lng, pos.lat) {
                        return Err(format!("inconsistent coordinates for node {node}"));
                    }
                }
            }
            segment = segment.with_nodes(a, b);
        }
        out.push(segment);
    }
    if out.is_empty() {
        return Err("network contains no edges".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use geo_core::Graph;
    use serde_json::json;
    fn edge(id: u64, nodes: [u64; 2], coordinates: Value) -> Value {
        json!({"type":"Feature","id":id,"properties":{"from_node":nodes[0],"to_node":nodes[1]},"geometry":{"type":"LineString","coordinates":coordinates}})
    }
    fn load(features: Vec<Value>) -> Result<Vec<Segment>, String> {
        segments_from_geojson(&json!({"type":"FeatureCollection","features":features}).to_string())
    }
    #[test]
    fn explicit_nodes_preserve_bridges_and_real_junctions() {
        let graph = Graph::build(
            load(vec![
                edge(1, [1, 2], json!([[8.8, 53.0], [8.81, 53.0]])),
                edge(2, [3, 4], json!([[8.81, 53.0], [8.82, 53.0]])),
                edge(3, [2, 5], json!([[8.81, 53.0], [8.81, 53.01]])),
            ])
            .unwrap(),
        );
        assert!(!graph.adjacent(0, 1));
        assert!(graph.shortest_path(0, 1).is_none());
        assert!(graph.adjacent(0, 2));
    }
    #[test]
    fn rejects_unstable_ids_bad_geometry_and_inconsistent_nodes() {
        let a = edge(1, [1, 2], json!([[8.8, 53.0], [8.81, 53.0]]));
        assert!(load(vec![a.clone(), a.clone()]).is_err());
        let mut missing = a.clone();
        missing.as_object_mut().unwrap().remove("id");
        assert!(load(vec![missing]).is_err());
        assert!(load(vec![edge(
            MAX_SAFE_INTEGER + 1,
            [1, 2],
            json!([[8.8, 53.0], [8.81, 53.0]])
        )])
        .is_err());
        assert!(load(vec![edge(2, [1, 2], json!([[181.0, 53.0], [8.81, 53.0]]))]).is_err());
        assert!(load(vec![edge(2, [1, 2], json!([[8.8, 53.0], [8.8, 53.0]]))]).is_err());
        assert!(load(vec![a, edge(2, [2, 3], json!([[8.9, 53.0], [8.91, 53.0]]))]).is_err());
    }
    #[test]
    fn rejects_missing_topology_in_versioned_networks() {
        let network = json!({"type":"FeatureCollection","wanderlust_network":{"version":1},"features":[
            {"type":"Feature","id":1,"geometry":{"type":"LineString","coordinates":[[8.8,53.0],[8.81,53.0]]}}
        ]});
        assert!(segments_from_geojson(&network.to_string()).is_err());
    }
}
