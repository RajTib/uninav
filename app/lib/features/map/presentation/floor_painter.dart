import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../domain/entities/building_bundle.dart';
import '../../../domain/entities/nav.dart';
import 'floor_scene.dart';

/// Visual style for the floor map, derived from the Material ColorScheme in
/// the widget layer so dark mode and high-contrast themes work with zero
/// painter changes (docs/05-map-representation.md).
final class MapStyle {
  const MapStyle({
    required this.floorFill,
    required this.floorOutline,
    required this.corridor,
    required this.corridorEdge,
    required this.markerFill,
    required this.markerRing,
    required this.markerGlyph,
    required this.roomFills,
    required this.roomOutline,
    required this.selectedFill,
    required this.selectedOutline,
    required this.label,
    required this.labelHalo,
    required this.poiFill,
    required this.poiGlyph,
    required this.route,
    required this.routeEnd,
  });

  factory MapStyle.fromScheme(ColorScheme scheme) => MapStyle(
        floorFill: scheme.surfaceContainerLowest,
        floorOutline: scheme.outline,
        corridor: scheme.surfaceContainerHigh,
        corridorEdge: scheme.outlineVariant,
        markerFill: scheme.tertiary,
        markerRing: scheme.onTertiary,
        markerGlyph: scheme.onTertiary,
        roomFills: {
          RoomType.classroom: scheme.primaryContainer,
          RoomType.lab: scheme.tertiaryContainer,
          RoomType.office: scheme.secondaryContainer,
          RoomType.auditorium: scheme.primaryContainer,
          RoomType.library: scheme.tertiaryContainer,
          RoomType.washroom: scheme.surfaceContainerHighest,
          RoomType.cafeteria: scheme.secondaryContainer,
          RoomType.utility: scheme.surfaceContainerHigh,
          // Same fill as the corridor surface (below) — a lift/stair lobby
          // reads as an extension of the walkable floor, not a distinct room.
          RoomType.junction: scheme.surfaceContainerHigh,
          RoomType.other: scheme.surfaceContainerHigh,
        },
        roomOutline: scheme.outlineVariant,
        selectedFill: scheme.inversePrimary,
        selectedOutline: scheme.primary,
        label: scheme.onSurface,
        labelHalo: scheme.surface,
        poiFill: scheme.secondary,
        poiGlyph: scheme.onSecondary,
        route: scheme.primary,
        routeEnd: scheme.error,
      );

  final Color floorFill;
  final Color floorOutline;

  /// Corridor surface, and the darker casing drawn behind it that reads as
  /// the corridor walls.
  final Color corridor;
  final Color corridorEdge;

  /// Stairs/lift/entrance symbol badge colours.
  final Color markerFill;
  final Color markerRing;
  final Color markerGlyph;
  final Map<RoomType, Color> roomFills;
  final Color roomOutline;
  final Color selectedFill;
  final Color selectedOutline;
  final Color label;

