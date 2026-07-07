# ADR-0002: Android first, iOS later

- **Status:** Accepted
- **Date:** 2026-07-07

## Context

Wanderlust needs reliable background GPS, on-device map rendering, and fairly
free file handling (imports, exports, per-area map files). Building two platforms
at once would multiply the cost of the riskiest, most platform-specific work.

## Decision

Ship **Android first**, add **iOS later**. Keep the geo-core platform-agnostic
(see [ADR-0003](0003-flutter-with-native-geo-core.md)) so iOS is a veneer over
existing logic rather than a second implementation.

## Consequences

- **Easier:** Android imposes fewer restrictions on background GPS and file
  handling, so the hard sensor work is less fraught on the first platform. A
  single target keeps early velocity high.
- **Harder / accepted:** iOS users wait. iOS background-location and file
  constraints differ meaningfully and must be re-verified when Phase 3 starts —
  "it works on Android" does not transfer.
- Because the core is reusable, the incremental cost of iOS is the surface layer,
  not the geo logic.

## Alternatives considered

- **iOS first** — stricter background-location model makes the riskiest work
  harder up front; rejected.
- **Both simultaneously** — doubles the cost of the hardest, most
  platform-specific pieces before the concept is proven; rejected.
