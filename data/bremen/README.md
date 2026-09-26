# Bremen center fixture

Real OpenStreetMap street geometry, covering the roadmap's Bremen center bbox:
`8.784897,53.062431,8.829756,53.089380` (west, south, east, north).

**© OpenStreetMap contributors. Data licensed under ODbL 1.0**, separately from
Wanderlust's code license. Attribution and license information:
https://www.openstreetmap.org/copyright

Source: https://download.geofabrik.de/europe/germany/bremen.html
The downloaded `bremen-latest.osm.pbf` snapshot has OSM base timestamp
`2026-09-25T20:24:36Z`. `source.json` records its SHA-256 and the extracted XML hash.
`source.osm.gz` retains the small highway/node extract needed to reproduce the
bundled network without network access or the original regional PBF. Contributor
usernames, changeset metadata, and unrelated features are omitted.

Rebuild the committed asset using Python's standard library:

```sh
python3 tools/build_network.py data/bremen/source.osm.gz \
  app/assets/geo/bremen-center.streets.geojson \
  --report data/bremen/network-report.json
python3 -m unittest discover -s tools/tests -v
```

For an intentional data refresh, install `osmium==4.3.1` in a Python environment
and run `tools/extract_osm.py <regional.pbf> data/bremen/source.osm.gz`, then rebuild.
A changed network gets a new version; existing saved raw walks are rematched rather
than attaching old counts to changed geometry. Keep the source hash and evaluation
reports in sync with the refreshed asset.

## Matching evaluation

`evaluation/` contains **synthetic** traces routed through real OSM topology,
expected edge ids from the independent Python route generator, and a measured
report. These are not walks recorded by a person. Noise is deterministic and
applied independently to both coordinate axes. `evaluation-5m/` repeats the
experiment at sampling closer to the recorder's five-metre distance filter.

```sh
cargo build --release -p geo-ffi
python3 tools/evaluate_matching.py --check
python3 tools/evaluate_matching.py --step-m 5 --check \
  --output tools/out/evaluation-5m
```

The evaluation invokes the actual Rust C ABI. CI requires zero false-positive
edges in these synthetic cases and at least 80% length coverage for clean traces.
Runtime is reported, not asserted against a machine-dependent threshold.

`matching-before.json` documents the every-node segmentation baseline;
`matching-segmentation.json` documents junction segmentation before requiring
consecutive supporting fixes. These historical reports intentionally use earlier
network/matcher versions. They are evidence for the design change, not golden
outputs for the final implementation. Edge-count recall across different
segmentations is not directly comparable.

Final network: 7,930 edges and 247.719 km of accepted street/path geometry. It has
91 connected components; disconnected private approaches, excluded restrictions,
and bbox boundaries are not automatically joined. 1,143 edges remain shorter
than six metres. Long primitive OSM edges can exceed the 60 m splitting target
because the generator never invents midpoint nodes.
