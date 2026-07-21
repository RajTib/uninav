# UniNav — Performance & Scale (v1.0)

Targets: 100+ buildings, 10k+ rooms per campus, 2 GB RAM devices, minimal Firestore spend.

## Firestore read minimization (the cost architecture)
1. Bundles in Storage, not docs (03): a building = 1 GET, not O(rooms) reads.
2. Version-gated sync: metadata read only on app open + pull-to-refresh; bundle downloaded only when `publishedVersion` differs from cache.
3. Campus-level `bundlesUpdatedAt` short-circuit when building count > ~20: 1 read answers "anything new?".
4. Announcements: 1 cached query/day. User data: local-first, lazy sync.
Budget assertion: < 20 reads/user/day steady-state, measured via a debug read counter in dev builds.

## Memory & lazy loading
- Load per-building graphs on demand; LRU-evict scenes for buildings not viewed recently (cap ~5 buildings in memory).
- Search index holds summaries only (~40 B/entry × 10k ≈ negligible); geometry never enters the index.
- Route across buildings merges only route-relevant graphs.
- Plan underlay images: webp, downsampled to screen resolution, `cacheWidth` set; evicted with scene.

## CPU / jank
- A* in an isolate when nodes > 3k (`compute`); JSON bundle decode in an isolate always (decode is the real jank source, not routing).
- FloorScene is immutable + `shouldRepaint` diffing; painters allocate nothing per frame; labels LOD-culled by zoom.
- Debounced search (250 ms) on main isolate until profiling says otherwise (measure, don't guess).

## Offline
- Tier: bundled asset campus → disk bundle cache → network (02 §7). Everything user-facing (search, route, render) reads from the cache tier, so offline is the default path, not a fallback path — there is no "offline mode" branch to break.
- Explicit "Download campus" for full prefetch (Wi-Fi-only option); stale badge shows bundle age when unverifiable.

## Measurement discipline
- Perf budgets in CI-adjacent checklist: cold start (trace), frame stats on map pan (DevTools), bundle decode time logged.
- No optimization lands without a before/after number; no speculative optimization (R-trees, isolate search) before a profile shows need.
