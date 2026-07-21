import 'geometry.dart';

/// Navigation graph primitives. Floor transitions are ordinary edges whose
/// endpoints sit on different floors — the router never special-cases floors
/// (docs/04-routing-engine.md §1).
final class NavNode {
  const NavNode({
    required this.id,
    required this.floorId,
    required this.point,
    required this.kind,
  });

  final String id;
  final String floorId;
  final Point2 point;
  final NodeKind kind;
}

enum NodeKind {
  room,
  corridor,
  junction,
  stair,
  elevator,
  ramp,
  entrance,
  exit,
}

final class NavEdge {
  const NavEdge({
    required this.a,
    required this.b,
    required this.kind,
    required this.lengthM,
    this.accessible = true,
    this.bidirectional = true,
  });

  final String a;
  final String b;
  final EdgeKind kind;

  /// Physical walking length in metres (for stairs: along the stair run).
  final double lengthM;

  /// False = unusable by wheelchair users (steps, narrow door...).
  final bool accessible;
  final bool bidirectional;
}

enum EdgeKind { corridor, door, stair, elevator, ramp, outdoor }
