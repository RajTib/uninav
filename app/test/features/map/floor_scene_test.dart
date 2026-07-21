import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/entities/building_bundle.dart';
import 'package:uninav/domain/entities/geometry.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';
import 'package:uninav/domain/services/routing/route.dart';
import 'package:uninav/features/map/presentation/floor_scene.dart';

void main() {
  late BuildingBundle bundle;
  late NavRoute crossFloorRoute; // r101 -> r202, via stairs (fastest)

  setUpAll(() {
    bundle = BuildingBundleDto.fromJson(
      jsonDecode(
        File('assets/campuses/demo/bundle_main.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final graph = NavGraph.fromBundles([bundle]);
    crossFloorRoute = const AStarRouter()
        .findRoute(graph, from: 'n_r101', to: 'n_r202')
        .fold((r) => r, (e) => fail('route failed: $e'));
  });

  group('FloorScene.fromBundle', () {
    test('collects only this floor content and converts to px', () {
      final scene = FloorScene.fromBundle(bundle, 'f0');
      expect(scene.rooms, hasLength(3));
      expect(scene.pois, hasLength(1));
      expect(scene.sizePx.width, 30 * FloorScene.defaultPxPerMeter);
      expect(scene.sizePx.height, 20 * FloorScene.defaultPxPerMeter);
      // 20 px/m: room 101's label at (5 m, 5 m) lands at (100, 100) px.
      final r101 =
          scene.rooms.singleWhere((r) => r.room.id == 'r101');
      expect(r101.labelCenter.dx, 100);
      expect(r101.labelCenter.dy, 100);
      expect(r101.path, isNotNull);
      expect(scene.routePaths, isEmpty);
      expect(scene.routeStart, isNull);
      expect(scene.routeEnd, isNull);
    });

    test('unknown floor throws (caller bug, not data)', () {
      expect(
        () => FloorScene.fromBundle(bundle, 'f99'),
        throwsArgumentError,
      );
    });

    test('splits a cross-floor route: start floor gets the departure', () {
      final scene =
          FloorScene.fromBundle(bundle, 'f0', route: crossFloorRoute);
      expect(scene.routePaths, hasLength(1));
      expect(scene.routeStart, isNotNull, reason: 'route starts on f0');
      expect(scene.routeEnd, isNull, reason: 'route ends on f1');
      final marker = scene.transitionMarkers.single;
      expect(marker.departing, isTrue);
      expect(marker.transition.kind, EdgeKind.stair);
      // Departure at the stair node n_s0 (28 m, 10 m) -> (560, 200) px.
      expect(marker.at.dx, closeTo(560, 1e-9));
      expect(marker.at.dy, closeTo(200, 1e-9));
    });

    test('splits a cross-floor route: end floor gets the arrival', () {
      final scene =
          FloorScene.fromBundle(bundle, 'f1', route: crossFloorRoute);
      expect(scene.routePaths, hasLength(1));
      expect(scene.routeStart, isNull);
      expect(scene.routeEnd, isNotNull);
      final marker = scene.transitionMarkers.single;
      expect(marker.departing, isFalse);
    });
  });

  group('FloorScene.roomAt (hit testing in metres)', () {
    test('hits a polygon room', () {
      final scene = FloorScene.fromBundle(bundle, 'f0');
      expect(scene.roomAt(const Point2(5, 5))?.id, 'r101');
      expect(scene.roomAt(const Point2(25, 5))?.id, 'r103');
    });

    test('misses the corridor', () {
      final scene = FloorScene.fromBundle(bundle, 'f0');
      expect(scene.roomAt(const Point2(10, 15)), isNull);
    });

    test('label-only rooms match near their label point', () {
      const labelOnly = BuildingBundle(
        schemaVersion: 1,
        buildingId: 'b',
        buildingName: 'B',
        version: 1,
        floors: [
          Floor(id: 'f0', level: 0, name: 'G', widthM: 20, heightM: 20),
        ],
        rooms: [
          Room(
            id: 'r1',
            floorId: 'f0',
            name: 'Unmapped Room',
            type: RoomType.other,
            labelPoint: Point2(10, 10),
          ),
        ],
        pois: [],
        nodes: [],
        edges: [],
      );
      final scene = FloorScene.fromBundle(labelOnly, 'f0');
      expect(scene.roomAt(const Point2(10.5, 10))?.id, 'r1');
      expect(scene.roomAt(const Point2(15, 10)), isNull);
    });
  });
}
