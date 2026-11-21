import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:butterfly/brushes/brush_paint.dart';
import 'package:butterfly/brushes/brush_registry.dart';
import 'package:butterfly/cubits/editor_runtime.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/services/asset.dart';
import 'package:butterfly/view_painter.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

BrushDefinition asset(String id) => BrushDefinition.fromJson(
  jsonDecode(File('assets/brushes/$id.v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

List<PathPoint> line(Offset a, Offset b, {double step = 2}) {
  final n = ((b - a).distance / step).ceil();
  return [
    for (var k = 0; k <= n; k++)
      () {
        final p = Offset.lerp(a, b, k / n)!;
        return PathPoint(p.dx, p.dy, 1);
      }(),
  ];
}

const red = SRGBColor(0xffdd0000);
const blue = SRGBColor(0xff0000dd);

PenElement pen(
  String id,
  List<PathPoint> points, {
  String brush = 'amaze.pen',
  SRGBColor color = red,
  double width = 20,
}) => PenElement(
  id: id,
  zoom: 1,
  points: points,
  property: PenProperty(
    brush: brush,
    strokeWidth: width,
    thinning: 0,
    paint: ElementPaint.solid(color: color),
  ),
);

PenElement across(String id, {SRGBColor color = red}) =>
    pen(id, line(const Offset(20, 100), const Offset(280, 100)), color: color);

PenElement hardMask(String id, {double opacity = 1}) => pen(
  id,
  line(const Offset(150, 20), const Offset(150, 180)),
  brush: 'amaze.hardMask',
  width: 30,
  color: SRGBColor(0xff000000).withValues(a: (opacity * 255).round()),
);

PenElement softMask(String id, {double opacity = 1}) => pen(
  id,
  line(const Offset(150, 20), const Offset(150, 180)),
  brush: 'amaze.softMask',
  width: 60,
  color: SRGBColor(0xff000000).withValues(a: (opacity * 255).round()),
);

Future<Renderer<PadElement>> setUp(PadElement element, String layer) async {
  final renderer = Renderer<PadElement>.fromInstance(element, layer);
  final transform = TransformCubit(1);
  await renderer.setup(
    transform,
    NoteData(Archive()),
    AssetService(),
    const DocumentPage(),
  );
  await transform.close();
  return renderer;
}

/// RGBA of [layers] (element, layer) painted as the canvas does, over a
/// white background when [background] is set.
Future<Uint8List> paint(
  List<(PadElement, String)> layers, {
  bool background = false,
}) async {
  final renderers = [for (final (e, l) in layers) await setUp(e, l)];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, 200),
      Paint()..color = const Color(0xffffffff),
    );
  }
  paintElementRenderers(
    canvas,
    const Size(300, 200),
    NoteData(Archive()),
    const DocumentPage(),
    DocumentInfo(),
    const CameraTransform(),
    renderers,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 200);
  final data = await image.toByteData();
  image.dispose();
  picture.dispose();
  for (final renderer in renderers) {
    renderer.dispose();
  }
  return data!.buffer.asUint8List();
}

List<int> pixel(Uint8List rgba, int x, int y) {
  final i = (y * 300 + x) * 4;
  return rgba.sublist(i, i + 4);
}

/// Counts save layers; everything else is ignored.
class _SaveLayerCounter implements Canvas {
  int saveLayers = 0;

