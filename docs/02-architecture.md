# UniNav — System Architecture (v1.0)

## 1. Guiding decisions (and why)

1. **Offline-first, bundle-based data.** The unit of download is a *versioned building bundle* (one JSON blob: floors, rooms, graph), not per-document Firestore reads. Firestore stores metadata + the moderation pipeline; Firebase Storage stores published bundles. This is the single most important cost/perf decision — a 500-room building is one Storage GET instead of 500 reads.
2. **Pure-Dart domain core.** The routing engine, graph model, and search index have zero Flutter/Firebase imports. They are unit-testable on the Dart VM and reusable in the future admin web app.
3. **Repository pattern with swappable data sources.** `BuildingRepository` has `FirebaseBuildingDataSource` and `LocalAssetDataSource` implementations. Dev/demo runs entirely from bundled assets — Firebase is a plug-in, not a foundation.
4. **Feature-first Clean Architecture.** Layers within features, not global layer folders — a solo dev navigates by feature ("search is broken"), not by layer.

## 2. Layering

```
┌────────────────────────────────────────────┐
│ Presentation  (widgets, controllers)       │  Riverpod Notifiers, GoRouter
├────────────────────────────────────────────┤
│ Domain        (entities, repos-as-         │  Pure Dart. No Flutter,
│                interfaces, use cases)      │  no Firebase, no JSON.
├────────────────────────────────────────────┤
│ Data          (DTOs, data sources,         │  JSON codecs, Firestore/Storage,
│                repo implementations)       │  local cache
└────────────────────────────────────────────┘
Dependency rule: outer depends on inner. Domain depends on nothing.
```

Use-case classes are introduced only where logic is non-trivial (`ComputeRoute`, `SubmitContribution`). Trivial pass-throughs call repositories directly from controllers — ceremony without benefit is technical debt too.

## 3. Folder structure

```
lib/
  main.dart                 # bootstrap only
  app/
    app.dart                # MaterialApp.router, theme wiring
    router/app_router.dart  # GoRouter config + guards
    theme/                  # Material 3 theme, tokens
  core/
    error/                  # Failure types, AppException
    result/result.dart      # Result<T> (sealed Ok/Err)
    utils/
    widgets/                # shared design-system widgets
  domain/                   # PURE DART — shared entities & contracts
    entities/               # Campus, Building, Floor, Room, NavNode, NavEdge, ...
    repositories/           # abstract interfaces
    services/routing/       # graph + A* engine
    services/search/        # in-memory search index
  data/
    dtos/                   # JSON ⇄ entity mapping
    sources/                # local_asset, firebase, cache
    repositories/           # implementations
  features/
    campus/                 #   each feature:
    search/                 #     presentation/screens, widgets,
    map/                    #     controllers (Riverpod)
    navigation/
    auth/
    contribution/
    settings/
test/                       # mirrors lib/
assets/campuses/            # demo bundle(s)
```

Why `domain/` and `data/` are top-level rather than per-feature: Room, the graph, and routing are shared by nearly every feature (search, map, navigation, contribution). Duplicating them per feature would force cross-feature imports anyway. Feature folders own only presentation + feature-local state.

## 4. State management (Riverpod)

- **Providers = the DI container.** Repositories and services are exposed as `Provider`s; tests and the demo build override `buildingRepositoryProvider` with fakes. No service locator, no `get_it` — one mechanism, compile-time safe.
- `Notifier`/`AsyncNotifier` for screen state; small immutable state classes (sealed where they are true state machines, e.g. `RouteState = Idle | Computing | Ready | NoPath | Error`).
- Streams (auth state, moderation queue) exposed as `StreamProvider`.
- No `StateProvider` for anything with invariants; logic lives in notifiers, widgets stay dumb.

## 5. Data flow (route computation example)

```
SearchScreen ─select dest→ RouteController(Notifier)
   → ComputeRoute use case
       → BuildingRepository.getGraph(buildingId)   # cached bundle
       → RoutingEngine.findPath(graph, from, to, prefs)  # pure Dart, isolate if >5k nodes
   ← Result<Route, RouteFailure>
RouteController emits RouteState.ready(route) → MapScreen paints overlay
```

## 6. Error handling

- Sealed `Failure` hierarchy in core: `NetworkFailure`, `NotFoundFailure`, `DataFormatFailure`, `PermissionFailure`, `RoutingFailure(noPath | nodeMissing)`.
- Repositories never throw across the boundary; they return `Result<T>`. Data sources may throw internally; the repository is the translation point (catch → typed Failure).
- Presentation maps Failures to user-facing strings centrally (`FailureL10n`), so error copy is consistent and translatable.
- Crashlytics later; until then a `Logger` abstraction with a console sink.

Why `Result` over exceptions at the boundary: routing "no path" and "room not found" are *expected outcomes*, not exceptional; sealed results force the UI to handle them exhaustively.

## 7. Offline & caching

Three tiers:

1. **Bundled assets** — one demo campus ships in the APK (works on first launch, no network, and doubles as the test fixture).
2. **Local bundle cache** — downloaded building bundles stored on disk (JSON files keyed by `buildingId@version`) with a small metadata index. Cache hit = no network at all.
3. **Remote** — Storage bundle download, triggered only when Firestore metadata says `version` changed.

Firestore's built-in offline persistence stays enabled but is treated as a bonus for metadata, not the offline strategy. User data (favorites, recents) is local-first (simple JSON/shared prefs) and mirrored to Firestore when signed in.

## 8. Scalability strategy

- **Data scale:** per-building bundles keep memory bounded — a 100-building campus never loads more than the buildings a route touches. Search index is built per campus from lightweight room summaries (name/alias/ids only), not full geometry.
- **Cost scale:** reads are O(buildings changed), not O(rooms viewed).
- **Compute scale:** routing is on-device; server does zero routing work. Isolate execution keeps UI at 60 fps for big graphs.
- **Team scale:** feature-first layout + pure domain lets future contributors work per-feature without touching the core.

## 9. Testing strategy

| Layer | Tooling | Target |
|---|---|---|
| Domain (engine, search, entities) | `package:test`, pure VM | ~90% — this is where correctness lives |
| Data (DTO codecs, repos) | unit + fake sources; golden JSON fixtures | round-trip every DTO |
| Controllers | Riverpod overrides, fake repos | state-machine transitions incl. failures |
| Widgets | `flutter_test` widget tests | screens render each state; a11y semantics |
| E2E | `integration_test` (later) | search→route happy path |

Static gates: `flutter analyze` with `analysis_options` strict mode (`strict-casts`, `strict-raw-types`), `dart format --set-exit-if-changed`, custom lint set. CI: GitHub Actions on every push.
