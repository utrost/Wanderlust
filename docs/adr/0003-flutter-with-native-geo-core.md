# ADR-0003: Flutter surface with a native geo-core via FFI

- **Status:** Proposed
- **Date:** 2026-07-07

## Context

We want "Android now, iPhone later almost for free" (see
[ADR-0002](0002-android-first-ios-later.md)) and a **platform-agnostic geo-core**
holding the two hard pieces — map-matching and the routing graph — with a thin
per-platform surface on top.

Three stacks are realistic:

1. **Flutter** — one codebase, a `maplibre` plugin, usable background-location
   packages.
2. **Kotlin + Compose (possibly Compose Multiplatform)** — idiomatic Android,
   native quality, core shareable as a Kotlin module; iOS via Compose MP is the
   shakier route.
3. **React Native** — appealing given React experience, MapLibre binding exists,
   but background GPS + compute-heavy geo processing are least pleasant in JS.

A cross-cutting question: what language holds the geo-core? Dart is convenient
but weaker for compute-heavy spatial work and its ecosystem (routing graphs,
spatial indices) is thin; a native core (e.g. Rust) via FFI is more defensible
and is portable across all three stacks.

## Decision

**Proposed:** build the surface in **Flutter**, and the **geo-core as a native
module (leaning Rust) wired in via FFI** rather than in pure Dart. This gives the
best "Android now, iOS nearly free" story while keeping the performance-critical,
correctness-critical geo logic in a fast, portable, well-tooled language.

Status is Proposed pending a check of current package maturity
(background-location, `maplibre` plugin, Flutter↔Rust FFI ergonomics).

## Consequences

- **Easier:** one UI codebase for both platforms; the geo-core is reusable beyond
  Flutter and testable in isolation; heavy geo math runs at native speed.
- **Harder / accepted:** an FFI boundary adds build complexity and marshalling
  overhead versus staying pure-Dart; contributors need some comfort with the
  native core.
- Reinforces the core/surface split from [ADR-0002](0002-android-first-ios-later.md).

## Alternatives considered

- **Kotlin + Compose Multiplatform** — great on Android, but the iOS path is less
  mature and would weaken the "iOS almost free" promise; reconsider if CMP
  maturity clearly surpasses Flutter's story.
- **React Native** — worst fit for background GPS and compute-heavy processing in
  JS; rejected for *this* app despite React familiarity.
- **Flutter with a pure-Dart core** — simplest build, but Dart is a weaker choice
  for the spatial/routing math and library ecosystem; rejected in favor of a
  native core.
