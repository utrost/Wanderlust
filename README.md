# Wanderlust

**Paint the streets you've walked.**

Wanderlust is an offline-first, privacy-respecting walking app. As you walk, it
colors the streets of your city onto the *real* street network — the more often
you walk a street, the more intense its color and width. No pace, no calories,
no streaks, no leaderboards. Just the quiet, addictive pleasure of watching your
personal territory grow.

It is the opposite of a fitness tracker. You are not an athlete here — you are a
cartographer of your own world.

> **Status: pre-alpha — vision & design only.** There is no application code in
> this repository yet. What follows is a set of design documents that describe
> what Wanderlust is and how it will be built.

---

## What makes it different

- **Collecting, not competing.** The filling map *is* the reward. No leaderboards,
  no social ranking, no streaks.
- **Serendipity over navigation.** The app invites you into unwalked alleys; it
  never commands a route.
- **A life map, not a log.** Over years it becomes a portrait of how you move
  through the world — a keepsake, not a statistic.
- **Local by default.** No account, no login, no telemetry. Your location data —
  the most sensitive thing an app can know about you — never leaves your device.

---

## Documentation

| Doc | For whom | What's in it |
| --- | --- | --- |
| [Design Spec](docs/DESIGN.md) | Anyone who wants the "why" | Philosophy, core mechanic, gamification, full feature set, non-goals |
| [User Guide](docs/USER_GUIDE.md) | Future users | How the app works from the outside: walking, maps, finds, notes, import/export |
| [Architecture](docs/ARCHITECTURE.md) | Contributors | System shape, map-matching approach, data model, stack, key risks |
| [Roadmap](docs/ROADMAP.md) | Contributors & the curious | Phased plan from geo-core to iOS, what's deferred and why |
| [Decision Records](docs/adr/README.md) | Contributors | The load-bearing technical decisions and their rationale |

If you're new, read the [Design Spec](docs/DESIGN.md) first — everything else
follows from it.

---

## License

Licensed under the **GNU Affero General Public License v3.0** — see
[`LICENSE`](LICENSE). The choice is still under discussion for a local-first
client that never talks to a server; see
[ADR-0006](docs/adr/0006-license.md).
