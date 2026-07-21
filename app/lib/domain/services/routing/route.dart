import '../../entities/geometry.dart';
import '../../entities/nav.dart';

/// A computed route, pre-split per floor so the renderer and the step list
/// consume it directly (docs/04-routing-engine.md §4).
final class NavRoute {
  const NavRoute({
    required this.nodeIds,
    required this.segments,
    required this.transitions,
    required this.totalLengthM,
    required this.estSeconds,
    required this.instructions,
  });

  final List<String> nodeIds;
  final List<RouteSegment> segments;
  final List<RouteTransition> transitions;
  final double totalLengthM;
  final int estSeconds;
  final List<RouteInstruction> instructions;
}

final class RouteSegment {
  const RouteSegment({
    required this.floorId,
    required this.points,
    required this.lengthM,
  });

  final String floorId;
  final List<Point2> points;
  final double lengthM;
}

final class RouteTransition {
  const RouteTransition({
    required this.kind,
    required this.fromFloorId,
    required this.toFloorId,
    required this.atNodeId,
  });

  final EdgeKind kind;
  final String fromFloorId;
  final String toFloorId;
  final String atNodeId;
}

final class RouteInstruction {
  const RouteInstruction({required this.kind, required this.text});

  final InstructionKind kind;

  /// English template text for now; replaced by l10n keys + args when i18n
  /// lands (the [kind] + structured fields exist so UI never parses text).
  final String text;
}

enum InstructionKind { start, walk, turnLeft, turnRight, floorChange, arrive }
