@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/entities/building_bundle.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';

import '../../tool/survey/floorplan_to_bundle.dart';

/// The JSON floor-plan pipeline (browser tracer -> bundle) must give the same
/// correctness guarantees as the text-DSL pipeline: a shape and its doorway
/// merge into one routable feature, a shape with two doorways stays internally
/// connected, and a bad file fails loudly rather than shipping a broken map.
///
/// One floor in the tracer's shape/point model:
///   * R1  classroom SHAPE + explicit doorway point (linked by `ref`)
///   * LJ  lift-junction SHAPE with TWO connection points (lift + stair
///         side) — also a walkable lobby, so it's a Room like any other
///         polygon shape, not just a graph node
///   * W1  washroom carrying both outline and point on one node (shared-id)
///   * G1  gallery SHAPE with NO point — a synthetic node is placed for it
Map<String, dynamic> _floorDoc() => {
      'building': 'SJT',
      'buildingName': 'Silver Jubilee Tower',
      'floor': 8,
      'image': {'file': 'f8.png', 'width': 500, 'height': 500},
      'corridorWidthM': 3.0,
      'corridors': [
        [
          [10, 10],
          [200, 10],
        ],
      ],
      'nodes': [
        {
          'id': 'R1',
          'kind': 'classroom',
          'displayName': 'Room 1',
          'aliases': ['1'],
          'polygon': [
            [10, 20],
            [60, 20],
            [60, 70],
            [10, 70],
          ],
        },
        {'id': 'R1_d', 'ref': 'R1', 'x': 35, 'y': 20},
        {
          'id': 'LJ',
          'kind': 'lift_junction',
          'displayName': 'Lift Junction',
          'polygon': [
            [90, 10],
            [130, 10],
            [130, 50],
            [90, 50],
          ],
        },
        {'id': 'LJ_l', 'ref': 'LJ', 'x': 100, 'y': 30},
        {'id': 'LJ_s', 'ref': 'LJ', 'x': 120, 'y': 30},
        {
          'id': 'W1',
          'kind': 'toilet_male',
          'displayName': "Men's Washroom",
          'polygon': [
            [160, 10],
            [200, 10],
            [200, 50],
            [160, 50],
          ],
          'x': 180,
          'y': 30,
        },
        {
          'id': 'G1',
          'kind': 'gallery',
          'displayName': 'Gallery',
          'polygon': [
            [220, 10],
            [300, 10],
            [300, 90],
            [220, 90],
          ],
        },
      ],
      'edges': [
        {'from': 'R1_d', 'to': 'LJ_l', 'weight': 10},
        {'from': 'LJ_s', 'to': 'W1', 'weight': 8},
        // Edge that names a SHAPE (G1) rather than a point — must resolve to
        // the synthetic node placed at the shape's centroid.
        {'from': 'W1', 'to': 'G1', 'weight': 12},
      ],
    };

void main() {
  group('floorplan_to_bundle shape/point model', () {
    test('merges shape + doorway, keeps counts, and is a valid bundle', () {
      final result = convert([_floorDoc()]);
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));

      final bundle = BuildingBundleDto.fromJson(result.bundle);
      expect(bundle.buildingName, 'Silver Jubilee Tower',
          reason: 'building name is data-driven, not hard-coded');

      // R1, W1, G1, LJ are all rooms — LJ (lift junction) is a walkable
      // lobby with its own traced outline, same as any other polygon shape.
      expect(
          bundle.rooms.map((r) => r.id), containsAll(['R1', 'W1', 'G1', 'LJ']));
      final ljRoom = bundle.roomById('LJ')!;
      expect(ljRoom.type, RoomType.junction);
      expect(ljRoom.polygon, isNotEmpty);
      // The room's routing node is its FIRST doorway point (lift side); the
      // second (stair side) stays reachable via the door edge asserted below.
      expect(ljRoom.nodeId, 'n_f8_LJ_l');

      // Shape's doorway point is the room's routing node.
      expect(bundle.roomById('R1')!.nodeId, 'n_f8_R1_d');
      expect(bundle.roomById('R1')!.polygon, isNotEmpty);

      // Washroom is also a POI so "nearest washroom" works.
      expect(bundle.pois.map((p) => p.id), contains('poi_W1'));

      // 4 points: R1_d, LJ_l, LJ_s, W1, plus one synthetic node for G1 = 5.
      expect(bundle.nodes.map((n) => n.id),
          containsAll(['n_f8_R1_d', 'n_f8_LJ_l', 'n_f8_LJ_s', 'n_f8_W1']));
      expect(bundle.nodes, hasLength(5));
    });

    test('a shape with two doorways stays internally connected', () {
      final bundle = BuildingBundleDto.fromJson(convert([_floorDoc()]).bundle);
      final door = bundle.edges.where((e) => e.kind == EdgeKind.door);
      expect(door, hasLength(1),
          reason: 'the two lift-junction points are joined by a door edge');
      final e = door.single;
      expect({e.a, e.b}, {'n_f8_LJ_l', 'n_f8_LJ_s'});
    });

    test('the generated graph is clean and routes end to end', () {
      final bundle = BuildingBundleDto.fromJson(convert([_floorDoc()]).bundle);
      final graph = NavGraph.fromBundles([bundle]);
      expect(graph.issues, isEmpty, reason: graph.issues.toString());

      final route = const AStarRouter()
          .findRoute(
            graph,
            from: bundle.roomById('R1')!.nodeId!,
            to: bundle.roomById('G1')!.nodeId!,
          )
          .fold((r) => r, (f) => fail('routing failed: $f'));
      expect(route.totalLengthM, greaterThan(0));
    });

    test('refuses a file with no edges instead of shipping a dead graph', () {
      final doc = _floorDoc()..['edges'] = <Map<String, dynamic>>[];
      final result = convert([doc]);
      expect(result.errors, isNotEmpty);
      expect(result.errors.join('\n'), contains('no usable edges'));
    });
  });
}
