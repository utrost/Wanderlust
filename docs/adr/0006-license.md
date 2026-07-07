# ADR-0006: License

- **Status:** Proposed
- **Date:** 2026-07-07

## Context

Wanderlust is intended as open source. The repository currently ships the **GNU
Affero General Public License v3.0 (AGPL-3.0)** in [`LICENSE`](../../LICENSE),
while the original design notes said only "License TBD" — so the two are not yet
reconciled.

AGPL's distinguishing feature is its **network-use clause**: if you run modified
AGPL software as a *network service*, you must offer users the source. But
Wanderlust is a **local-first client that deliberately has no server and never
phones home** ([ADR-0004](0004-local-first-no-cloud.md)). The exact clause that
makes AGPL "stronger" than GPL never triggers for this app, so AGPL may be an
imperfect fit even though it isn't wrong.

## Decision

**Proposed / unresolved.** Keep AGPL-3.0 as the current placeholder, but decide
deliberately between:

- **GPL-3.0** — strong copyleft matched to a client with no network-service
  surface; arguably the most honest fit.
- **AGPL-3.0** — hedges in case a future optional server component ever appears;
  currently in the repo.
- **MPL-2.0** — weaker, file-level copyleft; friendlier to reuse/embedding, less
  protective.

This ADR should move to Accepted once the choice is made, and the `LICENSE` file
and README updated to match.

## Consequences

- Until resolved, the README notes AGPL "under discussion" rather than presenting
  it as final, so contributors aren't misled about the intended terms.
- The choice affects how others may reuse the geo-core and surface, so it should
  be settled before meaningful external contribution begins.

## Alternatives considered

Captured in the Decision above (GPL-3.0 vs. AGPL-3.0 vs. MPL-2.0); the trade-off
is copyleft strength and network-clause relevance versus reuse-friendliness.
