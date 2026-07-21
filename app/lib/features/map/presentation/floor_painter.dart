import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../domain/entities/building_bundle.dart';
import 'floor_scene.dart';

/// Visual style for the floor map, derived from the Material ColorScheme in
/// the widget layer so dark mode and high-contrast themes work with zero
/// painter changes (docs/05-map-representation.md).
final class MapStyle {
  const MapStyle({
    required this.floorFill,
    required this.floorOutline,
    required this.roomFills,
    required this.roomOutline,
    required this.selectedFill,
    required this.selectedOutline,
    required this.label,
    required this.poiFill,
    required this.poiGlyph,
    required this.route,
    required this.routeEnd,
  });

  factory MapStyle.fromScheme(ColorScheme scheme) => MapStyle(
        floorFill: scheme.surfaceContainerLowest,
        floorOutline: scheme.outline,
        roomFills: {
          RoomType.classroom: scheme.primaryContainer,
          RoomType.lab: scheme.tertiaryContainer,
          RoomType.office: scheme.secondaryContainer,
          RoomType.auditorium: scheme.primaryContainer,
          RoomType.library: scheme.tertiaryContainer,
          RoomType.washroom: scheme.surfaceContainerHighest,
          RoomType.cafeteria: scheme.secondaryContainer,
          RoomType.utility: scheme.surfaceContainerHigh,
          RoomType.other: scheme.surfaceContainerHigh,
        },
        roomOutline: scheme.outlineVariant,
        selectedFill: scheme.inversePrimary,
        selectedOutline: scheme.primary,
        label: scheme.onSurface,
        poiFill: scheme.secondary,
        poiGlyph: scheme.onSecondary,
        route: scheme.primary,
        routeEnd: scheme.error,
      );

  final Color floorFill;
  final Color floorOutline;
  final Map<RoomType, Color> roomFills;
  final Color roomOutline;
  final Color selectedFill;
  final Color selectedOutline;
  final Color label;
  final Color poiFill;
  final Color poiGlyph;
  final Color route;
  final Color routeEnd;
}

/// Paints the static floor: outline, room polygons, POI badges, labels.
/// Static content is a separate painter from the animated route overlay so
/// dash animation never forces room/label repaints.
final class FloorPainter extends CustomPainter {
  FloorPainter({
    required this.scene,
    required this.style,
    required this.selectedRoomId,
    required this.onRoomTap,
    required Listenable viewScale,
    required double Function() scaleOf,
  })  : _scaleOf = scaleOf,
        super(repaint: viewScale);

  final FloorScene scene;
  final MapStyle style;
  final String? selectedRoomId;
  final double Function() _scaleOf;

  /// Fired by a screen reader's double-tap-to-activate on a room's semantics
  /// node — the same selection [_MapScreenState._onTapUp] performs for a
  /// sighted tap, so both input paths land on identical app state.
  final void Function(Room room) onRoomTap;

  /// Labels below this on-screen scale are unreadable clutter; cull them
  /// (level-of-detail, docs/11-performance.md).
  static const _labelMinScale = 0.65;

  // Layout is the expensive part of text; cache per room id for this
  // painter's lifetime (painter is rebuilt when scene/selection change).
  final _labelCache = <String, TextPainter>{};

