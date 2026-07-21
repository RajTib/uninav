# UniNav — Map Representation (v1.0)

## Options compared

| Criterion | A: PNG plans | B: SVG maps | C: Pure JSON geometry | D: Hybrid (JSON + optional raster underlay) |
|---|---|---|---|---|
| Authoring effort | Lowest (photograph/scan) | High (needs vector tooling) | Medium (admin editor draws) | Medium |
| Community editability | None (opaque pixels) | Poor (XML diffs are hostile) | **Excellent** (structured data, diffable, moderatable) | Excellent |
| Routing support | None — graph must be separate anyway | Partial (still need graph) | **Native** — geometry & graph share coordinates | Native |
| Rendering quality/zoom | Blurry at zoom; huge files | Crisp; Flutter SVG perf is weak for big files | Crisp via CustomPainter; styleable, themeable | Crisp + photographic context |
| Interactivity (tap room, highlight route) | Requires hit-map hacks | Hard (SVG DOM not exposed) | **Trivial** (polygons are data) | Trivial |
| File size / offline | MB per floor | Medium | **KB per floor** | KB + optional MB |
| Versioning/rollback/moderation | Binary blobs, no diff | Poor diffs | **Semantic diffs** ("room 513 moved") | Semantic |
| Dark mode / a11y themes | No | Limited | **Yes** (renderer applies theme) | Yes |

## Decision: **D — hybrid, with JSON as the single source of truth**

Geometry (room polygons, corridors, POIs, nodes, edges) lives in the bundle JSON (03-data-model.md) and is rendered with a custom `CanvasPainter`. An *optional* raster floor-plan image (`planImagePath`, webp in Storage) can be shown as a georeferenced underlay at reduced opacity — useful during early mapping when polygons are sparse, and for admin tracing.

Why not pure C: a raster underlay dramatically lowers the cold-start mapping cost (trace over a photo of the fire-evacuation plan) and gives users spatial context before an area is fully vectorized. Why JSON stays canonical: everything the platform promises — moderated community edits, semantic versioning, rollback, tap-to-identify, accessible theming, tiny offline bundles — is only possible when the map is structured data. PNG-as-truth (option A) is the classic prototype trap: it demos well and then blocks routing, editing, and moderation forever. SVG (B) looks appealing but is a worse JSON: it mixes geometry with presentation, diffs badly, and Flutter's SVG rendering of large files janks.

## Rendering pipeline

```
Bundle JSON → FloorScene (immutable render model: polygons, labels, route overlay)
  → InteractiveViewer (pan/zoom, matrix)
    → CustomPaint layers: underlay image → room fills → walls/strokes
       → POI icons → route polyline (animated) → labels (LOD-culled)
```

- Level-of-detail: labels and small POIs culled below zoom thresholds; polygons pre-simplified at export.
- Hit-testing: point-in-polygon on tap (rooms are few hundred per floor — linear scan is fine; R-tree only if profiling demands).
- Route overlay animates via a single `AnimationController` dash-offset — cheap, no per-frame allocation.
- Theming: renderer consumes Material 3 `ColorScheme` + room-type→style map, giving dark mode and colorblind-safe palettes for free.
