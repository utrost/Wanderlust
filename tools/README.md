# tools — offline map & data pipeline

Turns an OpenStreetMap extract for one area into the two things Wanderlust needs
on-device:

1. **`<area>.pmtiles`** — a compact offline vector basemap the app renders with
   MapLibre Native (ADR-0005). No planet download; one file per area.
2. **`<area>.streets.geojson`** — the walkable street network, fed into the Rust
   geo-core (`geo-ffi`'s GeoJSON loader) for map-matching.

Both are build artifacts — **not committed**. A small hand-sketched sample lives
at `geo-ffi/fixtures/kreuzberg-sample.geojson` for tests; this pipeline produces
the real thing.

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

> Status: pipeline scaffolded. The exact Planetiler profile (which layers,
> zooms, and simplification) is a Phase 0 task to tune against real render tests
> on-device.
