# UniNav — Performance & Scale

> **Status:** the rendering and data-layer optimisations described here are shipped. The isolate and LRU strategies are **planned, not implemented** — and deliberately so, because nothing has yet been profiled that needs them.

Related: [Architecture](02-architecture.md) · [Map representation](05-map-representation.md) · [Routing engine](04-routing-engine.md) · [Known issues](15-known-issues.md)

Long-term targets: 100+ buildings, 10k+ rooms per campus, 2 GB RAM devices, minimal backend spend.

---

## 0. The discipline this document is written under

**No optimisation lands without a before/after number, and no speculative optimisation lands before a profile shows need.**

That rule is why several strategies below are documented as *triggers* rather than as code. Writing an isolate boundary for a 41-node graph would add real complexity — asynchrony, serialisation, a harder debugging story — to solve a problem that does not exist. The trigger is recorded so the decision is made on evidence rather than rediscovered under pressure.

The current honest position: **the app has not been profiled.** Nothing here is a measured claim except where explicitly marked.

---

## 1. Architectural decisions that make performance a non-problem

These are worth more than any micro-optimisation, because they change the shape of the cost curve rather than its constant factor.

### 1.1 Bundles instead of per-room reads

One building is one file. `AssetBuildingRepository` caches the parsed `BuildingBundle` in memory keyed by `buildingId`, so reopening a building re-parses nothing.

The alternative — rooms as individual documents — would make the cost of viewing a building O(rooms) in reads, network round-trips and latency. Bundles make it O(1). This is a *cost architecture*, not a tweak ([03 §1](03-data-model.md)).

### 1.2 Search is local

A full scan of ~10⁴ entries with cheap per-token operations is far inside a 16 ms frame budget, and beats any network round-trip by orders of magnitude ([09](09-search.md)). Index built once per bundle version, not per query.

### 1.3 Routing is on-device

The server does zero routing work, so routing cost does not scale with users at all. A* on a few thousand nodes is milliseconds ([04](04-routing-engine.md)).

---

## 2. Rendering — where the real work went

The map is the only screen that can plausibly jank, so it received the attention.

### 2.1 Prebuilt immutable scene

`FloorScene` converts metres to pixels **once**, at construction, and builds every `Path` object then. Painters allocate nothing per frame.

Per-frame `Path` construction is the classic `CustomPainter` performance mistake: at 60 fps a pan allocates and discards the entire floor's geometry sixty times a second, and the garbage collector turns that into visible stutter.

### 2.2 Two-painter split — the single most important rendering decision

```dart
CustomPaint(
  painter: FloorPainter(...),            // static: rooms, corridors, labels, symbols
  foregroundPainter: RoutePainter(...),  // animated: dashed route
)
```

`RoutePainter` passes `super(repaint: animation)`, so only it repaints on animation ticks. Without the split, the 1 Hz dash animation would force every room polygon, every laid-out label and every corridor stroke to repaint 60 times a second — for a decoration.

### 2.3 `shouldRepaint` diffing

Both painters compare scene, style and selection identity. Because `FloorScene` is immutable and rebuilt only when its inputs change, identity comparison is both correct and free.

### 2.4 Text layout caching

`TextPainter.layout` is the expensive part of text rendering. Laid-out room labels are cached per room id for the painter's lifetime, so a pan never re-lays-out text.

### 2.5 Level-of-detail culling

Pin-room labels are culled below `viewScale = 0.25` — unreadable at that zoom, so drawing them costs layout for clutter. Polygon-room labels scale with their room and are never culled.

`viewScale` is a `ValueNotifier` fed from the transform controller, passed to the painter as its `repaint` listenable — so a zoom change repaints the static layer without rebuilding the widget tree.

### 2.6 Scene disposal

`floorSceneProvider` is `FutureProvider.autoDispose.family`. Leaving a floor releases its scene and its paths. Scenes are cheap to rebuild and should not pin memory for floors nobody is looking at.

