import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../entities/geometry.dart';
import '../../entities/nav.dart';
import 'nav_graph.dart';
import 'route.dart';
import 'route_prefs.dart';

/// A* shortest-path router. With an unaligned coordinate frame the heuristic
/// is 0 and this *is* Dijkstra — one implementation, two behaviors
/// (docs/04-routing-engine.md §3).
///
/// Pure Dart, deterministic, side-effect free: call it from an isolate for
/// graphs above a few thousand nodes.
final class AStarRouter {
  const AStarRouter({
    this.assumedFloorHeightM = NavGraph.assumedFloorHeightM,
    this.walkingSpeedMps = 1.2,
  });

  /// Defaults to [NavGraph.assumedFloorHeightM] — the two must agree (see
  /// that constant's doc comment). Overriding this without also passing a
  /// matching value to [NavGraph.fromBundles]'s validation would reintroduce
  /// the inadmissible-heuristic bug docs/15-known-issues.md #9 warns about.
  final double assumedFloorHeightM;
  final double walkingSpeedMps;

  Result<NavRoute, RoutingFailure> findRoute(
    NavGraph graph, {
    required String from,
    required String to,
    RoutePrefs prefs = RoutePrefs.fastest,
  }) {
    final start = graph.node(from);
    final goal = graph.node(to);
    if (start == null || goal == null) {
      return Result.err(
        RoutingFailure(
          'unknown node: ${start == null ? from : to}',
          RoutingFailureReason.nodeMissing,
        ),
      );
    }

    final path = _search(graph, from, to, prefs);
    if (path != null) {
      return Result.ok(_assemble(graph, from, path));
    }

    // Classify the failure honestly: is the graph disconnected, or did the
    // constraints (e.g. accessible mode) remove every viable path?
    // Compare by mode, not identity — a caller-built RoutePrefs must classify
    // the same way as the shared presets.
    final unconstrained = prefs.mode == RouteMode.fastest
        ? null
        : _search(graph, from, to, RoutePrefs.fastest);
    final reason = unconstrained == null
        ? RoutingFailureReason.disconnected
        : RoutingFailureReason.noPathForConstraints;
    return Result.err(RoutingFailure('no path $from -> $to', reason));
  }

  /// Nearest-of-many: shortest route from [from] to whichever of [goals] is
  /// cheapest to reach ("nearest washroom"). Uniform-cost search (heuristic
  /// 0 — a single-goal heuristic is unsound for a goal *set*), stopping at
  /// the first goal popped, which under Dijkstra is provably the nearest.
  Result<NavRoute, RoutingFailure> findNearestRoute(
    NavGraph graph, {
    required String from,
    required Set<String> goals,
    RoutePrefs prefs = RoutePrefs.fastest,
  }) {
    if (graph.node(from) == null) {
      return Result.err(
        RoutingFailure('unknown node: $from', RoutingFailureReason.nodeMissing),
      );
    }
    final validGoals = {for (final g in goals) if (graph.node(g) != null) g};
    if (validGoals.isEmpty) {
      return const Result.err(
        RoutingFailure('no goal nodes', RoutingFailureReason.nodeMissing),
      );
    }
    if (validGoals.contains(from)) {
      return Result.ok(_assemble(graph, from, const []));
    }

    final gScore = <String, double>{from: 0};
    final cameFrom = <String, _ArrivalArc>{};
    final open = HeapPriorityQueue<_OpenEntry>((a, b) {
      final byF = a.f.compareTo(b.f);
      return byF != 0 ? byF : a.id.compareTo(b.id);
    })
      ..add(_OpenEntry(from, 0));
    final closed = <String>{};

    while (open.isNotEmpty) {
      final current = open.removeFirst();
      if (closed.contains(current.id)) continue;
      if (validGoals.contains(current.id)) {
        return Result.ok(
          _assemble(graph, from, _reconstruct(graph, cameFrom, from, current.id)),
        );
      }
      closed.add(current.id);
      final g = gScore[current.id]!;
      for (final arc in graph.arcsFrom(current.id)) {
        if (closed.contains(arc.to)) continue;
        final cost = prefs.arcCost(arc);
        if (cost == null) continue;
        final tentative = g + cost;
        if (tentative < (gScore[arc.to] ?? double.infinity)) {
          gScore[arc.to] = tentative;
          cameFrom[arc.to] = _ArrivalArc(current.id, arc);
          open.add(_OpenEntry(arc.to, tentative));
        }
      }
    }

    // Same honest classification as findRoute: if the unconstrained search
    // can reach a goal, the constraints are what blocked it.
    final reachableUnconstrained = prefs.mode == RouteMode.fastest
        ? false
        : validGoals.any(
            (g) => _search(graph, from, g, RoutePrefs.fastest) != null,
          );
    return Result.err(
      RoutingFailure(
        'no reachable goal from $from',
        reachableUnconstrained
            ? RoutingFailureReason.noPathForConstraints
            : RoutingFailureReason.disconnected,
      ),
    );
  }

