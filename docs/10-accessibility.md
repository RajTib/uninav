# UniNav — Accessibility

Accessibility here is **data + routing + UI**, not a settings toggle bolted on at the end. The claim is testable: remove the accessibility features and the data model, the routing engine and the renderer all change shape. That is what "first-class" means.

Related: [Routing engine](04-routing-engine.md) · [Map representation](05-map-representation.md) · [UI screens](08-ui-screens.md) · [SRS](01-srs.md)

---

## Status at a glance

| Area | Shipped | Not yet |
|---|---|---|
| Data | `accessible` on edges, `wheelchairAccessible` on rooms, ramp/lift node kinds | Accessible-washroom and accessible-entrance POI subtypes |
| Routing | Step-free mode, prefer-lift mode, honest "no route" | — |
| Preferences | Set once, applied to every route, persisted | — |
| Screen reader | Per-room canvas semantics, textual step list, labelled controls | A manual TalkBack/VoiceOver pass |
| Vision | System font scale, `ColorScheme`-driven theming, icons never alone | High-contrast theme, verified colourblind palette |
| Motion | — | Reduced-motion gating |
| Audio / haptics | — | TTS voice guidance, haptic turn cues |

---

## 1. Data layer

```dart
NavEdge.accessible   // false = steps, narrow door, staff-only lift…
NavEdge.kind         // stair | elevator | ramp | corridor | door | outdoor
NodeKind.ramp, NodeKind.elevator
Room.wheelchairAccessible
```

Accessibility is a property of the **map**, not of the app's presentation of it. That placement is what allows routing to reason about it at all.

The mapping guide asks surveyors to record two things explicitly, because both are invisible from a floor plan and both change real routing outcomes:

- **Which floors each staircase actually reaches.** Some stop at the 3rd.
- **Whether the lift is genuinely usable** — staff-only, card-access or permanently broken.

A lift recorded as usable when it is not produces a route a wheelchair user cannot take. That failure is worse than reporting no route at all, because it is discovered only after the journey.

**Not yet:** accessible-washroom and accessible-entrance as distinct POI subtypes; a generator warning when a floor has no accessible ingress.

---

## 2. Routing layer

### 2.1 Step-free mode is graph filtering, not a preference weight

```dart
RoutePrefs.accessible:
  excludeStairs = true            // stair edges removed from consideration
  excludeInaccessibleEdges = true // accessible:false edges removed
  elevatorPenaltyM = 5            // reduced from 15 — the lift is the only option
```

Excluded edges return `null` from `arcCost`, so the search never traverses them. The result is therefore the **true shortest step-free path**, or nothing.

This distinction matters more than it may appear. A *weighted* approach — making stairs very expensive — will still route a wheelchair user up a staircase when no alternative exists, because "very expensive" is still finite. Filtering makes that outcome structurally impossible.

### 2.2 Failure is reported honestly

When step-free routing fails, the router re-runs unconstrained to classify why ([04 §5](04-routing-engine.md)):

| Reason | Message |
|---|---|
| `noPathForConstraints` | "No step-free route exists between these rooms." |
| `disconnected` | "These rooms are not connected on the map yet." |
| `nodeMissing` | "One of these rooms is not routable yet." |

*"No step-free route exists"* is the single most important sentence in the app for a wheelchair user. It is actionable — ask for help, use another entrance, report the gap — where a generic error is not. Because `PlannerState` is sealed, the compiler will not let a build collapse these three into one.

### 2.3 Prefer-lift, for people who *can* use stairs

`RoutePrefs.preferLift` (stairs at 3×) serves low stamina, injury or luggage. Modelling this as a distinct mode rather than a slider keeps the *hard* constraint and the *soft* preference from being confused — they are different needs with different failure semantics.

### 2.4 Set once, applies everywhere

`AppPrefs.defaultRouteMode` persists and is read by `RoutePlannerScreen.initState`. A wheelchair user sets step-free once, in Settings, and every route respects it. Per-route override remains available.

