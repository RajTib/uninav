# UniNav — Software Requirements Specification (v1.0)

## 1. Problem Statement

Outdoor map providers (Google Maps, OSM) stop at the building door. Inside large campuses, students waste time finding rooms: numbering schemes are inconsistent ("SJT-513A"), floors are mislabeled, wings are disconnected, and no authoritative indoor map exists. Freshers, visitors, and delivery staff are worst affected; wheelchair users have no way to know whether an accessible route exists at all.

UniNav is a data-driven indoor navigation platform. Venue-specific knowledge lives entirely in data (JSON/Firestore), never in code, so the same app serves a university, mall, hospital, or airport. Long-term, it is a collaborative mapping platform (OSM-style) where the community keeps maps alive after the original mappers graduate.

## 2. Objectives

1. Search any room/POI and get a step-by-step shortest path, including automatic floor transitions, in < 2 s on a mid-range Android phone.
2. Zero venue-specific code: onboarding a new campus = uploading data.
3. Community contribution pipeline with moderation, versioning, and rollback.
4. Offline-first: a downloaded campus is fully navigable without network.
5. Accessible routing (lift/ramp-only) as a first-class feature, not an afterthought.

## 3. User Personas

| Persona | Needs |
|---|---|
| Fresher | Find classroom fast, minimal learning curve |
| Regular student | Favorites, recents, timetable-adjacent use |
| Wheelchair user / low vision | Accessible routes, screen-reader UX, high contrast |
| Visitor/parent/delivery | No-login browsing of public campuses |
| Contributor | Suggest fixes, add rooms, track reputation |
| Moderator | Review queue, approve/reject, rollback |
| Campus admin | Upload buildings/floors, place nodes, analytics |

## 4. User Stories (prioritized)

**Must (MVP)**
- As a student, I search "SJT513" (or an alias) and see it on the floor map.
- As a student, I pick start + destination and get the shortest path with floor switches shown step by step.
- As a student, I browse a floor plan by building/floor without searching.
- As a wheelchair user, I toggle "accessible route" and get a lift/ramp-only path or an explicit "no accessible route" message.
- As any user, previously loaded campus data works fully offline.

**Should**
- As a user, I sign in (Google) to sync favorites/recents across devices.
- As a contributor, I long-press the map to suggest "room X is here" with an optional photo.
- As a moderator, I see a pending-edits queue and approve/reject with a reason.

**Could**
- As a user, I see nearest washroom/water cooler/printer from my selected location.
- As an admin, I import/export a building as one JSON file.

## 5. Use Cases (representative)

**UC-01 Navigate to room.** Precondition: campus data cached. Main flow: search → select destination → select start (room, or "main entrance" default) → engine computes path → step list + per-floor polyline rendered → user pages through floors. Extensions: no path found (disconnected graph) → error + "report a problem"; accessible mode → filtered graph; same-floor destination → single-floor route.

**UC-02 Contribute an edit.** Signed-in user long-presses map → chooses type (add/move/rename room, report issue) → submits with note/photo → Contribution doc created (`pending`) → moderator approves → change applied and map version bumped (Cloud Function later; moderator client pre-Functions) → contributor notified, reputation +N.

**UC-03 Admin onboards a building.** Admin uploads floor-plan image → calibrates coordinate system (scale/origin) → places nodes visually, tags rooms, connects edges → validates graph connectivity → publishes as new MapVersion.

## 6. Functional Requirements

- FR-1 Search over rooms, POIs, buildings, aliases, departments; prefix + fuzzy; ranked.
- FR-2 Shortest-path routing across floors and connected buildings; stairs, lifts, ramps, exits.
- FR-3 Route preferences: fastest | accessible (no stairs) | prefer-lift.
- FR-4 Floor-plan rendering with pan/zoom, room labels, route overlay, floor switcher.
- FR-5 Auth: anonymous browse; Google/email sign-in for personalization and contributions.
- FR-6 Favorites, recent searches, saved locations (synced when signed in, local otherwise).
- FR-7 Contribution CRUD with moderation states pending → approved | rejected; audit trail retained.
- FR-8 Map versioning per building; clients re-download only when version changes.
- FR-9 Campus selection; multiple campuses per install.
- FR-10 Announcements per campus (read-only in app).
- FR-11 Offline mode: cached campus fully searchable and routable; staleness indicator.
- FR-12 Feedback / report-a-problem on any room or route.

## 7. Non-Functional Requirements

- NFR-1 Route computation < 200 ms for graphs ≤ 10k nodes (on-device).
- NFR-2 Cold start < 3 s; map screen interactive < 1 s with cached data.
- NFR-3 Firestore reads per active session amortized < 50 (versioned bundle caching).
- NFR-4 Android 8+ / iOS 14+; usable on 2 GB RAM devices.
- NFR-5 WCAG 2.1 AA where applicable; full TalkBack/VoiceOver support.
- NFR-6 Crash-free sessions > 99.5%.
- NFR-7 All user content moderated before public visibility.
- NFR-8 Clean Architecture; ≥ 80% test coverage on domain layer; CI static-analysis gates.

## 8. Future Scope

AR wayfinding, BLE beacon / Wi-Fi RTT positioning, QR checkpoint localization, timetable integration, live crowd density, event mode, multi-language, white-label deployments (see 13-feature-backlog.md).

## 9. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Mapping effort too large (cold-start content) | High | High | Seed one building end-to-end; admin tooling early; community pipeline |
| No indoor positioning → user must self-locate start | Certain (MVP) | Medium | "Start from room/entrance" UX; QR checkpoints later |
| Firestore cost explosion from naive reads | Medium | High | Versioned JSON bundles in Storage, not per-room reads |
| Moderation bottleneck / spam | Medium | Medium | Reputation, rate limits, trusted auto-approve |
| Solo-dev burnout / scope creep | High | High | Strict milestone gates (14-roadmap.md) |
| Floor-plan copyright (official plans) | Low | Medium | Community-drawn schematic maps, like OSM |

## 10. Assumptions

- Users can identify their approximate start (room they're in / entrance used). No live indoor positioning in MVP.
- Campus layouts change slowly; eventual consistency of map data is acceptable.
- Free Firebase tier suffices for first ~5k MAU with the caching strategy in 11-performance.md.
- Moderators exist per campus (initially: the developer).

## 11. Technical Constraints

- Flutter stable, Material 3, Riverpod, GoRouter, Firebase (Auth, Firestore, Storage; Functions later — moderator-client-driven approval until then).
- No paid map SDKs; rendering is custom (see 05-map-representation.md).
- Solo developer; every subsystem must be maintainable by one person.

## 12. Success Metrics

- Activation: ≥ 60% of new users complete one navigation in first session.
- Task success: ≥ 90% of routes computed without "no path" errors.
- Retention: ≥ 30% week-4 retention among students during term.
- Content: ≥ 95% of teaching rooms mapped in launch building; median review time < 48 h.
- Cost: Firestore reads/user/day < 20 after caching.
