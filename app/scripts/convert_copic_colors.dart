// Converts colors.json from meodai/copic-colors into the trimmed marker
// palette asset used by aMaze.
//
// Usage, from app/:
//   dart run scripts/convert_copic_colors.dart <path to colors.json>
//
// Keeps number (as code), name, hex and family, in the source order.
// Drops links, image references and extractedColor.
import 'dart:convert';
import 'dart:io';

const _source = 'meodai/copic-colors@b495dad1e26202534d48587bf271aa3c0247f215';
const _output = 'assets/palettes/copic_colors.json';
final _hex = RegExp(r'^#[0-9a-f]{6}$');

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run $_scriptName <colors.json>');
    exitCode = 64;
    return;
  }
  final entries = jsonDecode(File(args.single).readAsStringSync()) as List;
  final codes = <String>{};
  final colors = <Map<String, String>>[];
  for (final entry in entries.cast<Map<String, dynamic>>()) {
    final code = (entry['number'] as String).trim();
    final hex = (entry['hex'] as String).trim().toLowerCase();
    final family = entry['family'];
    final familyName = family is List ? family.first as String : family;
    if (!_hex.hasMatch(hex)) throw FormatException('Bad hex for $code: $hex');
    if (!codes.add(code)) throw FormatException('Duplicate code $code');
    colors.add({
      'code': code,
      'name': (entry['name'] as String).trim(),
      'hex': hex,
      'family': familyName as String,
    });
  }
  final lines = [for (final color in colors) '    ${jsonEncode(color)}'];
  final json =
      '{\n'
      '  "source": "$_source",\n'
      '  "license": "MIT",\n'
      '  "colors": [\n'
      '${lines.join(',\n')}\n'
      '  ]\n'
      '}\n';
  File(_output).writeAsStringSync(json);
  stdout.writeln('Wrote ${colors.length} colors to $_output');
}

const _scriptName = 'scripts/convert_copic_colors.dart';
