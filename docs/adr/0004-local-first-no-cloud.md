# ADR-0004: Local-first, no cloud, no account

- **Status:** Accepted
- **Date:** 2026-07-07

## Context

Location data is the most sensitive thing an app can know about a person — where
you live, when you're away, your daily habits. The incumbent walking/fitness apps
are built around accounts, cloud sync, and data collection. Wanderlust's identity
is the exact opposite, and this is its strongest distinguishing trait.

## Decision

Wanderlust is **local-first with no account, no login, and no telemetry.** All
data lives as local files (SQLite for state, exportable as GeoJSON / GPX). The
app **never phones home** — no ads, no analytics, no required cloud.

Backup and portability are user-driven: export to GeoJSON / GPX / ZIP, and back
up via git or the user's own server if they choose. Any future sync is opt-in and
self-hosted, never required.

## Consequences

- **Easier:** no backend to build, secure, or pay for; no privacy policy
  minefield; trivially works offline.
- **Harder / accepted:** no server-side map-matching (reinforces
  [ADR-0001](0001-pragmatic-map-matching.md)); no cross-device sync out of the
  box; device loss without a user backup means data loss — so export/backup UX
  must be genuinely good, not an afterthought.
- Constrains many downstream choices: matching runs on-device, maps render from
  local PMTiles ([ADR-0005](0005-offline-rendering-maplibre-pmtiles.md)), and the
  full non-goals list (leaderboards, accounts, telemetry) follows.

## Alternatives considered

- **Optional cloud account / sync** — convenient for multi-device and backup, but
  every account system is a data-collection temptation and erodes the core promise;
  rejected as a default. Self-hosted, opt-in backup covers the real need.
- **Anonymous analytics** — even "privacy-respecting" telemetry contradicts the
  never-phone-home stance; rejected outright.
