# UniNav — Data Model

> **Status — read this first.**
> **§1–§4 (campus file, bundle schema, codec) are shipped and authoritative.** They describe the JSON the app parses today, in `app/lib/data/dtos/building_bundle_dto.dart`.
> **§5–§7 (Firestore collections, moderation, cost budget) are Planned.** No Firebase code exists in the app yet; the security rules in `app/firebase/` are written but undeployed and untested.

Related: [Architecture](02-architecture.md) · [Routing engine](04-routing-engine.md) · [Map representation](05-map-representation.md) · [Mapping guide](16-mapping-guide.md) · [Security](12-security.md)

---

## 1. The central split: metadata vs. bundles

Map geometry read one-room-at-a-time from a document database would be ruinously expensive and slow. So the data model splits along a single line:

- **Small, queryable, mutable metadata** → documents (Firestore, when it lands). Things needing queries, security rules and realtime updates.
- **Large, immutable geometry** → **building bundles**, one JSON blob per building per version. Cacheable forever, trivially rollback-able, downloadable in one request.

Today both live as Flutter assets:

```
app/assets/campuses/
  vit-vellore/
    campus.json          # the metadata half
    bundle_SJT.json      # the geometry half
  demo/
    campus.json
    bundle_main.json
  maps/sjt/              # authoring sources, not shipped data
    8th floor.png        # plan image
    floor_8.json         # traced output from tool/tracer
```

`AssetBuildingRepository` resolves paths by convention: `assets/campuses/{campusId}/campus.json` and `assets/campuses/{campusId}/bundle_{buildingId}.json`. `pubspec.yaml` declares whole directories as assets so a newly generated bundle is picked up without editing the manifest.

---

## 2. `campus.json` — the venue index

```jsonc
{
  "id": "vit-vellore",
  "name": "VIT Vellore",
  "type": "university",          // university | mall | hospital | airport | office | other
  "buildings": [
    {
      "id": "SJT",
      "name": "Silver Jubilee Tower",
      "code": "SJT",                            // optional short code
      "aliases": ["Silver Jubilee", "Tower"],
      "status": "inProgress",                   // mapped | inProgress | planned
      "note": "First building being mapped"     // optional
    }
  ]
}
```

### 2.1 Why unmapped buildings are listed

`BuildingStatus.planned` buildings appear in the campus file and on the home screen. This is deliberate and not a placeholder.

A user who cannot find their block needs to know whether the block is *missing from the map* or whether *the app is broken*. Listing it, greyed out, with a "Help map" action, answers that question and turns the gap into a contribution prompt. An empty list answers nothing.

`BuildingSummary.isNavigable` is `status != planned`, so `inProgress` buildings are openable but shown with a caveat ("Mapping in progress — some areas may be missing").

**Validation:** the repository rejects a `campus.json` whose `id` field disagrees with the directory it was loaded from. That mismatch used to be silently possible and produced confusing "building not found" errors downstream.

**Unknown `status` values fall back to `planned`** — showing a building the app cannot route through is worse than hiding it.

---

## 3. Bundle JSON — the canonical map format

`schemaVersion: 1`. The parser **rejects** any other value with an explicit message; it does not attempt best-effort parsing of a schema it doesn't know.

```jsonc
{
  "schemaVersion": 1,
  "buildingId": "SJT",
  "buildingName": "Silver Jubilee Tower",
  "version": 1,                       // bundle content version, bumped on republish

  "floors": [{
    "id": "f8",
    "level": 8,                       // 0 = ground, negative = basement
    "name": "8th Floor",
    "widthM": 61.05,
    "heightM": 62.63,
    "planImagePath": "8th floor.png", // optional raster underlay (not yet rendered)
    "sourcePxPerMetre": 13.33,        // optional: plan-image px per metre
    "corridorWidthM": 2.5,            // default 2.5
    "corridors": [                    // optional; polylines in metres, DRAWING ONLY
      [[12.4, 30.1], [40.2, 30.1], [40.2, 55.0]]
    ]
  }],

  "rooms": [{
    "id": "SJT813",
    "floorId": "f8",
    "name": "SJT 813",
    "type": "classroom",              // see RoomType below
    "aliases": ["813"],
    "polygon": [[x, y], ...],         // may be empty → renders as a pin
    "labelPoint": [x, y],             // required
    "nodeId": "n_f8_SJT813_d",        // optional; null = not routable yet
    "tags": {"dept": "Physics"},
    "wheelchairAccessible": true
  }],

  "pois": [{
    "id": "poi_wc_m_f8",
    "floorId": "f8",
    "type": "washroom",               // see PoiType below
    "point": [x, y],
    "name": "Men's Washroom",         // optional
    "nodeId": "n_f8_wc_m",            // optional
    "tags": {"gender": "male"}
  }],

  "nodes": [{
    "id": "n_f8_SJT813_d",
    "floorId": "f8",
    "x": 41.2, "y": 18.7,             // note: flat x/y, NOT a [x,y] pair
    "kind": "room"
  }],

  "edges": [{
    "a": "n_f8_SJT813_d",
    "b": "n_f8_c1",
    "kind": "corridor",
    "lengthM": 6.2,
    "accessible": true,
    "bidirectional": true
  }]
}
```

