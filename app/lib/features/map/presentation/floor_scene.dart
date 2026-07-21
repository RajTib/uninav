import 'dart:ui';

import '../../../domain/entities/building_bundle.dart';
import '../../../domain/entities/geometry.dart';
import '../../../domain/services/geometry/polygon_utils.dart';
import '../../../domain/services/routing/route.dart';

/// Immutable render model for one floor (docs/05-map-representation.md).
/// Built once per (bundle version, floor, route) and then painted many times:
/// all Path objects are pre-built here so painters allocate nothing per frame
/// (docs/11-performance.md). Coordinates are converted metres -> logical px
/// exactly once, at construction.
final class FloorScene {
  FloorScene._({
    required this.floor,
    required this.pxPerMeter,
    required this.rooms,
    required this.pois,
    required this.routePaths,
    required this.routeStart,
    required this.routeEnd,
    required this.transitionMarkers,
  });

  factory FloorScene.fromBundle(
    BuildingBundle bundle,
    String floorId, {
    NavRoute? route,
    double pxPerMeter = FloorScene.defaultPxPerMeter,
  }) {
    final floor = bundle.floorById(floorId);
    if (floor == null) {
      throw ArgumentError.value(floorId, 'floorId', 'not in bundle');
    }

    Offset toPx(Point2 p) => Offset(p.x * pxPerMeter, p.y * pxPerMeter);

    final rooms = [
      for (final room in bundle.rooms)
        if (room.floorId == floorId)
          SceneRoom(
            room: room,
            labelCenter: toPx(room.labelPoint),
            path: room.polygon.length >= 3
                ? (Path()
                  ..addPolygon(
                    room.polygon.map(toPx).toList(growable: false),
                    true,
                  ))
                : null,
          ),
    ];

    final pois = [
      for (final poi in bundle.pois)
        if (poi.floorId == floorId) ScenePoi(poi: poi, center: toPx(poi.point)),
    ];

    // Route overlay: only this floor's segments become paths; whether this
    // floor hosts the overall start/end is decided from the full route.
    final routePaths = <Path>[];
    Offset? routeStart;
    Offset? routeEnd;
    final markers = <TransitionMarker>[];
    if (route != null && route.segments.isNotEmpty) {
      for (final segment in route.segments) {
        if (segment.floorId != floorId || segment.points.length < 2) continue;
        final pts = segment.points.map(toPx).toList(growable: false);
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        routePaths.add(path);
      }
      if (route.segments.first.floorId == floorId) {
        routeStart = toPx(route.segments.first.points.first);
      }
      if (route.segments.last.floorId == floorId) {
        routeEnd = toPx(route.segments.last.points.last);
      }
      for (var i = 0; i < route.transitions.length; i++) {
        final t = route.transitions[i];
        if (t.fromFloorId == floorId) {
          // Departure marker sits at the end of the segment preceding the
          // transition (segments and transitions interleave 1:1).
          final seg = route.segments[i];
          markers.add(
            TransitionMarker(
              at: toPx(seg.points.last),
              transition: t,
              departing: true,
            ),
          );
        }
        if (t.toFloorId == floorId) {
          final seg = route.segments[i + 1];
          markers.add(
            TransitionMarker(
              at: toPx(seg.points.first),
              transition: t,
              departing: false,
            ),
          );
        }
      }
    }

    return FloorScene._(
      floor: floor,
      pxPerMeter: pxPerMeter,
      rooms: List.unmodifiable(rooms),
      pois: List.unmodifiable(pois),
      routePaths: List.unmodifiable(routePaths),
      routeStart: routeStart,
      routeEnd: routeEnd,
      transitionMarkers: List.unmodifiable(markers),
    );
  }

  /// 20 logical px per metre puts a 90 m building at 1800 px — comfortably
  /// pannable, and label text is readable at identity zoom.
  static const defaultPxPerMeter = 20.0;

  final Floor floor;
  final double pxPerMeter;
  final List<SceneRoom> rooms;
  final List<ScenePoi> pois;
  final List<Path> routePaths;
  final Offset? routeStart;
  final Offset? routeEnd;
  final List<TransitionMarker> transitionMarkers;

  Size get sizePx =>
      Size(floor.widthM * pxPerMeter, floor.heightM * pxPerMeter);

  /// Hit test in *metre* space (the domain's frame, not pixels): callers
  /// convert the tap offset once. Polygon rooms win over label-only rooms;
  /// label-only rooms match within a small radius of their label point.
  Room? roomAt(Point2 pMeters) {
    for (final sceneRoom in rooms) {
      final polygon = sceneRoom.room.polygon;
      if (polygon.length >= 3) {
        if (PolygonUtils.contains(polygon, pMeters)) return sceneRoom.room;
      } else if (sceneRoom.room.labelPoint.distanceTo(pMeters) <= 1.5) {
        return sceneRoom.room;
      }
    }
    return null;
  }
}

final class SceneRoom {
  const SceneRoom({
    required this.room,
    required this.labelCenter,
    required this.path,
  });

  final Room room;
  final Offset labelCenter;

  /// Null for rooms mapped without a polygon yet (label-only).
  final Path? path;
}

final class ScenePoi {
  const ScenePoi({required this.poi, required this.center});
  final Poi poi;
  final Offset center;
}

final class TransitionMarker {
  const TransitionMarker({
    required this.at,
    required this.transition,
    required this.departing,
  });

  final Offset at;
  final RouteTransition transition;

  /// True where the user leaves this floor, false where they arrive.
  final bool departing;
}
