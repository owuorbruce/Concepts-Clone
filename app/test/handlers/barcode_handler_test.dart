import 'dart:math';
import 'dart:ui';

import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final element = SvgElement(
    source: 'data:image/svg+xml,barcode',
    width: 200,
    height: 100,
  );

  test('barcode placement preserves drag direction for flipping', () {
    final handler = BarcodeHandler(BarcodeTool());
    final transformed = BarcodeHandler.transformBarcodeElement(
      element,
      const Rect.fromLTRB(100, 80, 10, 20),
    );

    expect(handler.shouldNormalize, isFalse);
    expect(transformed.position, const Point(100, 80));
    expect(transformed.width, -90);
    expect(transformed.height, -60);
  });

  test('barcode placement only keeps its original size for a tap', () {
    final vertical = BarcodeHandler.transformBarcodeElement(
      element,
      const Rect.fromLTRB(100, 80, 100, 20),
    );
    final tapped = BarcodeHandler.transformBarcodeElement(
      element,
      const Rect.fromLTRB(100, 80, 100, 80),
    );

    expect(vertical.position, const Point(100, 80));
    expect(vertical.width, 0);
    expect(vertical.height, -60);
    expect(tapped.position, const Point(0, 30));
    expect(tapped.width, 200);
    expect(tapped.height, 100);
  });

  test('a new barcode scans: at least 200 px on screen at any zoom', () {
    for (final zoom in [0.1, 0.25, 1.0, 4.0]) {
      for (final type in BarcodeType.values) {
        final barcode = BarcodeHandler.buildBarcode(
          BarcodeTool(barcodeType: type),
          'aMaze',
          zoom: zoom,
        );
        expect(
          min(barcode.width, barcode.height) * zoom,
          greaterThanOrEqualTo(BarcodeHandler.minScreenSize - 1e-9),
          reason: '$type at $zoom',
        );
        // Its proportions stay those of its type.
        expect(
          barcode.width / barcode.height,
          closeTo(type.width / type.height, 1e-9),
        );
      }
    }
    // Zoomed in, it keeps its own size.
    final big = BarcodeHandler.buildBarcode(BarcodeTool(), 'x', zoom: 4);
    expect(big.width, BarcodeType.qrCode.width);
  });
}
