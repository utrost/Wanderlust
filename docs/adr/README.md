# Architecture Decision Records

Short documents that capture a single significant decision: the context, the
choice, and the consequences. They record *why* Wanderlust is built the way it
is, so future contributors (and future us) don't re-litigate settled ground —
or, when a decision is revisited, can see what it costs.

Format: lightweight [MADR](https://adr.github.io/madr/)-style. New records use
[`0000-template.md`](0000-template.md), numbered sequentially, never renumbered.
When a decision changes, add a new ADR that supersedes the old one rather than
editing history.

## Index

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-pragmatic-map-matching.md) | Pragmatic map-matching (snap + graph fill), not HMM | Accepted |
| [0002](0002-android-first-ios-later.md) | Android first, iOS later | Accepted |
| [0003](0003-flutter-with-native-geo-core.md) | Flutter surface with a native geo-core via FFI | Proposed |
| [0004](0004-local-first-no-cloud.md) | Local-first, no cloud, no account | Accepted |
| [0005](0005-offline-rendering-maplibre-pmtiles.md) | Offline rendering: MapLibre Native + PMTiles | Accepted |
| [0006](0006-license.md) | License (AGPL-3.0, under review) | Proposed |
| [0007](0007-fog-of-war-optional-reveal-lens.md) | "Fog of war" as an optional reveal lens ("Uncharted"), not a default | Proposed |
