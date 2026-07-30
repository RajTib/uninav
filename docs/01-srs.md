# UniNav — Software Requirements Specification

> **Scope note.** This document states the full product vision *and* separates it from what the current MVP actually delivers (§5). The long-term goals in §2 remain the direction of travel; §5 is the contract for what exists today.

Related: [Architecture](02-architecture.md) · [Roadmap](14-roadmap.md) · [Navigation runtime](18-navigation-runtime.md) · [Known issues](15-known-issues.md) · [Feature backlog](13-feature-backlog.md)

---

## 1. Problem statement

Outdoor map providers stop at the building door. Inside large campuses, students lose real time finding rooms: numbering schemes are inconsistent (`SJT-513A`), floors are mislabelled, wings are disconnected, and no authoritative indoor map exists. Freshers, visitors and delivery staff are worst affected. Wheelchair users have no way to know whether an accessible route exists at all — which is a categorically different problem from a slow route, and the one this project treats as first-class.

UniNav is a **data-driven indoor navigation platform**. Venue knowledge lives entirely in data, never in code, so one binary serves a university, a mall, a hospital or an airport. Long-term it is a collaborative mapping platform where the community keeps maps alive after the original mappers graduate.

---

## 2. Long-term objectives

1. Search any room or POI and get a step-by-step shortest path, including automatic floor transitions, in under 2 s on a mid-range Android phone.
2. **Zero venue-specific code.** Onboarding a campus is uploading data.
3. A community contribution pipeline with moderation, versioning and rollback.
4. **Offline-first.** A downloaded campus is fully navigable with no network.
5. **Accessible routing as a first-class feature**, not a settings toggle bolted on.

---

## 3. User personas

| Persona | Needs | Served by MVP? |
|---|---|---|
| Fresher | Find a classroom fast, minimal learning curve | **Yes** |
| Regular student | Favourites, recents, quick repeat navigation | **Yes** |
| Wheelchair user | Step-free routes, honest "no accessible route" | **Yes** |
| Low-vision / screen-reader user | Semantic map, textual step list, high contrast | **Partly** — semantics and step list yes; TTS and high-contrast theme no |
| Visitor / parent / delivery | No-login browsing | **Yes** — there is no login at all |
| Contributor | Suggest fixes, add rooms, build reputation | **No** — report-a-problem queues locally only |
| Moderator | Review queue, approve/reject, rollback | **No** |
| Campus admin | Upload buildings, place nodes, analytics | **Partly** — via the developer toolchain, not a UI |

---

## 4. User stories

**Must — delivered in the MVP**

- As a student, I search "SJT 813" or an alias and see it on the floor map. ✅
- As a student, I pick a start and destination and get the shortest path with floor switches shown step by step. ✅
- As a student, I browse a floor plan by floor without searching. ✅
- As a wheelchair user, I choose step-free and get a lift-only path, or an explicit "no step-free route exists". ✅
- As any user, the app works fully offline. ✅ — data ships in the APK.
- As a user, I see the nearest washroom from a selected room. ✅

**Must — not yet delivered**

- As a student, I see an indicator moving along my route as I walk. ❌ — designed as a *simulation* first ([18-navigation-runtime.md](18-navigation-runtime.md)).

**Should — deferred**

- Sign-in and cross-device sync; long-press to contribute; a moderation queue.

---

## 5. MVP scope — the current contract

The MVP deliberately excludes indoor localisation. It proves that **accurate indoor mapping plus graph-based multi-floor routing** is achievable and useful. Positioning is the next problem, not this one.

### 5.1 In scope

| # | Capability | Where |
|---|---|---|
| MVP-1 | Accurate indoor floor mapping from real plans | [16-mapping-guide.md](16-mapping-guide.md) |
| MVP-2 | Graph-based building representation | [03](03-data-model.md), [04](04-routing-engine.md) |
| MVP-3 | Multi-floor routing via A* | [04-routing-engine.md](04-routing-engine.md) |
| MVP-4 | Clean Flutter UI | [08-ui-screens.md](08-ui-screens.md) |
| MVP-5 | Route visualisation on the floor plan | [05-map-representation.md](05-map-representation.md) |
| MVP-6 | **Simulated** navigation blob following the path | [18-navigation-runtime.md](18-navigation-runtime.md) — *not yet built* |
| MVP-7 | Architecture extensible to real positioning | [02 §8](02-architecture.md), [18](18-navigation-runtime.md) |

### 5.2 Explicitly out of scope

- **Real indoor positioning.** No QR, no BLE, no Wi-Fi RTT, no dead reckoning. Research directions only ([18 §5](18-navigation-runtime.md)).
- Backend, accounts, sync, community contributions, moderation, admin dashboard, multi-campus, AR, voice guidance.

### 5.3 The one statement that must not be misread

> **The navigation blob is simulated.** It interpolates along the computed route at a constant walking speed. It does **not** know where the user is. The app cannot determine the user's physical position by any means.
>
> The user selects their starting room; the app routes from there.

This is stated in the SRS, in the [architecture](02-architecture.md), in the [runtime design](18-navigation-runtime.md) and in the [roadmap](14-roadmap.md) — and it must be stated in the UI when the blob ships. A demo that lets a viewer believe the phone knows where it is has misled them.

**Why simulate at all?** Because it validates route calculation, floor transitions, instruction sequencing and rendering end to end, and it builds the entire consumer side of the position interface. When a real provider arrives, only that provider is new. Reasoning in full at [18 §4.1](18-navigation-runtime.md).

