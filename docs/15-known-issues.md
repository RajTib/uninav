# UniNav — Known Issues, Technical Debt & Next Steps

An honest register of what is unfinished, deferred, or risky. Kept in-repo so nothing lives only in someone's memory, and so a reviewer can tell what is known from what was missed.

Related: [Roadmap](14-roadmap.md) · [Architecture](02-architecture.md) · [Routing engine](04-routing-engine.md) · [Mapping guide](16-mapping-guide.md)

---

## 0. 🔴 ACTIVE REGRESSION — the shipped SJT bundle is empty

**`assets/campuses/vit-vellore/bundle_SJT.json` currently contains no map at all.** It is 171 bytes:

```jsonc
{ "schemaVersion": 1, "buildingId": "UNKNOWN", "buildingName": "UNKNOWN",
  "version": 1, "floors": [], "rooms": [], "pois": [], "nodes": [], "edges": [] }
```

Committed in `83cb90d "added floor 5"`. The app therefore shows **nothing** for SJT — no floors, no rooms, no routes. The traced sources (`floor_5/6/8.json`) are intact, so no work was lost; only the generated artefact is bad.

**Root cause.** `floorplan_to_bundle.dart` collected inputs with `args.where((a) => a.endsWith('.json'))`. Given no argument ending in `.json`, `inputs` was empty, `convert([])` returned a bundle with `buildingId ?? 'UNKNOWN'` and zero floors, `errors` was empty — so the tool reported success and overwrote a good map with an empty one.

**Fixed in the tool** (three guards added):

1. Reject an empty input list with a usage message showing the full multi-floor command.
2. Reject a 0-byte floor file by name, rather than failing obscurely later.
3. Refuse to write a bundle with zero floors or zero nodes — an empty bundle is always a tooling failure, never a legitimate result.
4. Exclude the `--out` path from `inputs` — it also ends in `.json`, so it was being read back as an input floor document.

**Still to do — regenerate the bundle:**

```bash
cd app
dart run tool/survey/floorplan_to_bundle.dart \
    assets/campuses/maps/sjt/floor_5.json \
    assets/campuses/maps/sjt/floor_6.json \
    assets/campuses/maps/sjt/floor_8.json \
    --out assets/campuses/vit-vellore/bundle_SJT.json
```

All three floors must be in **one** command — vertical stair/lift links are only created between the floors passed together, so regenerating one at a time yields a disconnected building.

---

## 1. Data & content gaps

### 1.1 SJT is 3 traced floors of 9 — **highest priority**

Traced sources, as of this pass:

```
maps/sjt/floor_0.json   0 bytes   ← empty placeholder
maps/sjt/floor_1.json   0 bytes      plan image now available (1st floor.jpeg)
maps/sjt/floor_2.json   0 bytes      plan image now available (2nd floor.jpeg)
maps/sjt/floor_3.json   0 bytes      plan image now available (3rd floor.jpeg)
maps/sjt/floor_4.json   0 bytes      plan image now available (4th floor.jpeg)
maps/sjt/floor_5.json  23 KB      ✅ 23 nodes, 24 edges, 5 corridors
maps/sjt/floor_6.json  23 KB      ✅ 22 nodes, 21 edges, 3 corridors
maps/sjt/floor_7.json   0 bytes      no plan image
maps/sjt/floor_8.json  11 KB      ✅ 19 nodes, 19 edges, 4 corridors
```

Plan images now exist for floors **1, 2, 3, 4, 5, 6 and 8** — only the Ground Floor and floor 7 still lack one. Tracing, not image acquisition, is now the bottleneck. This remains the binding constraint on the project — see [Phase 1](14-roadmap.md).

> Floor 5 is traced but **not yet in any bundle**, because of the regression in §0.

### 1.2 No `entrance` node anywhere in the SJT bundle

Node kinds present: `room` (31), `junction` (6), `elevator` (2), `stair` (2). There is no `entrance` and no `exit`.

Consequences:

- Routes have no natural default origin. The user must pick a start room from a dropdown.
- The reachability validation in `survey_to_bundle` ("every room reachable from the first entrance") cannot run — and, separately, the generator that actually produced this bundle does not implement that check at all (§2.1).

Fix with the Ground Floor in Phase 1.

### 1.3 Floor 7 gap between the two mapped floors

The single vertical connector spans levels 6 → 8, `floorsCrossed = 2`. Routing is correct — the cost model handles multi-floor spans — but the instruction reads "Take the lift to 8th Floor" and silently skips a floor that physically exists. Resolves itself once floor 7 is mapped.

---

## 2. Technical debt

### 2.1 Two divergent bundle generators — **the most significant debt**

| | `survey_to_bundle.dart` | `floorplan_to_bundle.dart` |
|---|---|---|
| Input | `.survey` paced field notes | Traced plan JSON from `tool/tracer` |
| **In active use** | **No** | **Yes** — produced every shipped bundle |
| Runs `NavGraph.fromBundles` validation | **Yes** | **No** |
| Refuses to write on graph errors | **Yes** | Only on its own ad-hoc checks |
| Reachability check from entrance | **Yes** | **No** |
| Emits through `BuildingBundleDto` | **Yes** (typed entities) | **No** — hand-built `Map<String, dynamic>` |

