import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/core/error/failure.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';
import 'package:uninav/domain/services/routing/route_prefs.dart';

void main() {
  const router = AStarRouter();
  late NavGraph graph;

  setUpAll(() {
    final bundle = BuildingBundleDto.fromJson(
      jsonDecode(
        File('assets/campuses/demo/bundle_main.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    graph = NavGraph.fromBundles([bundle]);
  });

  group('findNearestRoute', () {
    test('finds the washroom from a ground-floor room', () {
      // From Room 102: n_r102 -> n_c1 (5) -> n_wc0 (5.5) = 10.5 m.
      final route = router
          .findNearestRoute(graph, from: 'n_r102', goals: {'n_wc0'})
          .fold((r) => r, (e) => fail('$e'));
      expect(route.totalLengthM, closeTo(10.5, 1e-9));
      expect(route.nodeIds.last, 'n_wc0');
    });

    test('picks the nearest of several goals', () {
      // From n_c3: r103 door (5 m) vs r101 (via c1, c2: 25 m).
      final route = router.findNearestRoute(
        graph,
        from: 'n_c3',
        goals: {'n_r101', 'n_r103'},
      ).fold((r) => r, (e) => fail('$e'));
      expect(route.nodeIds.last, 'n_r103');
      expect(route.totalLengthM, 5);
    });

    test('start already at a goal yields a zero-length route', () {
      final route = router
          .findNearestRoute(graph, from: 'n_wc0', goals: {'n_wc0'})
          .fold((r) => r, (e) => fail('$e'));
      expect(route.totalLengthM, 0);
    });

    test('cross-floor nearest works (washroom is on the ground floor)', () {
      final route = router
          .findNearestRoute(graph, from: 'n_r201', goals: {'n_wc0'})
          .fold((r) => r, (e) => fail('$e'));
      expect(route.transitions, hasLength(1));
      expect(route.nodeIds.last, 'n_wc0');
    });

    test('unknown goals fail with nodeMissing', () {
      final failure = router
          .findNearestRoute(graph, from: 'n_r101', goals: {'nope'})
          .fold((r) => fail('expected failure'), (e) => e);
      expect(failure.reason, RoutingFailureReason.nodeMissing);
    });

    test('accessible mode honors constraints on the way to the goal', () {
      // Any route from f1 to the f0 washroom in accessible mode must use
      // the lift, never the stairs.
      final route = router
          .findNearestRoute(
            graph,
            from: 'n_r201',
            goals: {'n_wc0'},
            prefs: RoutePrefs.accessible,
          )
          .fold((r) => r, (e) => fail('$e'));
      expect(route.nodeIds, contains('n_l1'));
      expect(route.nodeIds, isNot(contains('n_s1')));
    });
  });
}
