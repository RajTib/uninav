# UniNav — Flutter UI Screens (v1.0)

Design language: Material 3, dynamic color (fallback seed indigo), 8-dp grid, `NavigationBar` with 3 tabs (Explore, Search, Profile). All screens: Semantics-labeled, 48-dp min targets, text scales to 2.0 without truncation, reduced-motion respected.

| Screen | Purpose | Key widgets | Navigation (GoRouter) | State (Riverpod) | Motion | A11y notes |
|---|---|---|---|---|---|---|
| Splash | Bootstrap: load prefs, warm cache, decide first route | Logo, `AnimatedOpacity` | `/` → redirect `/onboarding` \| `/home` | `appBootstrapProvider (FutureProvider)` | Logo fade ≤ 800 ms, skipped on reduced-motion | Announce "loading" |
| Onboarding | 3 pages: value prop, campus pick, optional sign-in | `PageView`, campus cards, skip | `/onboarding`; completion guard | `onboardingControllerProvider` | Parallax page slide | Fully skippable; no info locked behind it |
| Auth | Google / email sign-in; anonymous continue | `SignInButton`s, form | `/auth` (modal-pushed from actions needing identity, never a wall) | `authControllerProvider (StreamProvider auth state)` | Hero on logo | Error text linked to fields via semantics |
| Home / Explore | Campus overview: buildings grid, announcements, favorites row, "navigate again" | `SliverAppBar.medium`, cards, chips | `/home`; taps → `/building/:id`, `/search` | `campusProvider`, `favoritesProvider`, `announcementsProvider` | Card `Hero` into map | Announcement banners are live regions |
| Search | Unified search (rooms/POIs/buildings); recents, favorites, filters | `SearchAnchor` M3, result list w/ type icons, filter chips | `/search?q=`; result → `/map?dest=` | `searchControllerProvider` (debounced), `recentsProvider` | List items staggered fade-in (subtle) | Results announced with count; keyboard-navigable |
| Map | Floor viewing: pan/zoom, tap rooms, floor switcher, POI toggle | `InteractiveViewer` + `CustomPaint` (FloorScene), `SegmentedButton` floors, room sheet (`DraggableScrollableSheet`) | `/map/:buildingId?floor=&dest=` | `floorSceneProvider(building,floor)`, `selectedRoomProvider` | Floor cross-fade; camera ease to selection | Rooms exposed as semantic nodes ("SJT 513, classroom, double-tap for options"); route described textually |
| Navigation | Active route: step list + map overlay, floor auto-switch, progress | Bottom step card, `Stepper`-like list, overlay painter | `/navigate?from=&to=&mode=` | `routeControllerProvider` (sealed RouteState) | Animated dashed polyline; step card slides | Steps readable as list; voice guidance toggle; haptic on floor change |
| Contribution | Suggest edit / report issue from map long-press | Bottom sheet form, type picker, photo attach, map pin placer | `/contribute?target=` (auth-guarded) | `contributionFormProvider` | Sheet spring | Form fully labeled; photo optional & described |
| Profile | Identity, reputation, my contributions + statuses, sign in/out | `ListTile`s, status chips | `/profile` | `authControllerProvider`, `myContributionsProvider` | — | Status chips have text, not color-only |
| Settings | Theme, text size link, accessibility prefs (accessible routes default, prefer lift, voice), campus mgmt, cache clear, about | `SwitchListTile`s, sections | `/settings` | `prefsProvider (Notifier persisted)` | — | The a11y hub — discoverable within 2 taps of home |
| Admin (mobile-lite) | Moderation queue for on-the-go approve/reject | List + diff cards | `/admin` (role-guarded) | `moderationQueueProvider (StreamProvider)` | — | — |
| Error pages | Route-not-found, data-corrupt, generic | Illustration, retry, report | GoRouter `errorBuilder` | — | — | Retry is first focus |
| Offline banner/mode | Non-blocking: banner + stale timestamp; everything cached still works | `MaterialBanner` | n/a (overlay) | `connectivityProvider` | Banner slide | Announced once, not repeatedly |

Cross-cutting: every async screen renders `loading / data / error(retry)` from `AsyncValue` via one shared `AsyncView` widget — no ad-hoc spinners. Navigation state (deep links like `/map/SJT?dest=r_sjt513`) is the single source of truth; screens are restorable from URL alone, which also makes the future web build work.