  @override
  void paint(Canvas canvas, Size size) {
    final floorRect = Offset.zero & scene.sizePx;
    canvas.drawRect(floorRect, Paint()..color = style.floorFill);
    canvas.drawRect(
      floorRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = style.floorOutline,
    );

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.roomOutline;
    final selectedOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = style.selectedOutline;

    for (final sceneRoom in scene.rooms) {
      final selected = sceneRoom.room.id == selectedRoomId;
      final path = sceneRoom.path;
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = selected
                ? style.selectedFill
                : (style.roomFills[sceneRoom.room.type] ??
                    style.roomFills[RoomType.other]!),
        );
        canvas.drawPath(path, selected ? selectedOutline : outline);
      } else {
        // Label-only room (no polygon mapped yet): a dot marks the spot.
        canvas.drawCircle(
          sceneRoom.labelCenter,
          selected ? 8 : 5,
          Paint()..color = selected ? style.selectedOutline : style.roomOutline,
        );
      }
    }

    for (final scenePoi in scene.pois) {
      canvas.drawCircle(scenePoi.center, 7, Paint()..color = style.poiFill);
      _paintGlyph(canvas, _poiIcon(scenePoi.poi.type), scenePoi.center, 9,
          style.poiGlyph,);
    }

    final showLabels = _scaleOf() >= _labelMinScale;
    for (final sceneRoom in scene.rooms) {
      final selected = sceneRoom.room.id == selectedRoomId;
      if (!showLabels && !selected) continue;
      final tp = _labelCache.putIfAbsent(sceneRoom.room.id, () {
        final painter = TextPainter(
          text: TextSpan(
            text: sceneRoom.room.name,
            style: TextStyle(
              color: style.label,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: 96);
        return painter;
      });
      tp.paint(
        canvas,
        sceneRoom.labelCenter - Offset(tp.width / 2, tp.height / 2),
      );
    }
  }

  void _paintGlyph(
      Canvas canvas, IconData icon, Offset center, double size, Color color,) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  IconData _poiIcon(PoiType type) => switch (type) {
        PoiType.washroom => Icons.wc,
        PoiType.waterCooler => Icons.water_drop,
        PoiType.printer => Icons.print,
        PoiType.atm => Icons.atm,
        PoiType.vending => Icons.storefront,
        PoiType.firstAid => Icons.medical_services,
        PoiType.entrance => Icons.login,
        PoiType.exit => Icons.logout,
        PoiType.other => Icons.place,
      };

  @override
  bool shouldRepaint(FloorPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.selectedRoomId != selectedRoomId ||
      oldDelegate.style != style;

  /// One semantics node per room so TalkBack/VoiceOver can reach the canvas
  /// content directly (docs/15-known-issues.md #4). The step list on the
  /// planner screen stays the primary accessible surface for *route* steps,
  /// but browsing/selecting a room from the map itself was previously
  /// screen-reader-invisible below the single summary label.
  @override
  SemanticsBuilderCallback get semanticsBuilder => _buildSemantics;

  List<CustomPainterSemantics> _buildSemantics(Size size) => [
        for (final sceneRoom in scene.rooms)
          CustomPainterSemantics(
            key: ValueKey(sceneRoom.room.id),
            rect: sceneRoom.path?.getBounds() ??
                Rect.fromCircle(center: sceneRoom.labelCenter, radius: 16),
            properties: SemanticsProperties(
              label: '${sceneRoom.room.name}, ${sceneRoom.room.type.name}',
              textDirection: TextDirection.ltr,
              button: true,
              selected: sceneRoom.room.id == selectedRoomId,
              onTap: () => onRoomTap(sceneRoom.room),
            ),
          ),
      ];
}

/// Animated route overlay: dashed polyline marching toward the destination,
/// start/end markers, and floor-transition badges. Repaints are driven only
/// by [animation] — the static layer underneath is untouched.
final class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.scene,
    required this.style,
    required this.animation,
  }) : super(repaint: animation);

  final FloorScene scene;
  final MapStyle style;
  final Animation<double> animation;

  static const _dashLength = 10.0;
  static const _gapLength = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.routePaths.isEmpty &&
        scene.routeStart == null &&
        scene.routeEnd == null) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = style.route;

    const period = _dashLength + _gapLength;
    final phase = animation.value * period;
    for (final path in scene.routePaths) {
      for (final metric in path.computeMetrics()) {
        var distance = -phase;
        while (distance < metric.length) {
          final start = distance.clamp(0.0, metric.length);
          final end = (distance + _dashLength).clamp(0.0, metric.length);
          if (end > start) {
            canvas.drawPath(metric.extractPath(start, end), paint);
          }
          distance += period;
        }
      }
    }

    for (final marker in scene.transitionMarkers) {
      // withAlpha instead of withValues: keeps the floor at Flutter >=3.22.
      canvas.drawCircle(
          marker.at, 10, Paint()..color = style.route.withAlpha(64),);
      canvas.drawCircle(marker.at, 7, Paint()..color = style.route);
    }
    final start = scene.routeStart;
    if (start != null) {
      canvas.drawCircle(start, 7, Paint()..color = style.route);
      canvas.drawCircle(start, 3.5, Paint()..color = Colors.white);
    }
    final end = scene.routeEnd;
    if (end != null) {
      canvas.drawCircle(end, 9, Paint()..color = style.routeEnd);
      canvas.drawCircle(end, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(RoutePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.style != style;
}
