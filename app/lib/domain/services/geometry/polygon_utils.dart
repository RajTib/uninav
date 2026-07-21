import '../../entities/geometry.dart';

/// Pure geometric predicates used for map hit-testing. Lives in the domain
/// layer (no Flutter imports) so correctness is provable with plain VM tests
/// — the renderer only converts coordinates, it never decides geometry.
final class PolygonUtils {
  PolygonUtils._();

  /// Ray-casting point-in-polygon (even-odd rule). Works for concave
  /// polygons; self-intersecting polygons follow the even-odd convention.
  ///
  /// Points within [edgeToleranceM] of an edge count as inside, so taps on
  /// a shared wall between two rooms resolve to *a* room instead of neither
  /// (finger precision on a phone is far worse than any tolerance here).
  static bool contains(
    List<Point2> polygon,
    Point2 p, {
    double edgeToleranceM = 0.05,
  }) {
    if (polygon.length < 3) return false;

    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[j];
      final b = polygon[i];
      if (distanceToSegment(p, a, b) <= edgeToleranceM) return true;
      final crosses = (b.y > p.y) != (a.y > p.y) &&
          p.x < (a.x - b.x) * (p.y - b.y) / (a.y - b.y) + b.x;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  /// Shortest distance from [p] to segment [a]-[b].
  static double distanceToSegment(Point2 p, Point2 a, Point2 b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final lenSq = abx * abx + aby * aby;
    if (lenSq == 0) return p.distanceTo(a);
    var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq;
    t = t.clamp(0.0, 1.0);
    return p.distanceTo(Point2(a.x + t * abx, a.y + t * aby));
  }

  /// Axis-aligned bounds as [minX, minY, maxX, maxY]; null for empty input.
  static List<double>? bounds(List<Point2> polygon) {
    if (polygon.isEmpty) return null;
    var minX = polygon.first.x, minY = polygon.first.y;
    var maxX = minX, maxY = minY;
    for (final p in polygon) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return [minX, minY, maxX, maxY];
  }
}