### 3.1 Coordinate frame

Metres, per-floor local frame, **origin top-left, y grows down** — matching screen convention so the renderer converts with a single scalar multiply and no axis flip.

All floors of one building must share a frame, or vertical connectors will not line up and the A* heuristic becomes unsafe ([04-routing-engine.md §3.2](04-routing-engine.md)). Across *buildings*, frames are independent by default.

### 3.2 Enumerations

| Field | Values |
|---|---|
| `RoomType` | `classroom` `lab` `office` `auditorium` `library` `washroom` `cafeteria` `utility` `junction` `other` |
| `PoiType` | `washroom` `waterCooler` `printer` `atm` `vending` `firstAid` `entrance` `exit` `other` |
| `NodeKind` | `room` `corridor` `junction` `stair` `elevator` `ramp` `entrance` `exit` |
| `EdgeKind` | `corridor` `door` `stair` `elevator` `ramp` `outdoor` |

`RoomType.junction` deserves a note: a lift or stair lobby is a walkable space in its own right — people stand and pass through it — so it is a bounded room, not a corridor endpoint. It is filled in the corridor colour so it visually reads as an extension of the walkable floor.

### 3.3 The three fields that carry the most design weight

**`corridors` — drawing truth, separate from routing truth.**
Corridors are traced polylines used *only* for rendering. Routing ignores them completely and uses the graph.

This separation was learned the hard way. A graph edge asserts "A connects to B, 25 paces apart" — it says nothing about the corridor bending twice on the way. Drawn literally, a straight edge cuts diagonally through walls. Tracing the visible corridor shape separately means the map *looks* right while the graph stays *metrically* right. How a corridor looks and how far you walk down it are different facts, and conflating them corrupts both.

**`corridorWidthM` — only the centreline is traced.**
Stroking a centreline at the real corridor width paints a walkable area. That is half the clicks of outlining both walls, and corner joins come out correct automatically from `StrokeJoin.round`.

**`sourcePxPerMetre` — the authoring back-channel.**
Records how many pixels of the *original plan image* make one metre. It exists so the debug grid can be labelled in the same units the surveyor edits (plan pixels), letting a mispositioned room be read straight off the screen — "that box starts at 380, should be 300" — instead of converting units by hand. Null for bundles not derived from a plan image.

### 3.4 Optional and derived fields

- `polygon` may be empty. A freshly surveyed floor is mostly label-only rooms, drawn as map pins. That is a normal intermediate state, not an error.
- `nodeId` may be null. The room exists, is searchable and is drawn — it just isn't routable yet. Search marks these `routable: false` and the UI disables the Directions button rather than failing on tap.
- `labelPoint` is the room's *centre*; `nodeId` points at its *doorway*. These are genuinely different places and merging them would put route endpoints inside walls.

---

## 4. The codec: `BuildingBundleDto`

Hand-written, not code-generated. The reasoning is worth stating because "just use `json_serializable`" is the obvious objection.

The bundle schema is the platform's public contract. Community and admin tooling need **specific, human-readable** parse errors — `"polygon" must be [x, y] numbers, got: [1]` beats a generated `type 'int' is not a subtype of type 'num'` by a wide margin when the person reading it is a student debugging their own survey file.

### 4.1 Parsing rules

| Situation | Behaviour | Why |
|---|---|---|
| Wrong `schemaVersion` | `FormatException` with both versions named | Never best-effort a schema you don't know |
| Missing required string/int/double | `FormatException` naming the key and the object | Point at the problem, don't guess |
| Malformed coordinate | `FormatException` via one validated `_coord` path | Otherwise `RangeError`/`TypeError` — `Error`s, not `Exception`s — escape the repository's `on FormatException` and crash the app |
| Unknown enum value | Falls back (`RoomType.other`, `NodeKind.corridor`, …) | An old client must tolerate data written by newer tooling |
| Non-string `tags` value | Coerced with `'${e.value}'` | Numbers and bools are common in hand-authored data; rejecting a whole building over one is disproportionate |
| Missing optional list | Empty list | `polygon`, `aliases`, `corridors`, `tags` are all legitimately absent |

