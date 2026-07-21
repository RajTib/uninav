import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/domain/entities/geometry.dart';
import 'package:uninav/domain/services/geometry/polygon_utils.dart';

void main() {
  const square = [
    Point2(0, 0),
    Point2(10, 0),
    Point2(10, 10),
    Point2(0, 10),
  ];

  // L-shape: a 10x10 square with its top-right 5x5 quadrant removed.
  const lShape = [
    Point2(0, 0),
    Point2(5, 0),
    Point2(5, 5),
    Point2(10, 5),
    Point2(10, 10),
    Point2(0, 10),
  ];

  group('PolygonUtils.contains', () {
    test('center of a square is inside', () {
      expect(PolygonUtils.contains(square, const Point2(5, 5)), isTrue);
    });

    test('points outside are outside', () {
      expect(PolygonUtils.contains(square, const Point2(-1, 5)), isFalse);
      expect(PolygonUtils.contains(square, const Point2(5, 11)), isFalse);
      expect(PolygonUtils.contains(square, const Point2(20, 20)), isFalse);
    });

    test('concave polygon: the notch is outside, the arms are inside', () {
      expect(PolygonUtils.contains(lShape, const Point2(7.5, 2.5)), isFalse);
      expect(PolygonUtils.contains(lShape, const Point2(2.5, 2.5)), isTrue);
      expect(PolygonUtils.contains(lShape, const Point2(7.5, 7.5)), isTrue);
    });

    test('points on the boundary count as inside (tap tolerance)', () {
      expect(PolygonUtils.contains(square, const Point2(10, 5)), isTrue);
      expect(PolygonUtils.contains(square, const Point2(0, 0)), isTrue);
      expect(
        PolygonUtils.contains(square, const Point2(10.04, 5)),
        isTrue,
        reason: 'within default 5 cm tolerance',
      );
      expect(PolygonUtils.contains(square, const Point2(10.5, 5)), isFalse);
    });

    test('degenerate polygons never match', () {
      expect(PolygonUtils.contains(const [], const Point2(0, 0)), isFalse);
      expect(
        PolygonUtils.contains(
          const [Point2(0, 0), Point2(1, 1)],
          const Point2(0.5, 0.5),
        ),
        isFalse,
      );
    });
  });

  group('PolygonUtils.distanceToSegment', () {
    test('perpendicular distance in the middle', () {
      expect(
        PolygonUtils.distanceToSegment(
          const Point2(5, 3),
          const Point2(0, 0),
          const Point2(10, 0),
        ),
        closeTo(3, 1e-9),
      );
    });

    test('clamps to endpoints beyond the segment', () {
      expect(
        PolygonUtils.distanceToSegment(
          const Point2(13, 4),
          const Point2(0, 0),
          const Point2(10, 0),
        ),
        closeTo(5, 1e-9),
      );
    });

    test('zero-length segment degrades to point distance', () {
      expect(
        PolygonUtils.distanceToSegment(
          const Point2(3, 4),
          const Point2(0, 0),
          const Point2(0, 0),
        ),
        closeTo(5, 1e-9),
      );
    });
  });

  test('bounds', () {
    expect(PolygonUtils.bounds(lShape), [0, 0, 10, 10]);
    expect(PolygonUtils.bounds(const []), isNull);
  });
}
