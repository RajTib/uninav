# UniNav — Admin Dashboard (v1.0)

## 1. Platform decision

**Flutter Web, same monorepo, reusing `domain/` and `data/`.** A React/Next dashboard was considered (better web ecosystem, faster tables) and rejected: it would duplicate the entities, DTOs, graph validation, and renderer a solo dev must then keep in sync. The killer requirement — the **visual node/floor editor** — is exactly the custom-canvas code the mobile app already has; reusing the `FloorScene` renderer with an editing layer is weeks of saved work. Trade-off accepted: Flutter Web's weaker text/SEO story is irrelevant for an authenticated internal tool.

Structure: `apps/admin_web/` + shared packages (`packages/uninav_core` = domain, `packages/uninav_data`). Mobile app becomes `apps/mobile/`. (Milestone 1 starts as a single app; the split is a scripted refactor scheduled in the roadmap *before* admin work starts.)

## 2. Screens

| Screen | Capabilities |
|---|---|
| Login | Google sign-in; role check (`roles/{uid}`), non-staff bounced |
| Moderation queue | Filter by campus/building/type/status; diff viewer (base/current/proposed on map); approve / reject+reason / batch approve; supersede handling |
| Campus manager | CRUD campuses, publish/draft toggle, moderator assignment |
| Building manager | CRUD buildings, floors summary, upload plan images, version history + one-click rollback |
| **Floor editor** | The core tool: raster underlay calibration (2-point scale set), draw room polygons, place/drag nodes, connect edges (click-click), tag kinds/accessibility, live graph-validation panel (orphans, dangling refs, unreachable rooms), route preview between any two nodes |
| Import/Export | Bundle JSON down/upload with schema validation + dry-run diff report before publish |
| Analytics | Searches with zero results (mapping gap detector!), top destinations, routes/day, contribution funnel |
| Audit log | Filterable append-only viewer |

## 3. Editor UX decisions

- Editing happens on a **draft working copy** (local + Storage draft path), never on the published bundle; explicit Publish creates the MapVersion. Autosave every 30 s to draft.
- Undo/redo as an in-memory command stack over the draft (the payloads are the same contribution-shaped ops — one merge engine serves both community edits and admin edits).
- Keyboard-first: `N` place node, `E` edge mode, `R` room polygon, `Esc` cancel, arrows nudge.
- Graph validation runs on every mutation (debounced); Publish is blocked on errors, warnings allowed with confirmation.

## 4. Analytics: minimal, purposeful

Client logs (batched, anonymous by default): `search_performed {query, hits}`, `route_computed {from, to, lengthM, accessibleMode}`, `bundle_downloaded`. Zero-hit searches are the highest-value signal — they are the map's missing-content backlog, surfaced directly in the dashboard.