  /// Stroke drawn behind label text so it stays readable on any room fill.
  final Color labelHalo;
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
    this.showGrid = false,
    required this.onRoomTap,
    required Listenable viewScale,
    required double Function() scaleOf,
  })  : _scaleOf = scaleOf,
        super(repaint: viewScale);

  final FloorScene scene;
  final MapStyle style;
  final String? selectedRoomId;

  /// Authoring aid: a coordinate grid labelled in the SAME units the survey
  /// file uses (plan pixels), so mispositioned rooms can be read off the
  /// screen and corrected by typing numbers instead of guessing. Wired to
  /// debug builds only — release users never see it.
  final bool showGrid;

  final double Function() _scaleOf;

  /// Fired by a screen reader's double-tap-to-activate on a room's semantics
  /// node — the same selection [_MapScreenState._onTapUp] performs for a
  /// sighted tap, so both input paths land on identical app state.
  final void Function(Room room) onRoomTap;

  /// Labels below this on-screen scale are unreadable clutter; cull them
  /// (level-of-detail, docs/11-performance.md).
  // Applies only to PIN rooms (fixed-size text). Polygon-room labels scale
  // with their room, so they stay legible at any zoom and are never culled.
  static const _labelMinScale = 0.25;

  // Layout is the expensive part of text; cache per room id for this
  // painter's lifetime (painter is rebuilt when scene/selection change).
  final _labelCache = <String, _RoomLabel>{};

  @override
  void paint(Canvas canvas, Size size) {
    // Deliberately NO full-floor background rectangle. The floor's declared
    // size comes from the plan image and is far larger than the mapped area,
    // so painting it produced an ocean of empty card around a small map.
    // Rooms and corridors define the building's shape against the app
    // background — the same visual grammar as Google Maps buildings.
    if (showGrid) _paintGrid(canvas);

    // Corridors first, underneath everything. These are the walkable edges
    // from the survey; drawing them is what turns scattered points into a
    // readable floor plan.
    // Corridors are painted as AREAS, not wires: a centreline stroked at the
    // real corridor width. Two passes — a darker casing, then a lighter fill
    // inset inside it — which is the standard map technique for making a
    // stroked path read as a walkable surface with walls rather than a line.
    final widthPx = scene.floor.corridorWidthM * scene.pxPerMeter;
    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = widthPx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = style.corridorEdge;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(widthPx - 3, 1)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = style.corridor;
    for (final paint in [casing, fill]) {
      for (final corridor in scene.corridors) {
        canvas.drawLine(corridor.a, corridor.b, paint);
      }
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
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
        // Label-only room: surveyed as a doorway point, with no traced
        // outline. Drawn as a proper map pin rather than a faint dot — these
        // are the primary content on a freshly surveyed floor, not an
        // afterthought, and at 5 px they read as specks of dust.
        final fill = selected
            ? style.selectedFill
            : (style.roomFills[sceneRoom.room.type] ??
                style.roomFills[RoomType.other]!);
        canvas
          ..drawCircle(
            sceneRoom.labelCenter,
            selected ? 15 : 11,
            Paint()..color = style.floorFill,
          )
          ..drawCircle(
            sceneRoom.labelCenter,
            selected ? 13 : 9,
            Paint()..color = fill,
          )
          ..drawCircle(
            sceneRoom.labelCenter,
            selected ? 13 : 9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected ? 3 : 2
              ..color = selected ? style.selectedOutline : style.roomOutline,
          );
      }
    }

    for (final scenePoi in scene.pois) {
      canvas.drawCircle(scenePoi.center,32, Paint()..color = style.poiFill);
      _paintGlyph(canvas, _poiIcon(scenePoi.poi.type), scenePoi.center, 48,
          style.poiGlyph,);
    }

    // Stairs / lift / entrance symbols — larger than POIs because these are
    // primary navigation landmarks ("take the lift", "meet at the stairs").
    for (final marker in scene.markers) {
      canvas.drawCircle(marker.center, 36, Paint()..color = style.markerFill);
      canvas.drawCircle(
        marker.center,
        36,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = style.markerRing,
      );
      _paintGlyph(canvas, _markerIcon(marker.kind), marker.center, 64,
          style.markerGlyph,);
    }

    // ---- Labels ----------------------------------------------------------
    // The old scheme drew every label at a fixed 11 px in SCENE space. Rooms
    // are hundreds of scene px wide, so once the camera zooms out to fit the
    // floor, boxes stay big while text shrinks to an unreadable smudge.
    // Fix: labels are sized to FIT THEIR ROOM (like any real map), using the
    // room's shortest name ("801", not "Classroom 801") — the full name
    // belongs on the tap card, not the map. A surface-coloured halo keeps
    // text readable on every fill colour and in dark mode.
    final pinLabels = _scaleOf() >= _labelMinScale;
    for (final sceneRoom in scene.rooms) {
      final selected = sceneRoom.room.id == selectedRoomId;
      final path = sceneRoom.path;
      if (path == null && !pinLabels && !selected) continue;

      final label = _labelCache.putIfAbsent(
        sceneRoom.room.id,
        () => _layoutLabel(sceneRoom),
      );
      final anchor = path != null
          ? sceneRoom.labelCenter -
              Offset(label.fill.width / 2, label.fill.height / 2)
          : sceneRoom.labelCenter + Offset(-label.fill.width / 2, 14);
      label.halo.paint(canvas, anchor);
      label.fill.paint(canvas, anchor);
    }
  }

  /// Shortest way to say which room this is: prefer a compact alias like
  /// "801" over "Classroom 801". Map labels identify; cards describe.
  static String _shortName(Room room) {
    switch (room.type) {
      case RoomType.washroom:
        return room.name;

      case RoomType.auditorium:
        return room.name;

      default:
        final options = [room.name, ...room.aliases]
          ..removeWhere((s) => s.trim().isEmpty)
          ..sort((a, b) => a.length.compareTo(b.length));
        return options.first;
    }
  }

  _RoomLabel _layoutLabel(SceneRoom sceneRoom) {
    final path = sceneRoom.path;
    final text = _shortName(sceneRoom.room);

    // Pin rooms keep a fixed size; polygon rooms get text scaled to the box.
    var fontSize = 12.0;
    var maxWidth = 120.0;
    if (path != null) {
      final bounds = path.getBounds();
      // Scale with the room, clamped so tiny rooms stay legible and halls
      // don't shout. 0.28 × the room's smaller side reads well in practice.
      fontSize =
          (math.min(bounds.width, bounds.height) * 0.28).clamp(13.0, 44.0);
      maxWidth = bounds.width * 0.9;
    }

    TextPainter build(TextStyle textStyle) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      return tp;
    }

    final base = TextStyle(
      color: style.label,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    var fill = build(base);
    // If it still overflows its room, shrink once to fit.
    if (path != null && fill.width > maxWidth && fontSize > 13) {
      final shrunk = (fontSize * maxWidth / fill.width).clamp(11.0, fontSize);
      fill = build(base.copyWith(fontSize: shrunk));
    }
    final halo = TextPainter(
      text: TextSpan(
        text: text,
        style: (fill.text! as TextSpan).style!.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5
                ..color = style.labelHalo,
            ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return _RoomLabel(fill: fill, halo: halo);
  }

  /// Grid in plan-pixel coordinates. Every 50 source px is a light line,
  /// every 100 is a brighter labelled one — so a room drawn in the wrong
  /// place can be read straight off the screen ("that box starts at 380,
  /// should be 300") and fixed in the survey file.
  void _paintGrid(Canvas canvas) {
    // Source pixels per SCENE pixel. Without a recorded plan scale, fall
    // back to labelling in metres rather than drawing nothing.
    final srcPerMetre = scene.floor.sourcePxPerMetre;
    final step = srcPerMetre == null ? 10.0 : 50.0; // metres : source px
    final sceneStep =
        srcPerMetre == null ? step * scene.pxPerMeter : step / srcPerMetre * scene.pxPerMeter;
    if (sceneStep < 4) return; // pathological scale; don't hang on a huge loop

    final size = scene.sizePx;
    final minor = Paint()
      ..strokeWidth = 1
      ..color = style.label.withAlpha(28);
    final major = Paint()
      ..strokeWidth = 1
      ..color = style.label.withAlpha(64);

    var i = 0;
    for (var x = 0.0; x <= size.width; x += sceneStep, i++) {
      final isMajor = i % 2 == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          isMajor ? major : minor,);
      if (isMajor) _paintGridLabel(canvas, '${(i * step).round()}', Offset(x + 3, 3));
    }
    i = 0;
    for (var y = 0.0; y <= size.height; y += sceneStep, i++) {
      final isMajor = i % 2 == 0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          isMajor ? major : minor,);
      if (isMajor && i > 0) {
        _paintGridLabel(canvas, '${(i * step).round()}', Offset(3, y + 3));
      }
    }
  }

  void _paintGridLabel(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: style.label.withAlpha(140), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
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

  IconData _markerIcon(NodeKind kind) => switch (kind) {
        NodeKind.stair => Icons.stairs,
        NodeKind.elevator => Icons.elevator,
        NodeKind.ramp => Icons.accessible_forward,
        NodeKind.entrance => Icons.login,
        NodeKind.exit => Icons.logout,
        _ => Icons.circle,
      };

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
      oldDelegate.style != style ||
      oldDelegate.showGrid != showGrid;

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

/// A room label laid out once and painted many times: the fill text plus a
/// surface-coloured stroke behind it for contrast on any fill colour.
final class _RoomLabel {
  const _RoomLabel({required this.fill, required this.halo});
  final TextPainter fill;
  final TextPainter halo;
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
