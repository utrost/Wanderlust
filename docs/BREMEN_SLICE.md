# Bremen coverage slice: implementation and evaluation

The app now bundles a real Bremen center street network. Saving a foreground walk
runs its GPX through Rust on a worker isolate, stores the matched edge membership,
and redraws the street map from SQLite counts. The previous mock fill-stage picker
is removed. Pinch/pan works offline; the attribution control explains the source.

This is a **street coverage view**, not the planned PMTiles/MapLibre basemap. It
has no water/park layers, address labels, live location marker, or area selector.
Streets update after saving a walk, not continuously during recording. Walks
outside the bundled area are retained but add no Bremen coverage.

## Durable counts

Database version 2 migrates the recording journal without losing raw points.
`coverage_network` and `coverage_edge` register network identity and valid edges;
`walk_match` stores a processing fingerprint; `walk_edge` stores unique membership.
Counts are a grouped query over that membership: one edge contributes at most
once per walk. Reprocessing replaces membership in a transaction. Unknown edge
ids roll back to the prior match. A network revision has its own counts.

A fingerprint includes the raw serialized trace and matching revision, so both
trace changes and algorithm changes cause rematching. Startup handles recovered
interrupted walks; empty/outside-area results are cached too. Failures preserve
raw walks and existing coverage and expose a retry action. Native computation
runs off the Flutter UI isolate.

## Evaluation and resulting changes

Tests use real OSM geometry with **synthetic**, independently routed traces. They
do not establish phone GPS accuracy. See [fixture provenance](../data/bremen/README.md)
and the machine-readable reports there.

The initial every-node segmentation produced 14,831 tiny edges and poor recall.
Splitting at actual junctions while preserving shape geometry reduced this to
7,930 edges. Evaluation also exposed one-fix excursions onto neighboring streets.
GPX matching now requires two consecutive unambiguous supporting fixes before
painting a directly observed edge. Timed support must be continuous/plausible;
untimed traces can establish repeated direct observations but never inferred fill.

At five-metre synthetic sampling:

| Route | Clean length coverage | 2 m noise length coverage | 6 m noise length coverage | False-positive edges |
| --- | --- | --- | --- | --- |
| Market → Wall | 91.2% | 87.4% | 71.4% | 0 in each case |
| Schlachte | 91.4% | 87.5% | 70.1% | 0 in each case |
| Ostertor | 92.2% | 82.2% | 73.2% | 0 in each case |

The separate three-metre sampling suite also produced zero false positives in all
nine cases, with clean length coverage 85.8–94.4%. Matching took approximately
30–120 ms per short trace in the local release build, excluding loading and
persistence. This is a desktop measurement, not an Android battery/latency result.

Remaining weak points: short edges near junctions, nearby parallel streets,
long primitive edges painted from partial observations, linear nearest-edge
scans, and lack of field traces. Consecutive agreement reduces isolated errors;
sustained GPS bias can still choose a wrong street. The conservative thresholds
need field validation before treating the map as a reliable lifetime record.

## Automated verification

- Python: access rules, topology, stable ids, shape preservation, exact fixture rebuild.
- Rust: real-network loading and clean-route regression; noisy cases through the
  release C ABI evaluation; existing outage/track-break/false-snap regressions.
- Flutter/SQLite: migration, atomic replacement/rollback, version separation,
  refresh idempotency, failure retry, and a real-network rendering check.
- Full integration: simulated recorder → durable raw points → actual Rust FFI
  worker → counts → second walk → database reopen. Refreshing never increments
  counts; the second distinct walk increments each matched edge exactly once.

Run the real native Flutter test with `WANDERLUST_NATIVE_TESTS=1` and
`LD_LIBRARY_PATH` pointing to `target/release`, after building `geo-ffi`. CI enables
this path. Ordinary Flutter runs skip only the native-dependent integration test.

Next device checks: launch/native loading; permission denial/grant; a short Bremen
walk; stop/count redraw; restart/count persistence; interrupted-session recovery.
Then collect and manually label real noisy walking traces before tuning further.

## Local build verification (2026-09-26)

The debug APK was built locally for arm64-v8a and x86_64. Its signature verified;
location permissions are present; both architectures contain Flutter and Rust
ELF libraries; the bundled Bremen asset exactly matches the tested file.
`tools/verify_apk.py` now enforces architecture and asset checks in both APK CI
workflows. This build has not been installed or exercised on a physical phone.

Validation totals: 24 Rust tests (including doctests), 26 Flutter tests including
the real native integration, 11 Python tests, and 18 synthetic matching cases.
Clippy, Flutter analysis, Rust formatting, and diff whitespace checks passed.
