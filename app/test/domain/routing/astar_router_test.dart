import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/core/error/failure.dart';
import 'package:uninav/core/result/result.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/entities/building_bundle.dart';
import 'package:uninav/domain/entities/geometry.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';
import 'package:uninav/domain/services/routing/route.dart';
import 'package:uninav/domain/services/routing/route_prefs.dart';

// ---------------------------------------------------------------- helpers

NavNode node(String id, double x, double y,
        {String floor = 'f0', NodeKind kind = NodeKind.corridor,}) =>
    NavNode(id: id, floorId: floor, point: Point2(x, y), kind: kind);

NavEdge edge(String a, String b, double len,
        {EdgeKind kind = EdgeKind.corridor, bool accessible = true,}) =>
    NavEdge(a: a, b: b, kind: kind, lengthM: len, accessible: accessible);

BuildingBundle bundleOf(List<NavNode> nodes, List<NavEdge> edges,
        {List<Floor>? floors,}) =>
    BuildingBundle(
      schemaVersion: 1,
      buildingId: 'test',
      buildingName: 'Test',
      version: 1,
      floors: floors ??
          const [
            Floor(id: 'f0', level: 0, name: 'G', widthM: 100, heightM: 100),
            Floor(id: 'f1', level: 1, name: '1', widthM: 100, heightM: 100),
          ],
      rooms: const [],
      pois: const [],
      nodes: nodes,
      edges: edges,
    );

NavRoute expectOk(Result<NavRoute, RoutingFailure> r) =>
    r.fold((v) => v, (e) => fail('expected route, got $e'));

RoutingFailure expectErr(Result<NavRoute, RoutingFailure> r) =>
    r.fold((v) => fail('expected failure, got route $v'), (e) => e);

