# UniNav — Accessibility (v1.0)

Accessibility is data + routing + UI, not a settings toggle bolted on.

## Data layer
- Edges carry `accessible: bool`; nodes carry kind (`ramp`, `elevator`); rooms carry `wheelchairAccessible`. Contributors are prompted for these fields; the admin editor warns when a floor has no accessible ingress.
- POI types include accessible washrooms and accessible entrances.

## Routing layer (see 04)
- **Wheelchair mode:** stairs and `accessible:false` edges excluded from the graph — honest "no accessible route exists" instead of silent stairs. Result is the *shortest accessible path*, not a degraded heuristic.
- **Prefer elevator / prefer ramp:** weight multipliers for users with low stamina who *can* use stairs.
- Preferences persist (`prefs.accessibleRoutes` default), applied to every route, overridable per route.

## UI layer
- Full TalkBack/VoiceOver: map rooms exposed as semantic nodes; routes always available as a textual step list (the step list is the primary a11y surface — a map is never the only representation).
- **Voice guidance:** TTS reads steps on advance ("Turn left, then take the lift to Floor 3"); works with screen off.
- **Vision:** respects system font scale to 2.0; high-contrast theme; focus order audited per screen; icons + text, never icon-only controls.
- **Color blindness:** room-type palette chosen colorblind-safe (Okabe–Ito derived); route line uses color + dash pattern + width; status uses icons + labels, never color alone.
- Haptic cues on turns and floor changes.
- Reduced motion: all decorative animations gated on `MediaQuery.disableAnimations`.

## Verification
- CI widget tests assert semantics on every screen; manual TalkBack pass per milestone; a11y checklist in PR template. Success metric: complete a full navigation eyes-free.
