# tools — offline map & data pipeline

Turns an OpenStreetMap extract for one area into the two things Wanderlust needs
on-device:

1. **`<area>.pmtiles`** — a compact offline vector basemap the app renders with
   MapLibre Native (ADR-0005). No planet download; one file per area.
2. **`<area>.streets.geojson`** — the walkable street network, fed into the Rust
   geo-core (`geo-ffi`'s GeoJSON loader) for map-matching.

The Bremen street snapshot and its reproducible OSM source are committed for
offline tests; see [data/bremen](../data/bremen/README.md). PMTiles and regional
PBF files remain generated artifacts. The [network contract](../docs/NETWORK_CONTRACT.md)
defines segmentation, identity, topology, and pedestrian filtering.

## Prerequisites

- Java 17+ (for [Planetiler](https://github.com/onthegomap/planetiler), which
  builds the PMTiles).
- [`osmium`](https://osmcode.org/osmium-tool/) to extract the street network as
  GeoJSON.
- A regional `.osm.pbf` (e.g. Berlin from
  [Geofabrik](https://download.geofabrik.de/europe/germany/berlin.html)).

## Usage

```bash
# 1. Basemap tiles for a bbox (minLng,minLat,maxLng,maxLat):
./build_tiles.sh berlin-latest.osm.pbf 13.40,52.49,13.45,52.51 kreuzberg

# → out/kreuzberg.pmtiles  and  out/kreuzberg.streets.geojson
```

Drop `kreuzberg.pmtiles` into the app's area storage and load
`kreuzberg.streets.geojson` into the geo-core. See the roadmap (Phase 0:
"PMTiles + MapLibre render", Phase 1: "Area selection") for how these get wired
into onboarding.

> The street-network path is implemented and tested. The Planetiler profile
> and PMTiles/MapLibre basemap remain a separate unfinished integration.

For the bundled Bremen network, use the standard-library-only rebuild in
[data/bremen/README.md](../data/bremen/README.md). `extract_osm.py` needs
`osmium==4.3.1` only when refreshing from a regional PBF. `evaluate_matching.py`
uses the release Rust library through its real C ABI; no Python geo library is
needed to evaluate the committed network.