**The stricter, safer pipeline is the one nobody uses.** The pipeline in daily use bypasses the app's own validation entirely and hand-assembles JSON, so it can emit a bundle the app will reject — the exact failure the validation exists to prevent.

Fix: port `NavGraph` validation and reachability into `floorplan_to_bundle`, and make it construct typed entities and serialise through `BuildingBundleDto`, so format drift becomes structurally impossible. Then decide whether to keep or retire the `.survey` path.

### 2.2 `assumedFloorHeightM` has a third copy

A previous pass consolidated this constant into `NavGraph.assumedFloorHeightM`, referenced by `AStarRouter`'s constructor default — because if the build-time safety check and the search-time heuristic disagree, an edge can pass validation and still make the heuristic inadmissible ([04 §3.1](04-routing-engine.md)).

But `floorplan_to_bundle.dart` still declares its own:

```dart
const assumedFloorHeightM = 3.5;   // "kept in sync here"
```

A comment is not a mechanism. The tool already imports from `package:uninav/...`; it should import the constant too.

### 2.3 Node kinds are lost in `floorplan_to_bundle`

```dart
'kind': _nodeKinds[kindSource] ?? 'room',
```

`_nodeKinds` maps only `lift_junction`, `lift`, `staircase`, `entrance`, `exit`. Everything else — corridor points, doorway points, junctions — falls back to `'room'`. That is why the SJT bundle reports 31 `room` nodes for 37 rooms while having no `corridor` nodes at all.

Routing is unaffected (`NodeKind` does not influence cost), but it is semantically wrong, and `FloorScene` uses node kind to decide which nodes get map symbols. Fall back to `corridor` and map doorway points to `room` explicitly.

### 2.4 POI `gender` lives in `tags`, but the schema doc once implied a field

Resolved in favour of the code: `tags: {"gender": "male"}`. Noted because both `floorplan_to_bundle` and the docs previously suggested otherwise. [03-data-model.md](03-data-model.md) now matches the code.

### 2.5 CI has never passed

`.github/workflows/ci.yml` runs `flutter analyze` and `flutter test`. **Every commit in the repository's history shows a failing check**, including the initial one.

**Leading cause: `flutter analyze` defaults to `--fatal-infos`,** so *any* info-level lint fails the build — and `analysis_options.yaml` enables a strict set (`avoid_dynamic_calls`, `require_trailing_commas`, `prefer_single_quotes`, `directives_ordering`, `prefer_final_locals`, …) on top of `strict-casts` / `strict-inference` / `strict-raw-types`. The codebase has never been brought to a clean analyzer state.

**Fixed in this pass**

| Issue | Where |
|---|---|
| `avoid_dynamic_calls` — inline `as` does not promote a `dynamic` loop variable, so the *second* index was an unchecked dynamic invocation | `floorplan_to_bundle.dart` ×3, `search_controller.dart` ×1 |
| SDK floor declared `>=3.22.0` while the code needs ≥3.32 (`RadioGroup`, `DropdownButtonFormField.initialValue`, `Matrix4.translateByDouble`) | `pubspec.yaml` |

**Remaining — needs the real analyzer.** These are mechanical and should be applied with tooling, not by hand:

```bash
cd app
dart fix --dry-run          # see what will change
dart fix --apply            # trailing commas, quotes, final locals, …
dart format .
flutter analyze             # then read whatever is genuinely left
```

Only once `flutter analyze` is clean should a `dart format --set-exit-if-changed .` step be added to CI — a gate that starts red teaches everyone to ignore it.

Candidates the analyzer may still flag, unverified from here: raw `List` / `Map` in `is` / `as` positions under `strict-raw-types` (`building_bundle_dto.dart` ×5, `floorplan_to_bundle.dart` ×6).

### 2.6 Repository hygiene

**Fixed in this pass:** `.fuse_hidden*` copies, `_recovery/*.backup.json` and `android/.kotlin/errors/*.log` untracked from git and added to `.gitignore`, along with `android/local.properties` and `.claude/`.

**A real leak risk was also closed.** `app/.gitignore` protected institutional floor plans with a bare `*.png` — which silently stopped working the moment plans arrived as `1st floor.jpeg` … `4th floor.jpeg`. Those four were untracked and would have been committed by any `git add .`, against the root `.gitignore`'s explicit "NEVER commit these" policy. The rule is now **path-based** (`assets/campuses/maps/**`) rather than extension-based, so it holds for any format. As a side effect, `web/favicon.png` and the launcher icons — which the old blanket `*.png` also excluded — are committable again.

**Still outstanding**

