# UniNav — Data Model: Firestore + Storage (v1.0)

## 0. The key split: metadata vs. bundles

Firestore is priced per document read and capped at 1 MiB/doc. Map geometry read-per-room would be ruinously expensive and slow. So:

- **Firestore** = small metadata docs, the contribution/moderation pipeline, user data. Things that need queries, security rules, and realtime updates.
- **Firebase Storage** = published, immutable **building bundles** (`bundles/{buildingId}/{version}.json`): floors, rooms, nodes, edges, POIs in one gzip-able blob. Immutable per version → cacheable forever, trivially rollback-able.

A client syncs by reading N building metadata docs (N = buildings in campus, cheap), comparing `publishedVersion` to its cache, and downloading only changed bundles.

## 1. Collections

```
campuses/{campusId}
buildings/{buildingId}                    # top-level, campusId field (collection-group friendly)
buildings/{buildingId}/versions/{version} # MapVersion history
contributions/{contributionId}
users/{uid}
users/{uid}/saved/{savedId}               # favorites & saved locations
users/{uid}/routeHistory/{entryId}
feedback/{feedbackId}
announcements/{announcementId}            # campusId field
auditLogs/{logId}
roles/{uid}                               # separate from users: writable only by admin
```

### campuses/{campusId}
```jsonc
{
  "name": "VIT Vellore", "slug": "vit-vellore",
  "type": "university",            // university | mall | hospital | airport | office
  "location": {"lat": 12.97, "lng": 79.16}, "address": "...",
  "buildingCount": 14, "status": "published",   // draft | published | archived
  "coverImageUrl": "...", "searchIndexVersion": 7,
  "createdAt": ts, "updatedAt": ts
}
```
Justification: the app's campus picker needs exactly one read per campus. `searchIndexVersion` lets clients refresh the campus-wide search index (also a Storage blob) independently of bundles.

### buildings/{buildingId}
```jsonc
{
  "campusId": "vit-vellore",
  "name": "Silver Jubilee Tower", "code": "SJT", "aliases": ["SJT", "Tech Tower"],
  "floorsSummary": [{"id": "f0", "name": "Ground", "level": 0}, ...],
  "publishedVersion": 12,                     // -> Storage bundle path
  "bundlePath": "bundles/SJT/12.json", "bundleBytes": 48211, "bundleHash": "sha256:...",
  "entranceNodeIds": ["n_main_gate"],         // default route starts
  "connectedBuildingIds": ["TT"],             // inter-building edges exist
  "status": "published", "updatedAt": ts
}
```
Justification: everything the client needs to decide "do I re-download?" in one read. Floors/rooms/nodes are NOT subcollections — they live in the bundle. Top-level (not under campus) so a building can be queried/moved independently and collection-group queries stay simple.

### buildings/{buildingId}/versions/{version}  (MapVersion)
```jsonc
{
  "version": 12, "bundlePath": "bundles/SJT/12.json", "bundleHash": "...",
  "changeSummary": "Added 5th floor west wing",
  "sourceContributionIds": ["c123", "c124"],
  "createdBy": uid, "createdAt": ts,
  "stats": {"rooms": 412, "nodes": 1730, "edges": 2101}
}
```
Justification: rollback = set `publishedVersion: 11` on the parent. Full lineage from version → contributions → contributors (audit).

