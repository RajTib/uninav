# UniNav — Known Issues & Next Steps (as of M4 + audit pass)

Honest register of what is unfinished, deferred, or risky. Kept in-repo so nothing lives only in memory.

## Fixed during the audit pass

| Finding | Severity | Fix |
|---|---|---|
| `NavGraph.fromBundles` defaulted `framesAligned: true`, so merging two buildings (each with building-local coordinates) fed A* an inadmissible heuristic — which returns **suboptimal routes silently**, not just slower searches | High (latent; multi-building only) | Default is now `bundles.length == 1`; multi-building callers must opt in after georeferencing |
| A bad `lengthM` in map data (typo, or community edit) could break heuristic admissibility the same way | High (arrives with real data) | Graph build now validates every edge against its straight-line distance, reports a `GraphIssue.impossibleLength`, and disables the heuristic for that graph (falls back to Dijkstra, which stays correct) |
| Failure classification used `identical(prefs, RoutePrefs.fastest)` | Medium | Compares `prefs.mode`; caller-built prefs now classify correctly |
| `findNearestRoute` always reported `disconnected` on failure | Medium | Now distinguishes "constraints blocked it" (e.g. no step-free washroom) from "genuinely unreachable" |
| Map floor was sticky global state: plan a route, tap "View on map", land on the floor you last browsed | Medium (UX) | New route clears the manual floor override; the screen re-resolves to the route's start floor |
| "Nearest washroom" did nothing visible on failure | Medium (UX) | Reports outcome (distance, or why not) via snackbar |
| Home search bar was a live text field that discarded typed input | Low (UX) | Replaced with a proper tappable launcher + button semantics |

## Fixed since the M4 audit pass

| Finding | Severity | Fix |
|---|---|---|
| Map canvas exposed only a single summary `Semantics` label; individual rooms were invisible to screen readers below it | Medium (a11y) | `FloorPainter.semanticsBuilder` now emits one `CustomPainterSemantics` node per room (name + type label, button + selected state, tap action wired through the same `_selectRoom` path a sighted tap uses). Widget tests assert the traversal, selection state, and that activating a room's semantics action selects it. |
| No camera auto-centering: selecting a room, or landing on the map from a planned route, left the user to pan/zoom manually to find it | Low (UX) | Map screen now centers the camera on the selected room, or — when nothing is selected — on the route's start point while its start floor is showing. A target that's already centered doesn't fight a manual pan; re-selecting after clearing does re-center. |
| `_assumedFloorHeightM` duplicated between `AStarRouter` (search-time heuristic) and `NavGraph` (build-time heuristic-safety validation) — harmless while both happened to be `3.5`, but the two *must* agree, or the safety check stops validating what the heuristic actually assumes at search time | Low (latent correctness risk) | Single source of truth: `NavGraph.assumedFloorHeightM` (public `static const`); `AStarRouter`'s constructor default now references it instead of repeating the literal. |
| `test/widget_test.dart` used the `Widget` type without importing it — a pre-existing `flutter analyze` **error**, not just an info-level lint, contradicting this doc's "flutter analyze is clean" baseline | Low (build hygiene) | Added the missing `package:flutter/widgets.dart` import. |

## Open issues (ranked)

1. **Demo data is a fixture, not a map.** `assets/campuses/demo/bundle_main.json` exists to exercise the pipeline. Real mapping is M6 and is the project's biggest *non-technical* risk — budget grind time, not cleverness.
2. **No Firebase yet.** Auth, bundle sync, contributions, and the feedback outbox drain are all M5. Every touchpoint already sits behind a repository interface or the outbox, so this is additive.
3. **Recents/favorites are device-local.** Cross-device sync arrives with auth (M5).
4. **No raster underlay rendering.** Schema supports `planImagePath`; the renderer ignores it. Re-evaluated this pass, still deferred: the *draw* half (decode + paint beneath room fills at reduced opacity, per docs/05's rendering pipeline) is mechanically testable today with a synthetic fixture image — that's not what's blocking it. The *load* half is: `planImagePath` is a Storage-relative path (docs/03's example is `plans/SJT/f2.webp`), meant to be fetched through the M5 remote data source + disk-cache tier (docs/02 §7), which doesn't exist yet. A local-asset-only loader built now would need to be thrown away and redone once M5 lands, so this stays parked with Firebase rather than growing throwaway code.
5. **Routing runs on the main isolate.** Fine at demo scale; move to `compute()` when a bundle exceeds ~3k nodes (docs/11-performance.md). Measure before moving.
6. **Instruction text is English-only** and built in the engine. `InstructionKind` + structured fields exist so l10n can replace strings without touching search or routing.

## Deliberate non-goals for now

Live indoor positioning, AR, beacons, timetable integration — all documented in `13-feature-backlog.md` and gated behind QR checkpoints proving the localization UX first.

## Before any public release

- ~~Run `flutter analyze` + full test suite in CI~~ — done: `.github/workflows/ci.yml` runs both on every push/PR.
- `dart format --set-exit-if-changed .` currently reports 23 files needing reformatting under the installed Dart 3.12 formatter (`dart_style` convention drift since these were last saved, not anything touched this pass). Not fixed here to avoid an unrelated mass diff — run it and commit a clean pass before adding a format gate to CI, so the gate doesn't start red.
- Manual TalkBack pass on every screen.
- Firestore/Storage rules deployed **and** tested with the emulator suite (rules exist in `app/firebase/`, untested against a live project).
- Replace the demo bundle with a real, field-verified building.