---

## 6. Functional requirements

| # | Requirement | Status |
|---|---|---|
| FR-1 | Search rooms, POIs and aliases; prefix + fuzzy; ranked | ✅ ([09](09-search.md)) |
| FR-2 | Shortest path across floors; stairs, lifts, ramps | ✅ ([04](04-routing-engine.md)) |
| FR-3 | Route modes: fastest / step-free / prefer-lift | ✅ |
| FR-4 | Floor rendering with pan, zoom, labels, route overlay, floor switcher | ✅ ([05](05-map-representation.md)) |
| FR-5 | Auth: anonymous browse; sign-in for contributions | ⏳ no auth exists; browsing needs none |
| FR-6 | Favourites and recent searches | ✅ device-local |
| FR-7 | Contribution CRUD with moderation | ⏳ ([06](06-community-mapping.md)) |
| FR-8 | Map versioning; clients re-download on change | ⏳ schema carries `version`; no sync |
| FR-9 | Campus selection, multiple campuses per install | ⏳ one campus per build via `--dart-define` |
| FR-10 | Per-campus announcements | ⏳ |
| FR-11 | Offline: cached campus searchable and routable | ✅ assets ship in the APK |
| FR-12 | Report a problem on any room or route | ✅ queues locally; upload is ⏳ |
| **FR-13** | **Nearest-of-many routing ("nearest washroom")** | ✅ |
| **FR-14** | **Deep links** — `/map?room=`, `/plan?dest=&from=` | ✅ |
| **FR-15** | **Simulated navigation along a computed route** | ⏳ next deliverable |

✅ shipped · ⏳ designed, not built

---

## 7. Non-functional requirements

| # | Requirement | Status |
|---|---|---|
| NFR-1 | Route computation < 200 ms for ≤10k nodes, on-device | **Unverified.** Current graphs are 17–41 nodes; no benchmark harness exists |
| NFR-2 | Cold start < 3 s; map interactive < 1 s with cached data | **Unmeasured** |
| NFR-3 | Backend reads per session amortised < 50 | Not applicable — zero backend |
| NFR-4 | Android 8+ / iOS 14+; usable on 2 GB RAM | Plausible; untested on low-end hardware |
| NFR-5 | WCAG 2.1 AA where applicable; TalkBack/VoiceOver | **Partial** — per-room semantics ✅, manual screen-reader pass ❌ ([10](10-accessibility.md)) |
| NFR-6 | Crash-free sessions > 99.5% | No telemetry; corrupt-data paths degrade rather than crash by construction |
| NFR-7 | All user content moderated before public visibility | Not applicable yet |
| NFR-8 | Clean Architecture; ≥80% domain coverage; CI static gates | Architecture ✅, CI analyze+test ✅, **coverage unmeasured** |

Marking these honestly matters more than marking them green. NFR-1 and NFR-8 in particular are *claims* until a benchmark and a coverage run exist — both are listed in [15-known-issues.md](15-known-issues.md).

---

## 8. Risks

| Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---|---|---|
| **Mapping effort exceeds one person** | **High** | **High** | Browser tracer cuts per-floor cost; Phase 2 seeks student mappers | **Active — this is the binding constraint** |
| No indoor positioning; user self-locates | Certain (MVP) | Medium | Explicit start selection; QR checkpoints researched later | Accepted and documented |
| Demo mistaken for real localisation | Medium | **High** | "Simulated" label mandatory in UI and in the demo script | Mitigated by policy ([18 §4.2](18-navigation-runtime.md)) |
| Two divergent bundle generators drift apart | Medium | Medium | Consolidate or retire one in Phase 1 | **Open** ([15](15-known-issues.md)) |
| Scope creep back toward Firebase/admin | Medium | High | Roadmap defers both explicitly | Mitigated |
| Solo-dev burnout | High | High | Phase gates; smallest useful increment | Ongoing |
| Floor-plan copyright | Low | Medium | Community-traced schematic maps, OSM-style | Watch |

---

## 9. Assumptions

- Users can identify their approximate start — the room they are in, or the entrance they used. **No live positioning in the MVP.**
- Campus layouts change slowly; eventual consistency of map data is acceptable.
- One building mapped genuinely well is more persuasive than five mapped thinly.
- Plan images are obtainable for the buildings to be mapped. Where they are not, the paced `.survey` workflow is the fallback ([16](16-mapping-guide.md)).

---

## 10. Technical constraints

- Flutter ≥ 3.22 / Dart ≥ 3.4, Material 3, Riverpod, GoRouter.
- **Four runtime dependencies:** `collection`, `flutter_riverpod`, `go_router`, `shared_preferences`. Deliberately minimal — every dependency is a maintenance obligation for a solo developer.
- No paid map SDKs; rendering is custom ([05](05-map-representation.md)).
- No backend in the MVP.

---

## 11. Success metrics

**MVP (Phase 1–2)** — the only metrics that currently apply:

- Six SJT floors mapped and routable.
- A multi-floor route computed and drawn correctly for any pair of mapped rooms.
- Step-free mode produces a genuinely different route, or an honest refusal.
- The demo runs end to end without a fallback recording.

**Post-scale** — meaningful only once the app is in real hands:

- ≥60% of new users complete one navigation in their first session.
- ≥90% of route requests succeed without "no path".
- ≥95% of teaching rooms mapped in the launch building.
