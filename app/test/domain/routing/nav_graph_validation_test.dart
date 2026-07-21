import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/domain/entities/building_bundle.dart';
import 'package:uninav/domain/entities/geometry.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';

BuildingBundle bundleOf(
  String id,
  List<NavNode> nodes,
  List<NavEdge> edges,
) =>
    BuildingBundle(
      schemaVersion: 1,
      buildingId: id,
      buildingName: id,
      version: 1,
      floors: const [
        Floor(id: 'f0', level: 0, name: 'G', widthM: 100, heightM: 100),
      ],
      rooms: const [],
      pois: const [],
      nodes: nodes,
      edges: edges,
    );

NavNode n(String id, double x, double y, {String floor = 'f0'}) =>
    NavNode(id: id, floorId: floor, point: Point2(x, y), kind: NodeKind.corridor);

NavEdge e(String a, String b, double len) =>
    NavEdge(a: a, b: b, kind: EdgeKind.corridor, lengthM: len);

void main() {
  group('heuristic safety', () {
    test('single bundle keeps frames aligned (A* enabled)', () {
      final g = NavGraph.fromBundles([
        bundleOf('b1', [n('a', 0, 0), n('b', 10, 0)], [e('a', 'b', 10)]),
      ]);
      expect(g.framesAligned, isTrue);
      expect(g.issues, isEmpty);
    });

    test('multiple bundles default to unaligned frames (Dijkstra)', () {
      // Building-local coordinates: "(0,0)" means a different place in each
      // bundle, so the straight-line heuristic would be unsound.
      final g = NavGraph.fromBundles([
        bundleOf('b1', [n('a', 0, 0), n('b', 10, 0)], [e('a', 'b', 10)]),
        bundleOf('b2', [n('c', 0, 0), n('d', 10, 0)], [e('c', 'd', 10)]),
      ]);
      expect(g.framesAligned, isFalse);
    });

    test('explicit opt-in re-enables the heuristic for georeferenced data',
        () {
      final g = NavGraph.fromBundles(
        [
          bundleOf('b1', [n('a', 0, 0), n('b', 10, 0)], [e('a', 'b', 10)]),
          bundleOf('b2', [n('c', 50, 0), n('d', 60, 0)], [e('c', 'd', 10)]),
        ],
        framesAligned: true,
      );
      expect(g.framesAligned, isTrue);
    });

    test('an impossibly short edge is flagged and disables the heuristic', () {
      // 2 m declared across a 10 m gap: a data typo that would otherwise make
      // A* return a suboptimal (wrong) route silently.
      final g = NavGraph.fromBundles([
        bundleOf('b1', [n('a', 0, 0), n('b', 10, 0)], [e('a', 'b', 2)]),
      ]);
      expect(
        g.issues.map((i) => i.kind),
        contains(GraphIssueKind.impossibleLength),
      );
      expect(
        g.framesAligned,
        isFalse,
        reason: 'falls back to Dijkstra, which stays correct',
      );
    });

    test('routes remain correct on data with a bad length', () {
      // Cheap detour (2+2) vs direct (10): must pick the detour either way.
      final g = NavGraph.fromBundles([
        bundleOf(
          'b1',
          [n('s', 0, 0), n('m', 1, 0), n('t', 90, 0)],
          [e('s', 'm', 2), e('m', 't', 2), e('s', 't', 10)],
        ),
      ]);
      final route = const AStarRouter()
          .findRoute(g, from: 's', to: 't')
          .fold((r) => r, (f) => fail('$f'));
      expect(route.totalLengthM, 4);
      expect(route.nodeIds, ['s', 'm', 't']);
    });
  });

  group('structural issues', () {
    test('dangling edges are skipped, not fatal', () {
      final g = NavGraph.fromBundles([
        bundleOf('b1', [n('a', 0, 0)], [e('a', 'ghost', 5)]),
      ]);
      expect(
        g.issues.map((i) => i.kind),
        contains(GraphIssueKind.danglingEdge),
      );
      expect(g.node('a'), isNotNull);
    });

    test('orphan nodes are reported', () {
      final g = NavGraph.fromBundles([
        bundleOf('b1', [n('a', 0, 0), n('lonely', 5, 5)], [e('a', 'a', 0)]),
      ]);
      expect(
        g.issues.map((i) => i.detail),
        contains('lonely'),
      );
    });
  });
}
