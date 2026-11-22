import 'package:butterfly/renderers/textures/texture.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Counts the lines drawn on it and ignores everything else.
class _CountingCanvas implements Canvas {
  int lines = 0;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (paint.color.a > 0 && paint.strokeWidth >= 0) lines++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('14: the Pattern fill default draws visible lines', () {
    final tool = ToolFamily.patternFill.defaultTool as TextureTool;
    final canvas = _CountingCanvas();
    drawSurfaceTextureOnCanvas(
      tool.texture,
      canvas,
      1,
      Offset.zero,
      const Size(400, 300),
      Offset.zero,
      false,
      1,
    );
    expect(canvas.lines, greaterThan(0));
  });

  test('the bare pattern default draws no lines', () {
    final canvas = _CountingCanvas();
    drawSurfaceTextureOnCanvas(
      const PatternTexture(),
      canvas,
      1,
      Offset.zero,
      const Size(400, 300),
      Offset.zero,
      false,
      1,
    );
    expect(canvas.lines, 0);
  });
}
