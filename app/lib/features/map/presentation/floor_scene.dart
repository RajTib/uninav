import 'dart:ui';

import '../../../domain/entities/building_bundle.dart';
import '../../../domain/entities/geometry.dart';
import '../../../domain/entities/nav.dart';
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
    required this.markers,
    required this.corridors,
    required this.contentBounds,
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

    // Vertical-transport nodes get a proper map symbol (stairs / lift icon)
    // instead of an anonymous dot. These are the landmarks people navigate by
    // ("meet me at the lift"), so they must read at a glance.
    final markers = [
      for (final node in bundle.nodes)
        if (node.floorId == floorId &&
            const {
              NodeKind.stair,
              NodeKind.elevator,
              NodeKind.ramp,
              NodeKind.entrance,
              NodeKind.exit,
            }.contains(node.kind))
          SceneMarker(kind: node.kind, center: toPx(node.point)),
    ];

    // The walkable graph, drawn as corridor lines. Without these the map is
    // just disconnected dots floating in space — the edges are what make it
    // read as a floor plan. They are already in the data (routing uses them);
    // this simply makes them visible.
    final nodePos = <String, Offset>{
      for (final node in bundle.nodes)
        if (node.floorId == floorId) node.id: toPx(node.point),
    };
    final corridors = <SceneCorridor>[];
    if (floor.corridors.isNotEmpty) {
      // Traced corridor shapes: use them, and do NOT also draw graph edges.
      // A graph edge says "A connects to B in N steps" — drawn literally it
      // becomes a straight line that can cut diagonally across the building.
      // The traced polyline is what the corridor actually looks like.
      for (final path in floor.corridors) {
        for (var i = 1; i < path.length; i++) {
          corridors.add(
            SceneCorridor(a: toPx(path[i - 1]), b: toPx(path[i]), edge: null),
          );
        }
      }
    } else {
      // Not traced yet: fall back to drawing the graph, which is at least
      // topologically honest even where it isn't geometrically pretty.
      for (final edge in bundle.edges) {
        final a = nodePos[edge.a];
        final b = nodePos[edge.b];
        // Skip edges leaving this floor (stairs/lifts): their endpoints live
        // on another floor and a line to nowhere would be meaningless.
        if (a == null || b == null) continue;
        corridors.add(SceneCorridor(a: a, b: b, edge: edge));
      }
    }

    // Bounds of everything actually drawn. A floor's declared size comes from
    // its plan image, which is usually far larger than the surveyed area — so
    // fitting the camera to the floor leaves the content as a small clump in
    // an ocean of empty canvas. Fitting to *content* is what users expect.
    final drawn = <Offset>[
      ...nodePos.values,
      for (final r in rooms) r.labelCenter,
      for (final p in pois) p.center,
    ];
    final contentBounds = drawn.isEmpty
        ? (Offset.zero & Size(floor.widthM * pxPerMeter, floor.heightM * pxPerMeter))
        : _boundsOf(drawn).inflate(6 * pxPerMeter);

    // Route overlay: only this floor's segments become paths; whether this
    // floor hosts the overall start/end is decided from the full route.
    final routePaths = <Path>[];
    Offset? routeStart;
    Offset? routeEnd;
    final transitionMarkers = <TransitionMarker>[];
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
          transitionMarkers.add(
            TransitionMarker(
              at: toPx(seg.points.last),
              transition: t,
              departing: true,
            ),
          );
        }
        if (t.toFloorId == floorId) {
          final seg = route.segments[i + 1];
          transitionMarkers.add(
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
      markers: List.unmodifiable(markers),
      corridors: List.unmodifiable(corridors),
      contentBounds: contentBounds,
      routePaths: List.unmodifiable(routePaths),
      routeStart: routeStart,
      routeEnd: routeEnd,
      transitionMarkers: List.unmodifiable(transitionMarkers),
    );
  }

  /// 20 logical px per metre puts a 90 m building at 1800 px — comfortably
  /// pannable, and label text is readable at identity zoom.
  static const defaultPxPerMeter = 20.0;

  final Floor floor;
  final double pxPerMeter;
  final List<SceneRoom> rooms;
  final List<ScenePoi> pois;

  /// Stairs, lifts, ramps and entrances — drawn as map symbols.
  final List<SceneMarker> markers;

  /// Walkable graph edges on this floor, drawn as corridor lines.
  final List<SceneCorridor> corridors;

  /// Rectangle enclosing everything drawn, plus padding. The camera fits to
  /// this rather than to [sizePx] — see the comment at the construction site.
  final Rect contentBounds;

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

Rect _boundsOf(List<Offset> points) {
  var minX = points.first.dx, maxX = minX;
  var minY = points.first.dy, maxY = minY;
  for (final p in points) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// One walkable connection, ready to draw.
final class SceneCorridor {
  const SceneCorridor({required this.a, required this.b, this.edge});
  final Offset a;
  final Offset b;

  /// The graph edge this segment came from, when corridors were derived from
  /// the graph. Null for traced corridor shapes, which have no single edge.
  final NavEdge? edge;
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

/// A vertical-transport or entrance node, drawn with a kind-specific icon.
final class SceneMarker {
  const SceneMarker({required this.kind, required this.center});
  final NodeKind kind;
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