`toJson` is the exact inverse and is round-trip tested (`test/data/building_bundle_dto_test.dart`). It is not decoration — both bundle generators emit through it, so the app and the tooling can never drift apart on format.

---

## 5. Current data inventory (as of this audit)

Documented because roadmap claims should be checkable against the repository.

| Asset | Contents |
|---|---|
| `vit-vellore/campus.json` | 10 buildings: SJT (`inProgress`), 9 `planned` |
| `vit-vellore/bundle_SJT.json` | ⚠️ **Currently empty** — `buildingId: "UNKNOWN"`, zero floors. Overwritten by a bad regeneration run; see [15 §0](15-known-issues.md). Its last good contents were floors 6 and 8: 37 rooms, 2 POIs, 41 nodes, 42 edges (40 corridor, 1 stair, 1 elevator) |
| `demo/campus.json` | 2 buildings: `main` (`mapped`), `annex` (`planned`, exists to exercise the unmapped-building UI) |
| `demo/bundle_main.json` | Floors 0 and 1. 5 rooms, 1 POI, 17 nodes, 17 edges |
| `maps/sjt/floor_5.json`, `floor_6.json`, `floor_8.json` | Traced sources — 23, 22 and 19 nodes |
| `maps/sjt/floor_0…4.json`, `floor_7.json` | **Empty files (0 bytes).** Placeholders; not yet traced |
| `maps/sjt/*.png`, `*.jpeg` | Plan images for floors 1–6 and 8. **Gitignored by policy** — institutional drawings must not be redistributed; only derived coordinates are committed |

Two consequences worth flagging:

- **The SJT bundle contains no `entrance` node.** Routes therefore have no natural default start, and the reachability check that `survey_to_bundle` performs is not run by the pipeline that actually produced this bundle. See [15-known-issues.md](15-known-issues.md).
- **Floor 7 is missing between the two mapped floors,** so the single vertical connector spans levels 6→8 with `floorsCrossed = 2`. Routing is correct; the instruction reads "take the lift to 8th Floor" and skips a floor that exists physically.

---

## 6. Planned: Firestore collections

> **Not implemented.** No Firebase dependency is in `pubspec.yaml`. This is the target design for the remote tier; rules for it already live in `app/firebase/` ([12-security.md](12-security.md)).

```
campuses/{campusId}
buildings/{buildingId}                    # top-level, with a campusId field
buildings/{buildingId}/versions/{version} # MapVersion history
contributions/{contributionId}
users/{uid}
users/{uid}/saved/{savedId}
users/{uid}/routeHistory/{entryId}
feedback/{feedbackId}
announcements/{announcementId}
auditLogs/{logId}
roles/{uid}                               # separate from users: admin-writable only
```

**`buildings/{buildingId}`** carries everything a client needs to answer "do I re-download?" in one read: `publishedVersion`, `bundlePath`, `bundleBytes`, `bundleHash`, `floorsSummary`, `entranceNodeIds`, `connectedBuildingIds`. Floors, rooms and nodes are **not** subcollections — they live in the bundle.

**`buildings/{id}/versions/{n}`** records `bundlePath`, `bundleHash`, `changeSummary`, `sourceContributionIds`, `createdBy`, `stats`. Rollback is a pointer flip of `publishedVersion`; old bundles are never deleted. Full lineage runs version → contributions → contributors.

**`roles/{uid}` is a separate collection from `users/{uid}`** so privilege escalation through a profile write is structurally impossible, not merely rule-forbidden.

**`contributions`** is one flat collection rather than per-building subcollections, so a moderator's queue is a single query: `where campusId == X && status == 'pending' orderBy createdAt`. Payloads mirror bundle shapes so approval is a mechanical merge ([06-community-mapping.md](06-community-mapping.md)).

---

## 7. Planned: read-cost budget

| Action | Reads |
|---|---|
| Open app (campus doc cached) | 0–1 |
| Version check, 14 buildings | 14 — or 1 with a campus-level `bundlesUpdatedAt` short-circuit |
| Search + route + render | **0** — entirely local |
| Announcements | 1 |

The `bundlesUpdatedAt` short-circuit is deliberately deferred until a campus passes ~20 buildings. Adding it earlier is optimisation without measurement.

---

## 8. What was deliberately not normalised

**Rooms, nodes and edges as documents.** Query-ability at that granularity is not needed — the graph is always consumed whole, per building. Normalising would multiply read cost by three orders of magnitude and destroy the offline story, in exchange for queries nothing performs.

**A professor/department directory.** MVP embeds `tags` on rooms (`{"person": "Dr. Rao"}`), which the search index already tokenises. A real directory collection has different ownership and a different change cadence from geometry, so coupling them into one bundle version would mean republishing the map every time a cabin allocation changes.
