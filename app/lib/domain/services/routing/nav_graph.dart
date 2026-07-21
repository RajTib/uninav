import 'dart:math' as math;

import '../../entities/building_bundle.dart';
import '../../entities/nav.dart';

/// Immutable adjacency-list view over one or more building bundles.
/// Built once per bundle load, reused for every route query.
final class NavGraph {
  NavGraph._({
    required Map<String, NavNode> nodes,
    required Map<String, List<GraphArc>> adjacency,
    required Map<String, int> floorLevels,
    required Map<String, String> floorNames,
    required this.framesAligned,
    required this.issues,
  })  : _nodes = nodes,
        _adjacency = adjacency,
        _floorLevels = floorLevels,
        _floorNames = floorNames;

  /// [framesAligned]: whether all floors share one x/y frame, enabling the
  /// A* distance heuristic. Merged multi-building graphs pass false and the
  /// router degrades gracefully to Dijkstra (heuristic 0) — same code path.
  ///
  /// Default is `bundles.length == 1`: each building's coordinates are
  /// building-local, so across two bundles "(0,0)" means two different places
  /// and the straight-line heuristic would be inadmissible — which silently
  /// returns *suboptimal routes*, not just slower searches. Multi-building
  /// callers must opt in explicitly after georeferencing the frames.
  factory NavGraph.fromBundles(
    List<BuildingBundle> bundles, {
    bool? framesAligned,
    List<NavEdge> interBundleEdges = const [],
  }) {
    final aligned = framesAligned ?? bundles.length == 1;
    // Cleared if any edge is shorter than physically possible (see below):
    // correctness beats speed, so we fall back to Dijkstra rather than
    // trusting a heuristic the data doesn't support.
    var heuristicSafe = true;
    final nodes = <String, NavNode>{};
    final adjacency = <String, List<GraphArc>>{};
    final floorLevels = <String, int>{};
    final floorNames = <String, String>{};
    final issues = <GraphIssue>[];

    for (final bundle in bundles) {
      for (final floor in bundle.floors) {
        floorLevels[floor.id] = floor.level;
        floorNames[floor.id] = floor.name;
      }
      for (final node in bundle.nodes) {
        if (nodes.containsKey(node.id)) {
          issues.add(GraphIssue.duplicateNode(node.id));
        }
        nodes[node.id] = node;
        adjacency.putIfAbsent(node.id, () => []);
      }
    }

    final allEdges = [
      for (final bundle in bundles) ...bundle.edges,
      ...interBundleEdges,
    ];
    for (final edge in allEdges) {
      final a = nodes[edge.a];
      final b = nodes[edge.b];
      if (a == null || b == null) {
        issues.add(GraphIssue.danglingEdge(edge.a, edge.b));
        continue; // Skip rather than crash: community data may be imperfect.
      }
      final floorsCrossed =
          ((floorLevels[a.floorId] ?? 0) - (floorLevels[b.floorId] ?? 0))
              .abs();

      // Heuristic-safety check: A* is only guaranteed optimal while every
      // edge is at least as long as the straight line between its endpoints.
      // Bad community data (a length typo) would otherwise silently produce
      // *wrong* routes rather than obviously broken ones, so flag it and
      // disable the heuristic for the whole graph.
      if (aligned) {
        final dz = floorsCrossed * assumedFloorHeightM;
        final dxy = a.point.distanceTo(b.point);
        final straightLine = math.sqrt(dxy * dxy + dz * dz);
        if (edge.lengthM < straightLine - 1e-6) {
          issues.add(
            GraphIssue.impossibleLength(
              edge.a,
              edge.b,
              edge.lengthM,
              straightLine,
            ),
          );
          heuristicSafe = false;
        }
      }

      adjacency[edge.a]!.add(GraphArc(edge.b, edge, floorsCrossed));
      if (edge.bidirectional) {
        adjacency[edge.b]!.add(GraphArc(edge.a, edge, floorsCrossed));
      }
    }

    for (final entry in adjacency.entries) {
      if (entry.value.isEmpty) {
        issues.add(GraphIssue.orphanNode(entry.key));
      }
    }

    return NavGraph._(
      nodes: nodes,
      adjacency: adjacency,
      floorLevels: floorLevels,
      floorNames: floorNames,
      framesAligned: aligned && heuristicSafe,
      issues: List.unmodifiable(issues),
    );
  }

  /// Metres per floor level, used both for the straight-line
  /// heuristic-safety check above and — via [AStarRouter.assumedFloorHeightM]
  /// — for the A* heuristic itself. The two *must* agree: if the router's
  /// heuristic assumed a different floor height than the one this build-time
  /// check validated against, an edge could pass validation here yet still
  /// make the heuristic inadmissible at search time, silently reintroducing
  /// the wrong-route bug this check exists to prevent (docs/15-known-issues
  /// .md #9). Not venue data — a physical-plausibility constant, same for
  /// every building.
  static const double assumedFloorHeightM = 3.5;

  final Map<String, NavNode> _nodes;
  final Map<String, List<GraphArc>> _adjacency;
  final Map<String, int> _floorLevels;
  final Map<String, String> _floorNames;
  final bool framesAligned;

  /// Non-fatal data problems found at build time; surfaced to admin tooling.
  final List<GraphIssue> issues;

  NavNode? node(String id) => _nodes[id];
  Iterable<GraphArc> arcsFrom(String nodeId) =>
      _adjacency[nodeId] ?? const [];
  int floorLevel(String floorId) => _floorLevels[floorId] ?? 0;

  /// Human floor name for instruction text; falls back to the id so
  /// incomplete data degrades visibly rather than crashing.
  String floorName(String floorId) => _floorNames[floorId] ?? floorId;

  int get nodeCount => _nodes.length;
}

/// One directed traversal option out of a node.
final class GraphArc {
  const GraphArc(this.to, this.edge, this.floorsCrossed);
  final String to;
  final NavEdge edge;
  final int floorsCrossed;
}

final class GraphIssue {
  const GraphIssue._(this.kind, this.detail);
  factory GraphIssue.danglingEdge(String a, String b) =>
      GraphIssue._(GraphIssueKind.danglingEdge, '$a -> $b');
  factory GraphIssue.orphanNode(String id) =>
      GraphIssue._(GraphIssueKind.orphanNode, id);
  factory GraphIssue.duplicateNode(String id) =>
      GraphIssue._(GraphIssueKind.duplicateNode, id);
  factory GraphIssue.impossibleLength(
    String a,
    String b,
    double declared,
    double straightLine,
  ) =>
      GraphIssue._(
        GraphIssueKind.impossibleLength,
        '$a -> $b declares ${declared.toStringAsFixed(1)} m but the straight '
        'line is ${straightLine.toStringAsFixed(1)} m',
      );

  final GraphIssueKind kind;
  final String detail;

  @override
  String toString() => '${kind.name}: $detail';
}

enum GraphIssueKind {
  danglingEdge,
  orphanNode,
  duplicateNode,
  impossibleLength,
}
