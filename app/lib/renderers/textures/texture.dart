import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:butterfly/helpers/xml.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:material_leap/material_leap.dart';
import 'package:xml/xml.dart';

part 'pattern.dart';

void drawSurfaceTextureOnCanvas(
  SurfaceTexture texture,
  Canvas canvas,
  double scale,
  Offset offset,
  Size size, [
  Offset translation = .zero,
  bool extraLines = false,
  double? zoom,
]) => switch (texture) {
  PatternTexture e => drawPatternTextureOnCanvas(
    e,
    canvas,
    scale,
    offset,
    size,
    translation,
    extraLines,
    zoom,
  ),
};

void drawSurfaceTextureOnSvg(
  SurfaceTexture texture,
  XmlDocument xml,
  Offset offset,
  Size size, [
  Offset translation = .zero,
  bool extraLines = false,
]) => switch (texture) {
  PatternTexture e => drawPatternTextureOnSvg(
    e,
    xml,
    offset,
    size,
    translation,
    extraLines,
  ),
};