  // ---------------------------------------------------------------- search

  /// Returns the traversed arcs in order (empty list for from == to), or
  /// null when no path exists. Arcs — not node ids — are the search output,
  /// so parallel edges between the same node pair stay unambiguous.
  List<GraphArc>? _search(
    NavGraph graph,
    String from,
    String to,
    RoutePrefs prefs,
  ) {
    if (from == to) return const [];
    final goalNode = graph.node(to)!;
    final goalLevel = graph.floorLevel(goalNode.floorId);

    double heuristic(String id) {
      if (!graph.framesAligned) return 0;
      final n = graph.node(id)!;
      final dxy = n.point.distanceTo(goalNode.point);
      final dz =
          (graph.floorLevel(n.floorId) - goalLevel) * assumedFloorHeightM;
      // 3-D straight-line distance: admissible because every arc cost is
      // >= its physical length (see RoutePrefs.arcCost invariant).
      return math.sqrt(dxy * dxy + dz * dz);
    }

    final gScore = <String, double>{from: 0};
    final cameFrom = <String, _ArrivalArc>{};
    final open = HeapPriorityQueue<_OpenEntry>((a, b) {
      final byF = a.f.compareTo(b.f);
      return byF != 0 ? byF : a.id.compareTo(b.id); // deterministic ties
    })
      ..add(_OpenEntry(from, heuristic(from)));
    final closed = <String>{};

    while (open.isNotEmpty) {
      final current = open.removeFirst();
      if (closed.contains(current.id)) continue; // stale duplicate
      if (current.id == to) return _reconstruct(graph, cameFrom, from, to);
      closed.add(current.id);
      final g = gScore[current.id]!;

      for (final arc in graph.arcsFrom(current.id)) {
        if (closed.contains(arc.to)) continue;
        final cost = prefs.arcCost(arc);
        if (cost == null) continue; // excluded under these prefs
        final tentative = g + cost;
        if (tentative < (gScore[arc.to] ?? double.infinity)) {
          gScore[arc.to] = tentative;
          cameFrom[arc.to] = _ArrivalArc(current.id, arc);
          open.add(_OpenEntry(arc.to, tentative + heuristic(arc.to)));
        }
      }
    }
    return null;
  }

  List<GraphArc> _reconstruct(
    NavGraph graph,
    Map<String, _ArrivalArc> cameFrom,
    String from,
    String to,
  ) {
    final arcs = <GraphArc>[];
    var cursor = to;
    while (cursor != from) {
      final arrival = cameFrom[cursor]!;
      arcs.add(arrival.arc);
      cursor = arrival.fromId;
    }
    return arcs.reversed.toList(growable: false);
  }

  // -------------------------------------------------------------- assembly

