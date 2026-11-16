import 'dart:math';

import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:test/test.dart';

List<Point<double>> _points(PenElement element) =>
    element.points.map((p) => Point(p.x, p.y)).toList();

List<Point<double>> _corners(PenElement element) {
  final corners =
      (element.extra[kWallExtraKey] as Map)['corners'] as List<Object?>;
  final points = _points(element);
  return [for (final index in corners.cast<int>()) points[index]];
}

Matcher _near(Point<double> expected, [double tolerance = 0.01]) =>
    predicate<Point<double>>(
      (p) => (p - expected).magnitude <= tolerance,
      'within $tolerance of $expected',
    );

double _maxGap(PenElement element) {
  final points = _points(element);
  var result = 0.0;
  for (var i = 1; i < points.length; i++) {
    result = max(result, points[i].distanceTo(points[i - 1]));
  }
  return result;
}

const _color = SRGBColor(0xff374151);

void main() {
  test('makeWall reaches half the thickness past each end', () {
    final wall = makeWall(const Point(0, 0), const Point(960, 0), 4.5, _color);
    final corners = _corners(wall);
    expect(corners[0], _near(const Point(-216, -216)));
    expect(corners[1], _near(const Point(1176, -216)));
    expect(corners[2], _near(const Point(1176, 216)));
    expect(corners[3], _near(const Point(-216, 216)));
    expect(_maxGap(wall), lessThanOrEqualTo(6 + 1e-9));
    final points = _points(wall);
    expect(points.first, points.last);
    expect(wall.property.thinning, 0);
    expect(wall.property.smoothing, 0);
    expect(wall.property.streamline, 0);
    expect((wall.property.paint as SolidElementPaint).color.a, 0);
    expect((wall.property.fillPaint as SolidElementPaint).color, _color);
    expect((wall.extra[kWallExtraKey] as Map)['thicknessIn'], 4.5);
  });

  group('readWall', () {
    test('gives back the centerline and thickness', () {
      final wall = makeWall(
        const Point(100, 50),
        const Point(1060, 50),
        6,
        _color,
      );
      final geometry = readWall(wall)!;
      expect(geometry.a, _near(const Point(100, 50)));
      expect(geometry.b, _near(const Point(1060, 50)));
      expect(geometry.thicknessIn, closeTo(6, 1e-9));
    });

    test('still works after a quarter turn of the points', () {
      final wall = makeWall(
        const Point(0, 0),
        const Point(960, 0),
        4.5,
        _color,
      );
      final turned = wall.copyWith(
        points: [for (final p in wall.points) PathPoint(-p.y, p.x, p.pressure)],
      );
      final geometry = readWall(turned)!;
      expect(geometry.a, _near(const Point(0, 0)));
      expect(geometry.b, _near(const Point(0, 960)));
      expect(geometry.thicknessIn, closeTo(4.5, 1e-9));
    });

    test('is null once a corner is gone', () {
      final wall = makeWall(
        const Point(0, 0),
        const Point(960, 0),
        4.5,
        _color,
      );
      final corners = ((wall.extra[kWallExtraKey] as Map)['corners'] as List)
          .cast<int>();
      final points = [...wall.points]..removeAt(corners[2]);
      expect(readWall(wall.copyWith(points: points)), isNull);
      expect(readWall(PenElement(points: wall.points)), isNull);
    });
  });

  group('cutWall', () {
    // A 100 in centerline: the outline is 100 + 4.5 = 104.5 in long.
    final wall = makeWall(const Point(0, 0), const Point(9600, 0), 4.5, _color);
    const outlineIn = 104.5;
    double pieceLength(PenElement piece) {
      final corners = _corners(piece);
      return corners[0].distanceTo(corners[1]);
    }

    test('a cut in the middle leaves two valid walls', () {
      final pieces = cutWall(wall, 40, 70);
      expect(pieces, hasLength(2));
      expect(
        pieces.map(pieceLength).reduce((a, b) => a + b),
        closeTo((outlineIn - 30) * kCanvasUnitsPerInch, 1e-6),
      );
      for (final piece in pieces) {
        final geometry = readWall(piece)!;
        expect(geometry.thicknessIn, closeTo(4.5, 1e-9));
        expect((piece.property.fillPaint as SolidElementPaint).color, _color);
        expect(_maxGap(piece), lessThanOrEqualTo(6 + 1e-9));
      }
      // The cut sides are flat: the pieces end and start at the cut.
      expect(_corners(pieces.first)[1].x, closeTo(-216 + 40 * 96, 1e-6));
      expect(_corners(pieces.last)[0].x, closeTo(-216 + 70 * 96, 1e-6));
      expect(_corners(pieces.last)[1].x, closeTo(9600 + 216, 1e-6));
    });

    test('a cut at one end leaves one piece', () {
      expect(cutWall(wall, 0, 30), hasLength(1));
      expect(cutWall(wall, outlineIn - 30, outlineIn), hasLength(1));
      expect(cutWall(wall, 0, outlineIn), isEmpty);
    });
  });
}