void main() {
  const router = AStarRouter();

  group('basic pathfinding', () {
    test('finds shortest path on a line', () {
      final g = NavGraph.fromBundles([
        bundleOf(
          [node('a', 0, 0), node('b', 2, 0), node('c', 5, 0)],
          [edge('a', 'b', 2), edge('b', 'c', 3)],
        ),
      ]);
      final route = expectOk(router.findRoute(g, from: 'a', to: 'c'));
      expect(route.nodeIds, ['a', 'b', 'c']);
      expect(route.totalLengthM, 5);
      expect(route.segments.single.floorId, 'f0');
    });

    test('start == goal yields a zero-length route', () {
      final g = NavGraph.fromBundles([
        bundleOf([node('a', 0, 0), node('b', 1, 0)], [edge('a', 'b', 1)]),
      ]);
      final route = expectOk(router.findRoute(g, from: 'a', to: 'a'));
      expect(route.nodeIds, ['a']);
      expect(route.totalLengthM, 0);
    });

    test('picks the cheaper of two alternatives', () {
      // a -> b: direct 10, or via c: 4 + 4 = 8.
      final g = NavGraph.fromBundles([
        bundleOf(
          [node('a', 0, 0), node('b', 7, 0), node('c', 3, 2)],
          [edge('a', 'b', 10), edge('a', 'c', 4), edge('c', 'b', 4)],
        ),
      ]);
      final route = expectOk(router.findRoute(g, from: 'a', to: 'b'));
      expect(route.nodeIds, ['a', 'c', 'b']);
      expect(route.totalLengthM, 8);
    });

    test('respects directed (one-way) edges', () {
      final g = NavGraph.fromBundles([
        bundleOf(
          [node('a', 0, 0), node('b', 5, 0)],
          [
            const NavEdge(
              a: 'b',
              b: 'a',
              kind: EdgeKind.corridor,
              lengthM: 5,
              bidirectional: false,
            ),
          ],
        ),
      ]);
      final failure = expectErr(router.findRoute(g, from: 'a', to: 'b'));
      expect(failure.reason, RoutingFailureReason.disconnected);
    });

    test('reports missing nodes', () {
      final g = NavGraph.fromBundles([
        bundleOf([node('a', 0, 0)], const []),
      ]);
      final failure = expectErr(router.findRoute(g, from: 'a', to: 'zz'));
      expect(failure.reason, RoutingFailureReason.nodeMissing);
    });
  });

  group('demo fixture (asset JSON is the ground truth)', () {
    late NavGraph graph;

    setUpAll(() {
      final raw = File('assets/campuses/demo/bundle_main.json')
          .readAsStringSync();
      final bundle = BuildingBundleDto.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      graph = NavGraph.fromBundles([bundle]);
      expect(graph.issues, isEmpty,
          reason: 'demo fixture must be a clean graph',);
    });

    test('fastest r101 -> r202 takes the stairs (length 41 m)', () {
      final route = expectOk(
        router.findRoute(graph, from: 'n_r101', to: 'n_r202'),
      );
      expect(route.totalLengthM, closeTo(41, 1e-9));
      expect(route.transitions.single.kind, EdgeKind.stair);
      expect(route.segments, hasLength(2));
      expect(route.segments.first.floorId, 'f0');
      expect(route.segments.last.floorId, 'f1');
    });

    test('accessible r101 -> r202 takes the lift (length 40 m)', () {
      final route = expectOk(
        router.findRoute(
          graph,
          from: 'n_r101',
          to: 'n_r202',
          prefs: RoutePrefs.accessible,
        ),
      );
      expect(route.totalLengthM, closeTo(40, 1e-9));
      expect(route.transitions.single.kind, EdgeKind.elevator);
    });

    test('preferLift also chooses the lift', () {
      final route = expectOk(
        router.findRoute(
          graph,
          from: 'n_r101',
          to: 'n_r202',
          prefs: RoutePrefs.preferLift,
        ),
      );
      expect(route.transitions.single.kind, EdgeKind.elevator);
    });

    test('turn-by-turn for r101 -> r103 (same floor)', () {
      final route = expectOk(
        router.findRoute(graph, from: 'n_r101', to: 'n_r103'),
      );
      expect(route.totalLengthM, 30);
      expect(
        route.instructions.map((i) => i.kind).toList(),
        [
          InstructionKind.start,
          InstructionKind.walk, // 5 m out of the room
          InstructionKind.turnLeft,
          InstructionKind.walk, // 20 m along the corridor
          InstructionKind.turnLeft,
          InstructionKind.walk, // 5 m to the lab
          InstructionKind.arrive,
        ],
      );
    });
  });

  group('constraint handling', () {
    test('accessible mode with stairs-only link reports noPathForConstraints',
        () {
      final g = NavGraph.fromBundles([
        bundleOf(
          [
            node('a', 0, 0),
            node('s0', 1, 0, kind: NodeKind.stair),
            node('s1', 1, 0, floor: 'f1', kind: NodeKind.stair),
            node('b', 0, 0, floor: 'f1'),
          ],
          [
            edge('a', 's0', 1),
            edge('s0', 's1', 4, kind: EdgeKind.stair),
            edge('s1', 'b', 1),
          ],
        ),
      ]);
      expect(
        expectOk(router.findRoute(g, from: 'a', to: 'b')).transitions.single
            .kind,
        EdgeKind.stair,
      );
      final failure = expectErr(
        router.findRoute(g, from: 'a', to: 'b',
            prefs: RoutePrefs.accessible,),
      );
      expect(failure.reason, RoutingFailureReason.noPathForConstraints);
    });

    test('inaccessible edges are excluded in accessible mode', () {
      // Short path exists but is inaccessible; long accessible detour wins.
      final g = NavGraph.fromBundles([
        bundleOf(
          [node('a', 0, 0), node('b', 10, 0), node('c', 5, 8)],
          [
            edge('a', 'b', 10, accessible: false),
            edge('a', 'c', 10),
            edge('c', 'b', 10),
          ],
        ),
      ]);
      final fast = expectOk(router.findRoute(g, from: 'a', to: 'b'));
      expect(fast.totalLengthM, 10);
      final acc = expectOk(
        router.findRoute(g, from: 'a', to: 'b',
            prefs: RoutePrefs.accessible,),
      );
      expect(acc.totalLengthM, 20);
    });
  });

  group('A* agrees with brute-force Dijkstra on random graphs', () {
    test('100 random graphs, all pairs sampled', () {
      final rng = Random(42); // deterministic
      for (var trial = 0; trial < 100; trial++) {
        final nodeCount = 2 + rng.nextInt(30);
        final nodes = [
          for (var i = 0; i < nodeCount; i++)
            node('n$i', rng.nextDouble() * 100, rng.nextDouble() * 100),
        ];
        final edges = <NavEdge>[];
        for (var i = 0; i < nodeCount; i++) {
          final links = 1 + rng.nextInt(3);
          for (var k = 0; k < links; k++) {
            final j = rng.nextInt(nodeCount);
            if (j == i) continue;
            final physical =
                nodes[i].point.distanceTo(nodes[j].point);
            // Length >= straight-line distance keeps the heuristic
            // admissible, mirroring real map data.
            edges.add(
              edge('n$i', 'n$j', physical + rng.nextDouble() * 5),
            );
          }
        }
        final g = NavGraph.fromBundles([bundleOf(nodes, edges)]);
        final from = 'n${rng.nextInt(nodeCount)}';
        final to = 'n${rng.nextInt(nodeCount)}';

        final expected = _dijkstraCost(g, from, to);
        final actual = router.findRoute(g, from: from, to: to);
        if (expected == null) {
          expectErr(actual);
        } else {
          final route = expectOk(actual);
          expect(route.totalLengthM, closeTo(expected, 1e-6),
              reason: 'trial $trial: $from -> $to',);
        }
      }
    });
  });
}

/// Reference implementation: naive O(V^2) Dijkstra over edge lengths.
double? _dijkstraCost(NavGraph g, String from, String to) {
  final dist = <String, double>{from: 0};
  final visited = <String>{};
  while (true) {
    String? current;
    var best = double.infinity;
    for (final e in dist.entries) {
      if (!visited.contains(e.key) && e.value < best) {
        best = e.value;
        current = e.key;
      }
    }
    if (current == null) return null;
    if (current == to) return dist[current];
    visited.add(current);
    for (final arc in g.arcsFrom(current)) {
      final nd = dist[current]! + arc.edge.lengthM;
      if (nd < (dist[arc.to] ?? double.infinity)) dist[arc.to] = nd;
    }
  }
}
