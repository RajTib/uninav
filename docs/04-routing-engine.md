# UniNav — Indoor Routing Engine (v1.0)

## 1. Model

**Graph, not grid.** Indoor spaces route along corridors, so a sparse navigation graph (nodes at doors, junctions, stairs) beats a grid/navmesh: tiny memory, exact door-to-door semantics, and contributors can literally place the nodes.

- **Node** `{id, floorId, x, y (metres, per-floor frame), kind}` — kinds: `room, corridor, junction, stair, elevator, ramp, entrance, exit`.
- **Edge** `{a, b, kind, lengthM, accessible, bidirectional}` — kinds: `corridor, stair, elevator, ramp, door, outdoor`.
- **Floor transition = ordinary edge** between nodes on different floors. No special casing in the algorithm; the *path renderer* detects `floorId` changes to split the polyline and emit "Take stairs to Floor 3" instructions. This uniformity is what keeps the engine simple.
- **Multi-building**: `outdoor` edges connect building entrances; graphs of route-relevant buildings are merged on demand.

## 2. Weights

`weight = lengthM × kindMultiplier(prefs) + kindPenalty(prefs)`

| Edge kind | Default | Accessible mode | Prefer-lift |
|---|---|---|---|
| corridor/door | 1× | 1× | 1× |
| stair | 1× + 5 m penalty/floor | ∞ (excluded) | 3× |
| elevator | 1× + 15 m penalty (wait time) | 1× + 5 m | 1× |
| ramp | 1.2× | 1× | 1× |
| edge with `accessible: false` | 1× | ∞ (excluded) | 1× |

Penalties are data-driven constants in `RoutePrefs`, not hardcoded per venue. Elevator's flat penalty models waiting; stairs' per-floor penalty models effort. **Accessibility = graph filtering** (exclude stairs and inaccessible edges), so "no accessible path" is detected honestly rather than silently degraded. Emergency mode (future) filters to `exit`-reachable subgraph with stairs allowed, lifts excluded.

## 3. Algorithm choice

| | Dijkstra | A* | Bidirectional Dijkstra |
|---|---|---|---|
| Explores | uniformly | goal-directed | two frontiers |
| Needs heuristic | no | yes, admissible | no (harder with A*) |
| Nodes ≤10k perf | fine (<50 ms) | best | good |
| Complexity to implement/debug | trivial | small | subtle termination conditions |

**Decision: A\* with a Dijkstra fallback (heuristic = 0).**

- Heuristic: 3-D Euclidean distance `sqrt(dx² + dy² + (Δfloor × floorHeight)²)` using per-floor coordinates aligned to a shared building frame. This is admissible (never overestimates: you must physically cover at least that distance) so optimality is preserved.
- When floors' coordinate frames aren't calibrated to a common origin (possible with community data), the engine detects it and drops to heuristic 0 — which *is* Dijkstra. One implementation, two behaviors; no separate code path to maintain.

**Heuristic safety (implementation note).** Admissibility is a *data* property, not just a code property: it holds only while every edge's `lengthM` is ≥ the straight-line distance between its endpoints. Two ways that breaks in practice — merging buildings whose coordinates are each building-local, and a mistyped length from a contributor — and both produce **silently suboptimal routes**, the worst failure mode for a navigation app (it looks like it worked). So `NavGraph` treats the heuristic as opt-in and self-disabling: frames are assumed aligned only for a single bundle, and any edge failing the straight-line check raises a `GraphIssue.impossibleLength` and turns the heuristic off graph-wide. Correctness is preserved unconditionally; only search speed degrades, and the admin tooling gets a precise data-quality report.
- Bidirectional search rejected: its ~2× win matters at road-network scale (millions of nodes); at ≤10⁴ nodes it buys nothing measurable and costs the most debugging-prone code in pathfinding.
- Multi-goal "nearest washroom" uses the same engine with virtual target set (run Dijkstra from source, stop at first goal hit).

## 4. Output contract

```dart
Route {
  segments: [RouteSegment {floorId, polyline: [Point], lengthM}],
  transitions: [Transition {kind, fromFloorId, toFloorId, atNodeId}],
  totalLengthM, estSeconds,           // walking 1.2 m/s + transition costs
  instructions: [Instruction {text, icon, segmentIndex}]
}
```

Instruction generation (turn-by-turn) is a separate pure function over the path — heading change > 35° between consecutive corridor edges emits "turn left/right"; transitions emit floor-change steps. Keeping it out of the search keeps both testable.

## 5. Correctness & performance guarantees

- Deterministic tie-breaking (node id) → stable routes for tests and users.
- Engine validates the graph on load: dangling edge refs, orphan components (warned, surfaced to admin tooling).
- Runs in an isolate above 3k nodes; binary-heap priority queue; O((V+E) log V).
- Test suite: known-shortest fixtures, accessibility filtering, no-path, multi-floor, penalty monotonicity, and a randomized comparison against brute-force Dijkstra on generated graphs.