### Bundle JSON (Storage, not Firestore) — the canonical map format
```jsonc
{
  "schemaVersion": 1, "buildingId": "SJT", "version": 12,
  "floors": [{"id": "f2", "level": 2, "name": "2nd Floor",
              "widthM": 90.5, "heightM": 60.0, "planImagePath": "plans/SJT/f2.webp"}],
  "rooms":  [{"id": "r_sjt513", "floorId": "f5", "name": "SJT 513",
              "aliases": ["513"], "type": "classroom", "polygon": [[x,y],...],
              "labelPoint": [x,y], "nodeId": "n_513", "tags": {"capacity": "70"},
              "wheelchairAccessible": true}],
  "pois":   [{"id": "p_wc_f2_1", "floorId": "f2", "type": "washroom",
              "point": [x,y], "nodeId": "n_wc21", "gender": "any"}],
  "nodes":  [{"id": "n_513", "floorId": "f5", "x": 41.2, "y": 18.7,
              "kind": "room"}],   // room|corridor|junction|stair|elevator|ramp|entrance|exit
  "edges":  [{"a": "n_513", "b": "n_c51", "kind": "corridor",
              "lengthM": 6.2, "accessible": true, "bidirectional": true}]
}
```
Coordinates are metres in a per-floor local frame (origin top-left). Floor transitions are ordinary edges between nodes on different floors with `kind: "stair" | "elevator" | "ramp"`.

### contributions/{contributionId}
```jsonc
{
  "campusId": "vit-vellore", "buildingId": "SJT", "floorId": "f5",
  "type": "addRoom",   // addRoom|moveRoom|renameRoom|addEdge|addPoi|reportIssue|photo
  "payload": { /* type-specific proposed data, same shapes as bundle */ },
  "note": "Room was renamed last sem", "photoPaths": ["contrib/c123/1.jpg"],
  "authorId": uid, "status": "pending",  // pending|approved|rejected|superseded
  "review": {"moderatorId": uid, "reason": "...", "reviewedAt": ts},
  "appliedInVersion": 13, "createdAt": ts
}
```
Justification: one collection (not per-building subcollections) so a moderator's queue is a single query: `where campusId == X && status == "pending" orderBy createdAt`. Payload mirrors bundle shapes so approval is a mechanical merge.

### users/{uid} and roles/{uid}
```jsonc
// users/{uid} — self-writable profile
{ "displayName": "...", "photoUrl": "...", "homeCampusId": "vit-vellore",
  "prefs": {"accessibleRoutes": false, "preferElevator": false, "theme": "system"},
  "reputation": 0, "contributionCount": 0, "createdAt": ts }

// roles/{uid} — ONLY admin-writable (separate doc, simple rules)
{ "role": "moderator", "campusIds": ["vit-vellore"] }   // admin | moderator
```
Justification: privilege escalation is impossible via profile writes because role data lives in a collection users can't write. `reputation` is written only by the moderation flow.

**users/{uid}/saved** `{type: "favorite"|"savedLocation", roomId, buildingId, label, createdAt}` — subcollection: unbounded, user-owned, never queried globally.
**users/{uid}/routeHistory** `{fromRoomId, toRoomId, buildingIds, at}` — capped client-side (keep last 50); fuels "recents" and personal analytics.

### feedback, announcements, auditLogs
- `feedback`: `{campusId, target: {kind: "room"|"route"|"app", ids}, text, authorId, status, createdAt}` — lightweight, no moderation UI needed in MVP.
- `announcements`: `{campusId, title, body, severity, activeFrom, activeTo, createdBy}` — client queries active ones per campus; 1 read per app open (cacheable).
- `auditLogs`: append-only `{actorId, action, targetPath, before?, after?, at}` written on every moderation/publish action. Never read by the app; exists for accountability and abuse forensics.

## 2. Read-cost budget (typical session, warm cache)

| Action | Reads |
|---|---|
| Open app (campus doc cached) | 0–1 |
| Building version check (14 buildings) | 14 (or 1 if a campus-level `bundlesUpdatedAt` short-circuits) |
| Search + route + render | 0 (all local) |
| Announcements | 1 |

An optional `campuses/{id}.bundlesUpdatedAt` timestamp lets clients skip the per-building check entirely when nothing changed — added when campuses grow past ~20 buildings.

## 3. What was deliberately NOT normalized

- Rooms/nodes/edges into Firestore docs: query-ability isn't needed at that granularity; the graph is always consumed whole per building.
- Professor/department directory: MVP embeds `tags` on rooms; a real `directory` collection is future scope (Phase 13) because it has different ownership and change cadence than geometry.