  @override
  void saveLayer(Rect? bounds, Paint paint) => saveLayers++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final id in ['amaze.pen', 'amaze.hardMask', 'amaze.softMask']) {
      registerBrush(asset(id));
    }
    await loadBrushTextures();
  });

  test('the mask definitions are masks', () {
    expect(asset('amaze.hardMask').mask, isTrue);
    expect(asset('amaze.hardMask').engine, BrushEngine.outline);
    expect(asset('amaze.softMask').mask, isTrue);
    expect(asset('amaze.softMask').engine, BrushEngine.stamp);
    expect(asset('amaze.pen').mask, isFalse);
  });

  test('11: a hard mask hides the stroke under it, not next to it', () async {
    final rgba = await paint([(across('a'), 'l'), (hardMask('m'), 'l')]);
    expect(pixel(rgba, 150, 100)[3], 0);
    final beside = pixel(rgba, 60, 100);
    expect(beside[3], 255);
    expect(beside[0], greaterThan(200));
  });

  test('12: other layers and the background stay visible', () async {
    final rgba = await paint([
      (across('b', color: blue), 'other'),
      (across('a'), 'l'),
      (hardMask('m'), 'l'),
    ], background: true);
    final under = pixel(rgba, 150, 100);
    // The blue stroke on the other layer shows through the hole.
    expect(under[2], greaterThan(200));
    expect(under[0], lessThan(40));
    // Where the mask covers no stroke, the white background stays.
    expect(pixel(rgba, 150, 160), [255, 255, 255, 255]);
  });

  test('13: a stroke drawn after the mask is not hidden', () async {
    final rgba = await paint([(hardMask('m'), 'l'), (across('a'), 'l')]);
    expect(pixel(rgba, 150, 100)[3], 255);
  });

  test(
    '14: deleting the mask brings the stroke back, after a rebake',
    () async {
      final masked = await paint([(across('a'), 'l'), (hardMask('m'), 'l')]);
      expect(pixel(masked, 150, 100)[3], 0);
      final restored = await paint([(across('a'), 'l')]);
      expect(pixel(restored, 150, 100)[3], 255);
      // A new or changed mask is never drawn onto the cache incrementally.
      final mask = await setUp(hardMask('m'), 'l');
      final stroke = await setUp(across('a'), 'l');
      expect(bakeNeedsReset([stroke, mask]), isTrue);
      expect(bakeNeedsReset([stroke]), isFalse);
      expect(isMaskElement(mask.element), isTrue);
      expect(isMaskElement(stroke.element), isFalse);
    },
  );

  test(
    '15: a 30% soft mask fades by about 30%; two passes fade more',
    () async {
      final one = await paint([
        (across('a'), 'l'),
        (softMask('m', opacity: 0.3), 'l'),
      ]);
      final alpha = pixel(one, 150, 100)[3] / 255;
      expect(1 - alpha, closeTo(0.3, 0.05));
      final two = await paint([
        (across('a'), 'l'),
        (softMask('m1', opacity: 0.3), 'l'),
        (softMask('m2', opacity: 0.3), 'l'),
      ]);
      expect(pixel(two, 150, 100)[3] / 255, lessThan(alpha - 0.1));
      // Off the mask, nothing fades.
      expect(pixel(one, 40, 100)[3], 255);
    },
  );

  test('16: a layer without masks paints with no extra saveLayer', () async {
    final plain = [
      await setUp(across('a'), 'l'),
      await setUp(across('b'), 'l'),
    ];
    final counter = _SaveLayerCounter();
    paintElementRenderers(
      counter,
      const Size(300, 200),
      NoteData(Archive()),
      const DocumentPage(),
      DocumentInfo(),
      const CameraTransform(),
      plain,
    );
    expect(counter.saveLayers, 0);
    final masked = [...plain, await setUp(hardMask('m'), 'other')];
    final second = _SaveLayerCounter();
    paintElementRenderers(
      second,
      const Size(300, 200),
      NoteData(Archive()),
      const DocumentPage(),
      DocumentInfo(),
      const CameraTransform(),
      masked,
    );
    // One layer for the masked layer only; the plain layer stays direct.
    expect(second.saveLayers, 1);
  });

  test('SVG export embeds a masked layer as one image', () async {
    final renderers = [
      await setUp(across('a'), 'l'),
      await setUp(hardMask('m'), 'l'),
    ];
    final image = await renderMaskedLayer(
      renderers,
      NoteData(Archive()),
      const DocumentPage(),
      DocumentInfo(),
      pixelsPerUnit: 2,
    );
    expect(image, isNotNull);
    expect(image!.bounds.contains(const Offset(20, 100)), isTrue);
    expect(image.png.sublist(1, 4), utf8.encode('PNG'));
  });
}
