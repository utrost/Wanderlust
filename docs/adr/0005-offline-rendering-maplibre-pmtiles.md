# ADR-0005: Offline rendering with MapLibre Native + PMTiles

- **Status:** Superseded by [ADR-0008](0008-offline-geojson-cell-rendering.md)
- **Date:** 2026-07-07

## Context

The app must render a real street map and paint per-segment walk counts onto it,
**fully offline** ([ADR-0004](0004-local-first-no-cloud.md)) and bounded in size —
no planet download, no tile server. Users select an area (city / district /
drawn rectangle) and the map for just that area is loaded on demand.

## Decision

- Render with **MapLibre Native** — open source, no proprietary tile service,
  data-driven styling that can map an `edge_id → count` to color and width.
- Store each area's basemap as a single **PMTiles** file — one self-contained,
  range-readable archive per area, loaded on demand. No tile server, no per-tile
  HTTP.
- Ship **one PMTiles file per area**; a city in street detail is roughly
  tens-to-low-hundreds of MB.

## Consequences

- **Easier:** genuinely offline; a whole area is one file (easy to download,
  cache, delete, or side-load); data-driven styling makes the heatmap a rendering
  concern, not a bespoke draw loop; the "passport" multi-area model is just
  multiple files.
- **Harder / accepted:** producing / sourcing PMTiles per selected area is a
  pipeline to build; per-area files can grow large, so download/storage UX
  matters; the walk-count overlay must be kept in sync with the basemap's segment
  identifiers.

## Alternatives considered

- **Online tile server / vector tiles over HTTP** — simplest to render, but breaks
  offline-first and implies infrastructure; rejected.
- **Raster tiles cached on device** — offline-capable, but no data-driven styling
  for the count-based heatmap and far larger on disk; rejected.
- **Full offline planet / regional extracts in a raw format** — too big and
  unbounded; PMTiles' per-area, range-readable model fits the bounded-area design.
