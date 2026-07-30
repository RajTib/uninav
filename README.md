# UniNav

Data-driven indoor navigation for large campuses. Google Maps stops at the door; UniNav takes over inside. One codebase serves any venue — university, mall, hospital, airport — because **all venue knowledge is data, never code**.

## Repository layout

```
docs/    18 design documents. Start with docs/README.md.
app/     Flutter application
  lib/domain/    pure Dart: routing engine, graph, search, geometry
  lib/data/      JSON codec + repositories
  lib/features/  presentation, one folder per feature
  tool/tracer/   browser floor-plan tracer (zero install)
  tool/survey/   bundle generators
  assets/campuses/  campus + building map data
```

## What works today

- **Routing engine** — A* over a navigation graph, multi-floor transitions as ordinary edges, three route modes (fastest / step-free / prefer-lift), nearest-of-many ("nearest washroom"), turn-by-turn instructions, honest failure classification. Cross-checked against a brute-force Dijkstra on 100 randomly generated graphs.
- **Bundle schema + strict codec** — versioned JSON per building; malformed data degrades to a typed failure, never a crash.
- **Map renderer** — custom `CustomPainter` pipeline over an immutable `FloorScene`, pan/zoom, tap-to-select with domain-level point-in-polygon hit testing, floor switcher, animated route overlay, per-room screen-reader semantics.
- **On-device search** — exact > prefix > bounded Damerau–Levenshtein fuzzy, alias and tag-value search, AND-semantics multi-token queries, favourites/recents ranking boosts.
- **App shell** — GoRouter with deep links, persisted preferences behind a `KeyValueStore` seam, favourites, recents, offline report outbox, onboarding.
- **Mapping toolchain** — a zero-install browser tracer plus two bundle generators.

## What does not work yet

> **The app cannot determine where you are.** There is no indoor positioning — no QR, no BLE, no Wi-Fi RTT, no dead reckoning. You select your starting room and the app routes from there.
>
> The **navigation blob is not built**, and when it ships it will be a **simulation** interpolated along the computed route, labelled as such in the UI. The architecture is built so real positioning becomes one swappable component rather than a rewrite — see [docs/18-navigation-runtime.md](docs/18-navigation-runtime.md).

**The map is two floors of nine**, in one building of ten. Mapping — not engineering — is the binding constraint. See [docs/14-roadmap.md](docs/14-roadmap.md) and [docs/15-known-issues.md](docs/15-known-issues.md).

Also absent by design: Firebase, accounts, community contributions, admin dashboard.

## Run it

```bash
cd app
flutter pub get
flutter test
flutter run                              # VIT Vellore — real, partially mapped
flutter run --dart-define=CAMPUS=demo    # fully populated demo campus
```

Requires Flutter ≥ 3.22 (Dart ≥ 3.4). Four runtime dependencies: `collection`, `flutter_riverpod`, `go_router`, `shared_preferences`.

## Architecture in one paragraph

The domain layer is pure Dart — routing engine, graph, search, geometry, entities — with zero Flutter and zero Firebase imports, so all correctness is testable on the plain VM and reusable outside the app. The data layer converts JSON bundles and hides storage behind repository interfaces. Presentation is Riverpod notifiers plus dumb widgets, with GoRouter URLs as the single source of navigation truth. Map data ships as immutable versioned bundles, one blob per building — the decision that makes offline-first, low running cost, rollback and future community moderation simultaneously possible. Navigation itself is split into four independent layers — route calculation, position provider, navigation engine, UI rendering — so that swapping simulated positioning for real indoor positioning later touches exactly one of them. Full reasoning: [docs/02-architecture.md](docs/02-architecture.md).
