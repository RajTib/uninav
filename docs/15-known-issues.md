# UniNav — Known Issues, Technical Debt & Next Steps

An honest register of what is unfinished, deferred, or risky. Kept in-repo so nothing lives only in someone's memory, and so a reviewer can tell what is known from what was missed.

Related: [Roadmap](14-roadmap.md) · [Architecture](02-architecture.md) · [Routing engine](04-routing-engine.md) · [Mapping guide](16-mapping-guide.md)

---

## 1. Data & content gaps

### 1.1 SJT is 2 floors of 9 — **highest priority**

`bundle_SJT.json` contains floors **6 and 8 only**: 37 rooms, 41 nodes, 42 edges.

```
maps/sjt/floor_0.json   0 bytes   ← empty placeholder
maps/sjt/floor_1.json   0 bytes
maps/sjt/floor_2.json   0 bytes
maps/sjt/floor_3.json   0 bytes
maps/sjt/floor_4.json   0 bytes
maps/sjt/floor_5.json   0 bytes   ← plan image exists, tracing does not
maps/sjt/floor_6.json  23 KB      ✅
maps/sjt/floor_7.json   0 bytes
maps/sjt/floor_8.json  11 KB      ✅
```

Only `5th floor.png`, `6th floor.png` and `8th floor.png` are present, so floors 0–4 and 7 need plan images before they can even be traced. This is the binding constraint on the whole project — see [Phase 1](14-roadmap.md).

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

### 2.5 Repository hygiene

| Item | Problem |
|---|---|
| `app/README.md` | Still the default `flutter create` template |
| `floor plans.pdf` (9.5 MB) | Large binary at repo root |
| `rough.json`, `sjt_floor8_preview.png`, `sjt_floor8_v2.png` | Scratch files at repo root |
| `app/demo_map.png`, `demo_routing.png`, `nav_demo.png`, `release_home.png` | Screenshots loose in the app root rather than `docs/assets/` |
| `app/_recovery/*.backup.json` | Manual backups; version control already does this |
| `app/test/features/**/.fuse_hidden*` | Orphaned filesystem artefacts from an interrupted operation, containing full copies of test files |
| `app/android/.kotlin/errors/*.log` | Build error logs not ignored |

None affects correctness; all affect how the repository reads to an external reviewer, which for this project is part of the deliverable.

### 2.6 `dart format` drift

`dart format --set-exit-if-changed .` reports roughly 23 files needing reformatting under current `dart_style`. Deliberately not fixed in a docs pass — run it, commit the mass diff on its own, *then* add the gate to CI so the gate never starts red.

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

## 5. Before any public release

- [x] `flutter analyze` and `flutter test` in CI on every push and PR
- [ ] `dart format --set-exit-if-changed` clean, then gated in CI (§2.6)
- [ ] Manual TalkBack pass on every screen
- [ ] Six SJT floors mapped, with an `entrance` node
- [ ] Graph validation running in the generator that is actually used (§2.1)
- [ ] Simulated navigation shipped **and visibly labelled as simulated**
- [ ] Repository root cleaned (§2.5); `app/README.md` written
- [ ] Performance claims measured or restated (§2.7)
- [ ] Firestore/Storage rules tested against the emulator suite before any deployment