### 2.7 Grid loop guard

The debug grid returns early if the computed step would fall below 4 scene px — a pathological scale would otherwise spin a loop drawing millions of invisible lines.

---

## 3. Data layer

- **Hand-written codec.** No mirrors, no reflection, no build-time generation — straightforward field access.
- **Coordinate validation in one path.** `_coord` is the only place a `[x, y]` pair is read, so validation is centralised rather than duplicated per call site.
- **Synchronous preference reads.** `main()` awaits `SharedPreferences.getInstance()` **once**, then every read is synchronous. No async plumbing leaks into providers, and no screen renders a spinner while waiting for a boolean.
- **Fire-and-forget writes.** Preference and outbox writes use `.ignore()`. A preference write must never block or crash the UI.

---

## 4. Current measurements

| Quantity | Value |
|---|---|
| `bundle_SJT.json` | 42 KB · 37 rooms · 41 nodes · 42 edges |
| `bundle_main.json` (demo) | 4.3 KB · 5 rooms · 17 nodes · 17 edges |
| Largest traced source | `floor_6.json`, 23 KB |
| Runtime dependencies | 4 (`collection`, `flutter_riverpod`, `go_router`, `shared_preferences`) |

These are **file sizes and counts, not performance measurements.** They are listed because they establish the scale at which the app currently operates — and it is small enough that every deferred optimisation below is correctly deferred.

---

## 5. Planned, with explicit triggers

| Strategy | Trigger | Why not now |
|---|---|---|
| **Routing in an isolate** (`compute()`) | Bundle exceeds ~3k nodes | 41 nodes today. `AStarRouter` is already pure and side-effect free, so it is isolate-ready with no refactor |
| **Bundle decode in an isolate** | Bundle exceeds a few hundred KB | 42 KB. Decode — not routing — is the real jank source at scale, so this trips before the routing trigger |
| **LRU scene/graph eviction** (~5 buildings) | More than one building loaded at once | Only one building is ever loaded |
| **R-tree hit testing** | Profiling shows tap latency | Linear scan over a few hundred rooms per floor is far inside frame budget |
| **Search in an isolate** | Profiling shows keystroke jank | Debounced at 250 ms; corpus is 39 entries |
| **Polygon simplification at export** | Detailed traced outlines appear | Rooms are rectangles or short polygons |
| **Campus-level `bundlesUpdatedAt`** | More than ~20 buildings | Needs the remote tier at all |
| **Downsampled plan underlays** (`cacheWidth`, webp) | Underlay rendering ships | Underlays are not rendered ([05 §8](05-map-representation.md)) |

---

## 6. Unverified claims

Called out because unverified claims presented as facts are worse than acknowledged gaps.

| Claim | Source | Status |
|---|---|---|
| Route computation < 200 ms for ≤10k nodes | [01](01-srs.md) NFR-1 | **Not measured.** Largest graph tested is 41 nodes |
| Cold start < 3 s; map interactive < 1 s | NFR-2 | **Not measured** |
| Usable on 2 GB RAM devices | NFR-4 | **Not tested** |
| ≥80% domain test coverage | NFR-8 | **Not measured** — no coverage run exists |
| 60 fps on map pan | This document, previously | **Not measured.** The optimisations are sound in principle; the number is absent |

**What would close these:** a synthetic 10k-node graph benchmark in `test/`, a `flutter test --coverage` run in CI, a DevTools timeline capture on a mid-range device, and a cold-start trace. None is hard; none has been done. Tracked in [15-known-issues.md](15-known-issues.md).

---

## 7. Offline as the default path

Every user-facing operation — search, route, render — reads from the cache tier. There is no "offline mode" branch, and therefore no offline branch that can rot untested while everyone develops online.

The tiers are bundled assets → parsed-bundle memory cache → (planned) disk cache → (planned) network. Today the app never leaves the first two, which is why offline works perfectly and why nothing about it is currently at risk.
