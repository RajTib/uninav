# UniNav — Search Engine (v1.0)

## 1. Where search runs: on-device

Firestore cannot do substring/fuzzy search, and per-keystroke server queries would be slow, costly, and dead offline. The searchable corpus per campus is small (10⁴ entries ≈ a few hundred KB), so the index is built **in memory on the client** from a campus-level `searchIndex.json` Storage blob (regenerated at publish; versioned via `campuses.searchIndexVersion`). Algolia/Typesense rejected for MVP: cost + an offline hole, for no capability we can't afford locally at this scale.

## 2. Index & entry shape

```dart
SearchEntry { id, kind /*room|poi|building|department|person*/,
  displayName, buildingId, floorId, aliases: [..], tokens: [..], boost }
```

Token pipeline: lowercase → strip punctuation → split camel/alnum boundaries ("SJT513A" → sjt, 513, a; "Lab-3" → lab, 3) → alias expansion from data ("Tech Tower" → sjt). Structures: token → posting-list map for exact/prefix (trie unnecessary at this size; sorted-list binary search on prefixes), plus the raw entries for fuzzy pass.

## 3. Query pipeline (per debounced keystroke, 250 ms)

```
normalize(q) → exact token match (score 100)
            → prefix match (80, scaled by matched fraction)
            → fuzzy: Damerau-Levenshtein ≤ 1 (len ≤ 5) or ≤ 2 (longer), score 60 − 10·dist
            → alias hits ×0.95
rank = matchScore + kindBoost(room 10, building 8, poi 5)
     + recencyBoost(recent searches, +15) + favoriteBoost(+20)
     + sameBuildingBoost(current context, +5)
top 20, grouped by kind
```

Fuzzy runs only when exact+prefix produce < 5 hits (typo repair as fallback keeps the common path fast). Full pass worst case ~10k entries × cheap ops ≪ 16 ms frame budget; measured, and moved to an isolate only if profiling says so.

## 4. Feature mapping

- **Room number / lab / building / department:** entry kinds + tokenization above.
- **Professor:** `person` entries emitted from room `tags` (office → "Dr. Rao" → cabin) until a directory collection exists.
- **Aliases & partial:** aliases are first-class in data; prefix covers partials.
- **Recents:** local ring buffer (50), synced to `users/{uid}` when signed in; shown on empty query.
- **Favorites:** pinned section on empty query; ranking boost when querying.
- **Zero-hit queries:** logged (anonymized) — feeds the mapping-gap analytics (07).

## 5. Testing

Golden ranking tests ("513" → SJT 513 above CDMM 513 when context = SJT), typo tables ("libary", "sjt51"), alias round-trips, and a fuzz test asserting no query crashes the tokenizer.