  NavRoute _assemble(NavGraph graph, String from, List<GraphArc> arcs) {
    final startNode = graph.node(from)!;
    final nodeIds = <String>[from];
    final segments = <RouteSegment>[];
    final transitions = <RouteTransition>[];
    var totalLength = 0.0;
    var transitionSeconds = 0;

    var segmentPoints = [startNode.point];
    var segmentFloor = startNode.floorId;
    var segmentLength = 0.0;

    void closeSegment() {
      segments.add(
        RouteSegment(
          floorId: segmentFloor,
          points: List.unmodifiable(segmentPoints),
          lengthM: segmentLength,
        ),
      );
    }

    var currentId = from;
    for (final arc in arcs) {
      final prev = graph.node(currentId)!;
      final next = graph.node(arc.to)!;
      nodeIds.add(next.id);
      totalLength += arc.edge.lengthM;

      if (next.floorId == segmentFloor) {
        segmentPoints.add(next.point);
        segmentLength += arc.edge.lengthM;
      } else {
        closeSegment();
        transitions.add(
          RouteTransition(
            kind: arc.edge.kind,
            fromFloorId: prev.floorId,
            toFloorId: next.floorId,
            atNodeId: prev.id,
          ),
        );
        transitionSeconds += switch (arc.edge.kind) {
          EdgeKind.elevator => 40,
          EdgeKind.stair => 15 * math.max(1, arc.floorsCrossed),
          _ => 10,
        };
        segmentFloor = next.floorId;
        segmentPoints = [next.point];
        segmentLength = 0;
      }
      currentId = next.id;
    }
    closeSegment();

    final walkSeconds = totalLength / walkingSpeedMps;
    return NavRoute(
      nodeIds: List.unmodifiable(nodeIds),
      segments: List.unmodifiable(segments),
      transitions: List.unmodifiable(transitions),
      totalLengthM: totalLength,
      estSeconds: (walkSeconds + transitionSeconds).round(),
      instructions: _instructions(graph, segments, transitions),
    );
  }

  /// Turn-by-turn text, derived purely from geometry — kept out of the search
  /// so both are independently testable.
  List<RouteInstruction> _instructions(
    NavGraph graph,
    List<RouteSegment> segments,
    List<RouteTransition> transitions,
  ) {
    const turnThresholdDeg = 35.0;
    final out = <RouteInstruction>[
      const RouteInstruction(kind: InstructionKind.start, text: 'Start'),
    ];

    for (var s = 0; s < segments.length; s++) {
      final pts = segments[s].points;
      var legLength = 0.0;

      void flushWalk() {
        if (legLength > 0.5) {
          out.add(
            RouteInstruction(
              kind: InstructionKind.walk,
              text: 'Walk ${legLength.round()} m',
            ),
          );
          legLength = 0;
        }
      }

      for (var i = 1; i < pts.length; i++) {
        legLength += pts[i - 1].distanceTo(pts[i]);
        if (i < pts.length - 1) {
          final turn = _turnAngleDeg(pts[i - 1], pts[i], pts[i + 1]);
          if (turn.abs() >= turnThresholdDeg) {
            flushWalk();
            out.add(
              RouteInstruction(
                kind: turn > 0
                    ? InstructionKind.turnLeft
                    : InstructionKind.turnRight,
                text: turn > 0 ? 'Turn left' : 'Turn right',
              ),
            );
          }
        }
      }
      flushWalk();

      if (s < transitions.length) {
        final t = transitions[s];
        final verb = switch (t.kind) {
          EdgeKind.elevator => 'Take the lift',
          EdgeKind.stair => 'Take the stairs',
          EdgeKind.ramp => 'Take the ramp',
          _ => 'Continue',
        };
        out.add(
          RouteInstruction(
            kind: InstructionKind.floorChange,
            text: '$verb to ${graph.floorName(t.toFloorId)}',
          ),
        );
      }
    }

    out.add(
      const RouteInstruction(
        kind: InstructionKind.arrive,
        text: 'You have arrived',
      ),
    );
    return List.unmodifiable(out);
  }

  /// Signed turn angle at [p2] in degrees; positive = left (y-down frame).
  double _turnAngleDeg(Point2 p1, Point2 p2, Point2 p3) {
    final v1x = p2.x - p1.x, v1y = p2.y - p1.y;
    final v2x = p3.x - p2.x, v2y = p3.y - p2.y;
    final cross = v1x * v2y - v1y * v2x;
    final dot = v1x * v2x + v1y * v2y;
    final angle = math.atan2(cross, dot) * 180 / math.pi;
    // Screen/floor frames are y-down, so a positive cross product is a
    // clockwise (right) turn visually; flip so positive = left.
    return -angle;
  }
}

final class _OpenEntry {
  const _OpenEntry(this.id, this.f);
  final String id;
  final double f;
}

/// How the search arrived at a node: predecessor + the exact arc taken.
final class _ArrivalArc {
  const _ArrivalArc(this.fromId, this.arc);
  final String fromId;
  final GraphArc arc;
}
