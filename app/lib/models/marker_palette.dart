import 'dart:convert';

import 'package:material_leap/material_leap.dart';

final _hexPattern = RegExp(r'^#[0-9a-f]{6}$');

/// One color of a marker reference palette.
///
/// [hex] is a digital approximation published for the marker, not a
/// measurement of the physical ink.
class MarkerColor {
  const MarkerColor({
    required this.code,
    required this.name,
    required this.hex,
    required this.family,
  });

  /// The marker's code, like `R29`.
  final String code;
  final String name;

  /// Lowercase `#rrggbb`.
  final String hex;

  /// The color family, like `R` or `YG`.
  final String family;

  /// The color, fully opaque.
  SRGBColor get color {
    return SRGBColor(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  bool operator ==(Object other) => other is MarkerColor && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'MarkerColor($code, $name, $hex)';
}

/// A list of marker colors with lookups by family, code and text.
class MarkerPalette {
  MarkerPalette(List<MarkerColor> colors)
    : colors = List.unmodifiable(colors),
      _byCode = {for (final color in colors) color.code.toLowerCase(): color};

  /// The colors in the order of the source data.
  final List<MarkerColor> colors;
  final Map<String, MarkerColor> _byCode;

  /// Parses a palette file: an object with a non-empty `colors` list of
  /// `code`, `name`, `hex` and `family` entries.
  ///
  /// Throws a [FormatException] if the JSON or its structure is invalid, a
  /// hex value is not `#rrggbb`, a code appears twice or the list is empty.
  factory MarkerPalette.parse(String json) {
    // Malformed JSON already throws a FormatException.
    final Object? data = jsonDecode(json);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('A marker palette must be a JSON object');
    }
    final entries = data['colors'];
    if (entries is! List) {
      throw const FormatException('A marker palette needs a colors list');
    }
    if (entries.isEmpty) {
      throw const FormatException('A marker palette needs at least one color');
    }
    final codes = <String>{};
    final colors = <MarkerColor>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw FormatException('Invalid marker color', entry);
      }
      String field(String key) {
        final value = entry[key];
        if (value is! String || value.isEmpty) {
          throw FormatException('Marker color needs a $key', entry);
        }
        return value;
      }

      final code = field('code');
      final hex = field('hex');
      if (!_hexPattern.hasMatch(hex)) {
        throw FormatException('Invalid hex for marker $code', hex);
      }
      if (!codes.add(code.toLowerCase())) {
        throw FormatException('Duplicate marker code', code);
      }
      colors.add(
        MarkerColor(
          code: code,
          name: field('name'),
          hex: hex,
          family: field('family'),
        ),
      );
    }
    return MarkerPalette(colors);
  }

  /// The families in the order they first appear.
  List<String> get families {
    final seen = <String>{};
    return [
      for (final color in colors)
        if (seen.add(color.family)) color.family,
    ];
  }

  List<MarkerColor> byFamily(String family) {
    return colors.where((color) => color.family == family).toList();
  }

  /// The color with exactly this [code], ignoring case.
  MarkerColor? byCode(String code) => _byCode[code.trim().toLowerCase()];

  /// Colors whose code or name contains [query], ignoring case.
  ///
  /// Codes that start with the query come first, then other code matches,
  /// then name matches; each group keeps the source order. An empty query
  /// returns every color.
  List<MarkerColor> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return colors;
    final prefix = <MarkerColor>[];
    final inCode = <MarkerColor>[];
    final inName = <MarkerColor>[];
    for (final color in colors) {
      final code = color.code.toLowerCase();
      if (code.startsWith(needle)) {
        prefix.add(color);
      } else if (code.contains(needle)) {
        inCode.add(color);
      } else if (color.name.toLowerCase().contains(needle)) {
        inName.add(color);
      }
    }
    return [...prefix, ...inCode, ...inName];
  }
}
