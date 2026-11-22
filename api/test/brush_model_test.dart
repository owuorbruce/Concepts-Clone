import 'dart:convert';

import 'package:butterfly_api/butterfly_api.dart';
import 'package:test/test.dart';

void main() {
  test('0: brushById resolves versions', () {
    final catalog = BrushCatalog()
      ..register(const BrushDefinition(id: 'amaze.pen', version: 1, name: 'a'))
      ..register(const BrushDefinition(id: 'amaze.pen', version: 2, name: 'b'));
    expect(catalog.byId('amaze.pen', 3)?.version, 2);
    expect(catalog.byId('amaze.pen', 1)?.version, 1);
    expect(catalog.byId('amaze.pen')?.version, 2);
    expect(catalog.byId('unknown'), isNull);
  });

  test('1: PathPoint without extras keeps old JSON; with them round-trips', () {
    const old = PathPoint(1, 2, 0.5);
    expect(jsonEncode(old.toJson()), '{"x":1.0,"y":2.0,"pressure":0.5}');
    expect(PathPoint.fromJson({'x': 1.0, 'y': 2.0, 'pressure': 0.5}), old);
    const full = PathPoint(1, 2, 0.5, 0.7, 1.2, 345);
    final decoded = PathPoint.fromJson(
      jsonDecode(jsonEncode(full.toJson())) as Map<String, dynamic>,
    );
    expect(decoded, full);
    expect(decoded.tilt, 0.7);
    expect(decoded.azimuth, 1.2);
    expect(decoded.time, 345);
  });

  test('2: old pen JSON reads brush as empty and round-trips', () {
    const oldJson =
        '{"type":"pen","rotation":0.0,"shear":0.0,"collection":"",'
        '"id":"abc","points":[{"x":0.0,"y":0.0,"pressure":1.0},'
        '{"x":10.0,"y":5.0,"pressure":0.4}],"property":{"strokeWidth":5.0,'
        '"thinning":0.4,"paint":{"type":"solid","color":4278190080,"blur":0.0},'
        '"fillPaint":{"type":"solid","color":0,"blur":0.0},"smoothing":0.5,'
        '"streamline":0.3,"type":"pen"},"extra":{}}';
    final element = PadElement.fromJson(
      jsonDecode(oldJson) as Map<String, dynamic>,
    );
    final pen = element as PenElement;
    expect(pen.property.brush, '');
    expect(pen.property.brushVersion, 1);
    final reencoded = jsonEncode(element.toJson());
    final again = PadElement.fromJson(
      jsonDecode(reencoded) as Map<String, dynamic>,
    );
    expect(jsonEncode(again.toJson()), reencoded);
    expect(reencoded.contains('brush'), isFalse);
    expect(jsonDecode(reencoded)['property'], jsonDecode(oldJson)['property']);
    final brushed = pen.copyWith(
      property: pen.property.copyWith(brush: 'amaze.pen', brushVersion: 2),
    );
    final back = PadElement.fromJson(
      jsonDecode(jsonEncode(brushed.toJson())) as Map<String, dynamic>,
    ) as PenElement;
    expect(back.property.brush, 'amaze.pen');
    expect(back.property.brushVersion, 2);
  });

  test('3: BrushDefinition.fromJson fills every default', () {
    final def = BrushDefinition.fromJson({'id': 'x', 'engine': 'outline'});
    expect(def.id, 'x');
    expect(def.version, 1);
    expect(def.engine, BrushEngine.outline);
    expect(def.width, const BrushWidth());
    expect(def.width.pressureGamma, 1.0);
    expect(def.width.minRatio, 0.15);
    expect(def.width.speedSmoothing, 0.6);
    expect(def.nib.angleDeg, 45);
    expect(def.nib.aspect, 1.0);
    expect(def.taper, const BrushTaper());
    expect(def.dash, const BrushDash());
    expect(def.hairline, isFalse);
    expect(def.opacity.min, 1.0);
    expect(def.texture, '');
    expect(def.spacing, 0.1);
    expect(def.angleMode, BrushAngleMode.direction);
    expect(def.flow, 1);
    expect(def.buildUp, isTrue);
    expect(def.grain.scale, 1);
    expect(def.grain.strength, 0);
    expect(def.tiltShading, isFalse);
    expect(def.wetEdges, 0);
    expect(def.blend, BrushBlend.normal);
    expect(def.defaultSize, isNull);
    expect(def.defaultOpacity, isNull);
    expect(def.dynamics, isEmpty);
    final dyn = BrushDefinition.fromJson({
      'width': <String, dynamic>{},
      'dynamics': [
        {
          'input': 'speed',
          'output': 'opacity',
          'curve': [
            [0, 1],
            [1, 0.5],
          ],
        },
      ],
    });
    expect(dyn.width, const BrushWidth());
    expect(dyn.dynamics.single.curve.last, [1.0, 0.5]);
  });
}
