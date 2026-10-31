# ADR-0008: Offline GeoJSON rendering and bounded geographic cells

- **Status:** Accepted (records the existing implementation)
- **Date:** 2026-10-31
- **Supersedes:** [ADR-0005](0005-offline-rendering-maplibre-pmtiles.md)

## Context

The implemented application downloads OSM street/scenery GeoJSON and draws it
with Flutter CustomPainter. It neither loads PMTiles nor depends on MapLibre.
The older ADR and issues #6/#8 described a pipeline that was not shipped.

## Decision

Document the existing GeoJSON renderer as the current architecture. Preserve
original downloaded sources in the offline library and build disposable,
compressed geographic-cell caches for bounded loading. Recording interests take
priority over browsing; switching views does not delete sources or recordings.
Street matching stays in Rust and coverage/block analysis remains independent
of the renderer. The bundled sample network can be reproduced with
`tools/build_network.py`; see `tools/README.md` and the network contract.

## Consequences

No tile server or map account is needed after downloading an area. The app owns
path caching, culling, label layout and large-map performance. PMTiles/MapLibre
remain possible future alternatives, requiring a new decision and measured
benefit; they are not unfinished deliverables of the current beta.
