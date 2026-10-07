# Offline street network contract (version 1)

`tools/build_network.py` converts OSM XML into one GeoJSON FeatureCollection. The
same artifact feeds Rust matching and Flutter rendering. There is no runtime
server or map download in this slice.

Each Feature has a positive, unique integer `id`, a LineString `geometry`, and
properties `osm_way_id`, `from_node`, `to_node`, `highway`, and `length_m`.
Optional `name`, `foot`, `bicycle`, `footway`, `access`, `bridge`, `tunnel` and
`layer` tags provide matching context. Missing tags remain unknown. Coordinates are
WGS84 longitude/latitude pairs. Invalid coordinates, duplicate ids, inconsistent
node positions, missing endpoint ids, and unsupported contract versions are
rejected by the Rust loader. MultiLineStrings must be normalized into individually
identified edges first. Legacy unversioned test fixtures may use coordinate-only
topology, but may not mix it with explicit OSM topology.

The root `wanderlust_network` object includes `version: 1`, `area_id`, display
`name`, `network_version`, filtering `policy`, `edge_id_scheme`, `source_sha256`,
OSM base time when available, and attribution/license metadata. Root `bbox` uses
west/south/east/north order.

## Topology and identity

- Split at shared OSM nodes, way endpoints, barriers, and boundary transitions.
  Keep intermediate shape nodes in the LineString; do not turn each into a tiny
  street. Split long chains at existing nodes after approximately 60 m.
- Use explicit OSM node ids for graph connectivity. Geometric crossings and nearby
  endpoints with different node ids never become inferred junctions. This
  preserves bridge/tunnel separation as represented in OSM.
- Orient a way's node chain canonically before splitting. Edge ids are the first
  52 bits of SHA-256 over `osm-edge-v2:<way-id>:<canonical-node-chain>`; collisions
  are detected and fail the build. Integers remain exact in JSON/JavaScript/Dart
  and SQLite. Reordering input or reversing way direction does not change ids.
- Coordinate edits preserve an unchanged chain's id, but alter the network
  version. Splits, way-id changes, or node-chain edits can change ids. Cross-version
  rematching uses saved raw traces; no promise of permanent identity across all
  OSM edits is made.
- Network versions hash canonical features, bbox, area id, and filtering policy.
  Coverage is scoped to that version, preventing silent mixing after a refresh.

## Pedestrian filtering

The policy accepts common pedestrian and ordinary street classes, applies
`foot` before general `access`, and requires explicit pedestrian permission for
cycleways/bridleways. It excludes motorways/trunks, construction/proposed ways,
private/restricted access without a pedestrian override, conditional access,
indoor/level-dependent ways, and polygon outlines marked `area=yes`.

Edges incident to blocked nodes are conservatively omitted. Geometry crossing
the selected bbox boundary is omitted rather than clipped into invented nodes.
These are deliberately conservative rules for this Bremen proof, not a complete
country-specific pedestrian routing policy or a completeness denominator.

References: [OSM access tags](https://wiki.openstreetmap.org/wiki/Key:access),
[pyosmium handlers](https://docs.osmcode.org/pyosmium/latest/reference/Handler-Processing/).
