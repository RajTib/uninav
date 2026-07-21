import '../../entities/nav.dart';
import 'nav_graph.dart';

/// Routing preferences expressed as edge-weight policy. All constants are
/// venue-independent behavioral tuning, not venue data
/// (docs/04-routing-engine.md §2).
final class RoutePrefs {
  const RoutePrefs._({
    required this.mode,
    required this.stairMultiplier,
    required this.stairPenaltyPerFloorM,
    required this.elevatorPenaltyM,
    required this.rampMultiplier,
    required this.excludeStairs,
    required this.excludeInaccessibleEdges,
  });

  /// Shortest walk; small elevator penalty models waiting time.
  static const fastest = RoutePrefs._(
    mode: RouteMode.fastest,
    stairMultiplier: 1,
    stairPenaltyPerFloorM: 5,
    elevatorPenaltyM: 15,
    rampMultiplier: 1.2,
    excludeStairs: false,
    excludeInaccessibleEdges: false,
  );

  /// Hard constraint: no stairs, no inaccessible edges. If no path exists the
  /// router reports it honestly instead of silently routing via stairs.
  static const accessible = RoutePrefs._(
    mode: RouteMode.accessible,
    stairMultiplier: 1,
    stairPenaltyPerFloorM: 0,
    elevatorPenaltyM: 5,
    rampMultiplier: 1,
    excludeStairs: true,
    excludeInaccessibleEdges: true,
  );

  /// Soft preference: stairs allowed but expensive (low stamina, luggage).
  static const preferLift = RoutePrefs._(
    mode: RouteMode.preferLift,
    stairMultiplier: 3,
    stairPenaltyPerFloorM: 5,
    elevatorPenaltyM: 5,
    rampMultiplier: 1,
    excludeStairs: false,
    excludeInaccessibleEdges: false,
  );

  final RouteMode mode;
  final double stairMultiplier;
  final double stairPenaltyPerFloorM;
  final double elevatorPenaltyM;
  final double rampMultiplier;
  final bool excludeStairs;
  final bool excludeInaccessibleEdges;

  /// Cost of traversing [arc] in metre-equivalents, or null if the edge is
  /// excluded under these preferences. Null (not infinity) so exclusion is
  /// explicit and un-summable by accident.
  ///
  /// Invariant relied on by the A* heuristic: cost >= physical length,
  /// because every multiplier is >= 1 and penalties are additive.
  double? arcCost(GraphArc arc) {
    final edge = arc.edge;
    if (excludeInaccessibleEdges && !edge.accessible) return null;
    return switch (edge.kind) {
      EdgeKind.stair => excludeStairs
          ? null
          : edge.lengthM * stairMultiplier +
              stairPenaltyPerFloorM * arc.floorsCrossed,
      EdgeKind.elevator => edge.lengthM + elevatorPenaltyM,
      EdgeKind.ramp => edge.lengthM * rampMultiplier,
      EdgeKind.corridor ||
      EdgeKind.door ||
      EdgeKind.outdoor =>
        edge.lengthM,
    };
  }
}

enum RouteMode { fastest, accessible, preferLift }
