# UniNav — Implementation Roadmap (solo dev + Claude Pro, v1.0)

Estimates assume ~10–15 focused hrs/week. Each milestone ends with: working build, tests green, self-review, tag.

| # | Milestone | Contents | Est. | Difficulty | Risk | Depends on |
|---|---|---|---|---|---|---|
| M1 | Core skeleton + engine | Repo, CI, analysis_options, folder structure, domain entities, bundle JSON schema + codecs, **A\* engine + tests**, mock/asset data source, sample building fixture | 2 wk | Med | Low — pure Dart, fully testable | — |
| M2 | Map rendering | FloorScene, CustomPainter pipeline, pan/zoom, tap-to-select, floor switcher, route overlay | 3 wk | **High** (the hardest UI work; custom painting + gestures) | Perf jank; mitigate with immutable scene + profiling early | M1 |
| M3 | Search + navigation UX | Search index + ranking, search screen, route screen w/ steps, prefs (accessible mode), recents/favorites (local) | 2 wk | Med | Low | M1, M2 |
| M4 | App shell | GoRouter, theming, splash/onboarding/settings/error/offline states, demo campus asset polish | 1.5 wk | Low | Low | M3 |
| M5 | Firebase read path | Auth (anon+Google), Firestore metadata, Storage bundle sync, disk cache, rules v1 deploy, App Check | 2 wk | Med | Config fiddliness; keep asset source as fallback | M4 |
| M6 | **Content: map one real building** | Hand-author SJT (or chosen building) bundle via scripts; field-verify; fix schema pain points found | 2 wk | Low tech / High grind | Motivation risk — timebox; this validates everything | M5 |
| M7 | Closed beta | 20–50 students, Crashlytics, analytics events, zero-hit search log, fix cycle | 2 wk | Low | Feedback volume | M6 |
| M8 | Contributions (client) | Contribution forms, my-contributions, moderation-lite screen for you as moderator, rules v2 | 2.5 wk | Med | Moderation merge correctness — reuse tested merge engine | M7 |
| M9 | Monorepo split + admin editor | packages/ split, Flutter Web admin, floor editor (calibrate, draw, nodes, edges, validate, publish) | 4 wk | **High** | Biggest single feature; cut scope to editor-only first | M8 |
| M10 | Cloud Functions hardening | Server-side approval merge, rate limits, reputation, index regeneration | 2 wk | Med | Cold-start/billing surprises | M9 |
| M11 | Public v1 | Store listing, onboarding polish, second building mapped by community pilot | 2 wk | Low | Store review | M10 |

Total ≈ 25 weeks part-time. Critical path: M1 → M2 → M3 → M5 → M6.

**Sequencing rationale:** engine before UI (correctness cheap to test first); rendering before Firebase (the product risk is "is custom map UX good enough?", not "can I call Firestore?"); real content (M6) before beta — a beautiful empty map teaches nothing; admin tooling only after contribution shapes are proven by real moderation done manually.

**Kill criteria / checkpoints:** after M2, if custom rendering is unacceptably janky on a low-end device, fall back to raster-underlay-first rendering (same data model — this is why JSON stays canonical). After M7, if activation < 30%, fix findability before building the contribution platform.
