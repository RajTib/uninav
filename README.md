# UniNav

Data-driven indoor navigation platform. Google Maps stops at the door; UniNav takes over inside. One codebase serves any venue — university, mall, hospital, airport — because **all venue knowledge is data, never code**.

## Repository layout

```
docs/    14 design documents (SRS → roadmap). Start with 01-srs.md and 14-roadmap.md.
app/     Flutter application
```

## Status: Milestones 1–4 implemented

- **M1 — Core:** Clean Architecture skeleton, pure-Dart A* routing engine (floor transitions, accessible/prefer-lift modes, turn-by-turn with floor names), versioned bundle JSON schema + strict codec, demo campus asset. Randomized engine test cross-checks against reference Dijkstra.
- **M2 — Map:** custom CustomPainter floor renderer (immutable FloorScene, two-layer painting so the animated route overlay never repaints rooms), pan/zoom, tap-to-select with domain-level point-in-polygon hit testing, floor switcher, transition badges.
- **M3 — Search:** on-device index (exact > prefix > bounded Damerau-Levenshtein fuzzy), alias/tag search, AND-semantics multi-token queries, favorites/recents ranking boosts, debounced UI.
- **M4 — Shell:** persisted preferences behind a `KeyValueStore` seam (in-memory default for tests, shared_preferences in prod), settings (theme, default route mode incl. step-free), favorites, persistent recents, nearest-washroom multi-goal routing, POI destinations, report-a-problem **offline outbox** (drains to Firestore in M5), first-run onboarding, 404 page, back-navigation fixes.

Still intentionally absent: Firebase (M5 — every remote touchpoint already sits behind a repository interface or outbox), real campus data (M6), community moderation (M8), admin editor (M9). See `docs/14-roadmap.md`.

## Run it

```bash
cd app
flutter pub get     # new dependency: shared_preferences
flutter test
flutter run
```

Requires Flutter ≥ 3.22 (Dart ≥ 3.4).

## Architecture in one paragraph

Domain layer is pure Dart (engine, graph, search, entities) and owns all correctness; data layer converts JSON bundles and hides storage behind repositories; presentation is Riverpod notifiers + dumb widgets, with GoRouter URLs as the single source of navigation truth. Map data ships as immutable versioned bundles (one blob per building) — the key decision that makes offline-first, low Firestore cost, rollback and community moderation all possible. Full reasoning: `docs/02-architecture.md`.