| Item | Problem |
|---|---|
| `app/README.md` | Still the default `flutter create` template |
| `floor plans.pdf` (9.5 MB) | Large binary at repo root |
| `rough.json`, `sjt_floor8_preview.png`, `sjt_floor8_v2.png` | Scratch files at repo root |
| `app/demo_map.png`, `demo_routing.png`, `nav_demo.png`, `release_home.png` | Now gitignored, but should move to `docs/assets/` if they are wanted in the repo |

### 2.7 Unverified performance claims

[01-srs.md](01-srs.md) NFR-1 asserts <200 ms routing for 10k nodes; NFR-8 asserts ≥80% domain coverage. Neither is measured. Current graphs are 17–41 nodes, so nothing has been stressed. Either build a benchmark and a coverage run, or restate the claims as targets. They are now marked unverified in the SRS.

---

## 3. Missing functionality (known, sequenced)

| # | Gap | Notes |
|---|---|---|
| 1 | **No navigation blob / position provider / navigation engine** | The MVP's headline missing piece. Only a marching-dash route animation exists. Design: [18-navigation-runtime.md](18-navigation-runtime.md) |
| 2 | **No indoor positioning of any kind** | Deliberate. Research directions in [18 §5](18-navigation-runtime.md) |
| 3 | No raster underlay rendering | Schema carries `planImagePath`; the painter ignores it. Blocked on the remote data source + disk cache tier, not on the drawing code — building a local-only loader now means throwing it away later |
| 4 | No Firebase | Auth, bundle sync, contribution upload, outbox drain. Every touchpoint already sits behind a repository interface or the outbox, so it is additive |
| 5 | Favourites/recents are device-local | Cross-device sync arrives with auth |
| 6 | Routing runs on the main isolate | Fine at 41 nodes. Move to `compute()` past ~3k, and measure first |
| 7 | Instruction text is English-only | `InstructionKind` plus structured fields exist so l10n can replace strings without touching search or routing |
| 8 | No voice guidance, haptics, or reduced-motion gating | [10-accessibility.md](10-accessibility.md) |
| 9 | No high-contrast or colourblind-verified palette | Styling derives from `ColorScheme`, so this is a theme addition, not a painter change |
| 10 | One campus per build | `--dart-define=CAMPUS=…`; runtime selection needs the remote tier |

---

## 4. Fixed in earlier audit passes

Retained because the reasoning is more valuable than the fix.

| Finding | Severity | Fix |
|---|---|---|
| `NavGraph.fromBundles` defaulted `framesAligned: true`, so merging two buildings fed A* an inadmissible heuristic — returning **silently suboptimal routes** | High | Default is now `bundles.length == 1`; multi-building callers must opt in after georeferencing |
| A bad `lengthM` in map data could break admissibility the same way | High | Build-time straight-line validation; flags `GraphIssue.impossibleLength` and disables the heuristic graph-wide |
| Failure classification used `identical(prefs, RoutePrefs.fastest)` | Medium | Compares `prefs.mode`; caller-built prefs now classify correctly |
| `findNearestRoute` always reported `disconnected` | Medium | Distinguishes "constraints blocked it" from "genuinely unreachable" |
| Map floor was sticky global state across a route plan | Medium | A new route clears the manual floor override |
| "Nearest washroom" did nothing visible on failure | Medium | Reports outcome via snackbar |
| Home search bar was a live field that discarded input | Low | Replaced with a tappable launcher carrying button semantics |
| Map canvas exposed only one summary `Semantics` label | Medium (a11y) | `FloorPainter.semanticsBuilder` emits one node per room, with tap wired through the same path a sighted tap uses; asserted by widget tests |
| No camera auto-centering on selection or route | Low | Centres on new targets only; never fights a manual pan |
| `assumedFloorHeightM` duplicated between router and graph | Low (latent) | Single source of truth in `NavGraph` — **but see §2.2, a third copy survives in tooling** |
| `test/widget_test.dart` used `Widget` without importing it — an analyze **error** | Low | Import added |

---

## 5. Do this first

1. [ ] **Regenerate `bundle_SJT.json`** from floors 5, 6 and 8 in one command (§0). The app has no map until this is done.
2. [ ] **Get CI green:** `dart fix --apply && dart format . && flutter analyze` (§2.5).
3. [ ] Delete the stale `app/../.git/index.lock` left by this session's staged removals, if git complains.

## 6. Before any public release

- [x] `flutter analyze` and `flutter test` wired into CI on every push and PR
- [ ] **CI actually passing** — it never has (§2.5)
- [ ] `dart format --set-exit-if-changed` clean, *then* gated in CI
- [ ] Manual TalkBack pass on every screen
- [ ] Six SJT floors mapped, with an `entrance` node
- [ ] Graph validation running in the generator that is actually used (§2.1)
- [ ] Simulated navigation shipped **and visibly labelled as simulated**
- [ ] Repository root cleaned (§2.6); `app/README.md` written
- [ ] Performance claims measured or restated (§2.7)
- [ ] Firestore/Storage rules tested against the emulator suite before any deployment