The accessibility promise is *set once, applies everywhere* — not *choose again every time*.

---

## 3. UI layer

### 3.1 The step list is the primary accessible surface

Every route is available as a textual step list with a per-kind icon: `start`, `walk`, `turnLeft`, `turnRight`, `floorChange`, `arrive`. Floor changes name the destination floor — *"Take the lift to 8th Floor"*.

**A map is never the only representation of a route.** The step list is not a fallback for when the map fails; it is a first-class parallel representation, and it is the one that works with a screen reader, at any font size, and read aloud by the system.

### 3.2 Canvas semantics

`FloorPainter.semanticsBuilder` emits one `CustomPainterSemantics` node **per room**:

```dart
SemanticsProperties(
  label: '${room.name}, ${room.type.name}',
  button: true,
  selected: room.id == selectedRoomId,
  onTap: () => onRoomTap(room),   // same path a sighted tap uses
)
```

A custom-painted canvas is opaque to a screen reader by default. Before this, the map exposed only a single summary label and every room below it was invisible. Now TalkBack and VoiceOver can traverse rooms, hear their type, and activate one by double-tap — landing on **identical app state** to a sighted tap, because both call the same `_selectRoom`.

Asserted by widget tests: traversal, selection state, and that activating a room's semantics action selects it.

### 3.3 Controls

- Icon buttons carry `tooltip`, which Flutter exposes as a semantics label — no icon-only control is unlabelled.
- The home search launcher is `Semantics(button: true, label: 'Search rooms, labs and offices')`, not a decorative box.
- The map exposes a summary label — floor name and room count — plus a pointer to the room list and search.
- Settings radio subtitles state consequences, not just names.

### 3.4 Colour and contrast

Every colour derives from the Material 3 `ColorScheme` via `MapStyle.fromScheme`. Room labels are drawn twice — a 3.5 px surface-coloured halo, then the fill — so text stays readable on any room fill in either theme.

Status is never colour alone: route endpoints differ in colour **and** size, transition badges have a distinct shape, and the wheelchair icon carries a tooltip.

**Not yet:** an explicit high-contrast theme, and formal verification that the room-type palette is colourblind-safe. Because styling is scheme-driven, both are theme additions rather than painter changes.

---

## 4. Not implemented

| Gap | Why it matters | Notes |
|---|---|---|
| **Manual TalkBack / VoiceOver pass** | Automated semantics tests prove nodes *exist*, not that traversal is *usable* | The highest-value remaining a11y task. Cheap: one device, thirty minutes |
| **Reduced-motion gating** | The route dash animation runs unconditionally; it should respect `MediaQuery.disableAnimations` | Small fix, real impact for vestibular sensitivity |
| **Voice guidance (TTS)** | Eyes-free navigation with the screen off | Blocked on the navigation engine ([18](18-navigation-runtime.md)) — there is nothing to announce until progress is tracked |
| **Haptic cues** on turns and floor changes | Same | Same blocker |
| **High-contrast theme** | Low vision | Theme addition |
| **Colourblind-safe palette verification** | 8% of men | Okabe–Ito-derived palette is the intended reference |
| **Font-scale audit to 2.0** | Text must not truncate at large sizes | Untested |

---

## 5. Verification

**Automated today**

- Widget tests assert per-room semantics on the map canvas, including traversal and activation.
- Routing tests assert step-free mode excludes stairs and inaccessible edges, honours constraints across floors, and reports `noPathForConstraints` rather than silently routing via stairs.

**Not automated**

- Screen-reader traversal quality — order, verbosity, whether it is genuinely usable.
- Font scaling to 2.0 without truncation.
- Contrast ratios against WCAG 2.1 AA.

**The standing success criterion:** complete a full navigation eyes-free — search a room, plan a route, follow the steps — using only a screen reader. That has not yet been attempted, and until it has, the WCAG claim in [01-srs.md](01-srs.md) NFR-5 is marked *partial* rather than met.
