# geo-core

The platform-agnostic heart of Wanderlust (ADR-0003): the two hard,
correctness-critical pieces — the routing graph and **map-matching** — plus the
local data model, in fast, portable Rust. The Flutter surface links this via
FFI; nothing here knows about UI or platform.

## Status — Phase 0 spike (implemented, tested)

- **Map-matching** with the *don't-paint-what-you-didn't-walk* guardrail
  (ADR-0001): snap GPS points to the nearest edge, then fill gaps with the
  shortest path **only when it's plausible** — an implausible detour is left
  dark rather than painting streets the walker never touched.
- **Routing graph**: segments fused at shared junctions, nearest-segment lookup,
  Dijkstra shortest path.
- **Data model**: the on-device SQLite schema (`schema.rs`), local-first
  (ADR-0004).
- **GPX**: a minimal track-point reader so real exports can be fed in.

Phase 0 exit criterion — *"GPX in → correct per-segment counts, no phantom
streets"* — is encoded in [`tests/matching.rs`](tests/matching.rs).

## Build & test

```bash
cargo test              # unit + integration + doctest
cargo clippy --all-targets
cargo fmt --check
```

## Next

- A spatial index (R-tree / grid) to replace the O(n) nearest-segment scan.
- Bearing-aware snapping to resolve near-junction ambiguity.
- The FFI bridge (leaning `flutter_rust_bridge`) and the SQLite storage layer.
- Cross-compilation for Android (NDK targets) and iOS.
