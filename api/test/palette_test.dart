import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:test/test.dart';

/// Builds big-endian binary fixtures.
class _Bytes {
  final _builder = BytesBuilder();

  void ascii(String value) => _builder.add(value.codeUnits);

  void uint16(int value) {
    final data = ByteData(2)..setUint16(0, value);
    _builder.add(data.buffer.asUint8List());
  }

  void uint32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    _builder.add(data.buffer.asUint8List());
  }

  void float32(double value) {
    final data = ByteData(4)..setFloat32(0, value);
    _builder.add(data.buffer.asUint8List());
  }

  void utf16(String value) {
    for (final unit in value.codeUnits) {
      uint16(unit);
    }
    uint16(0);
  }

  void bytes(Uint8List value) => _builder.add(value);

  Uint8List toBytes() => _builder.toBytes();
}

Uint8List _text(String value) => Uint8List.fromList(utf8.encode(value));

List<int> _colors(NamedItem<ColorPalette> palette) {
  return palette.item.colors.map((e) => e.value).toList();
}

Uint8List _aseColor(String name, String model, List<double> values) {
  final block = _Bytes()
    ..uint16(name.length + 1)
    ..utf16(name)
    ..ascii(model);
  for (final value in values) {
    block.float32(value);
  }
  block.uint16(2);
  final bytes = block.toBytes();
  final entry = _Bytes()
    ..uint16(0x0001)
    ..uint32(bytes.length)
    ..bytes(bytes);
  return entry.toBytes();
}

Uint8List _aseGroupStart(String name) {
  final block = _Bytes()
    ..uint16(name.length + 1)
    ..utf16(name);
  final bytes = block.toBytes();
  final entry = _Bytes()
    ..uint16(0xC001)
    ..uint32(bytes.length)
    ..bytes(bytes);
  return entry.toBytes();
}

Uint8List _aseGroupEnd() {
  final entry = _Bytes()
    ..uint16(0xC002)
    ..uint32(0);
  return entry.toBytes();
}

Uint8List _ase(List<Uint8List> blocks) {
  final file = _Bytes()
    ..ascii('ASEF')
    ..uint16(1)
    ..uint16(0)
    ..uint32(blocks.length);
  for (final block in blocks) {
    file.bytes(block);
  }
  return file.toBytes();
}

void _acoColor(_Bytes file, int space, List<int> values, [String? name]) {
  file.uint16(space);
  for (final value in [...values, 0, 0, 0, 0].take(4)) {
    file.uint16(value);
  }
  if (name == null) return;
  file.uint32(name.length + 1);
  file.utf16(name);
}

Uint8List _procreate(Object json) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('Swatches.json', jsonEncode(json)));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('gpl', () {
    test('reads name, colors and skips headers and comments', () {
      final data = _text('''GIMP Palette
Name: Earth tones
Columns: 4
# comment
255   0   0	Red
  0 128 255
not a color
''');
      final palettes = importPaletteFile(
        data,
        fileExtension: 'GPL',
        name: 'file',
      );
      expect(palettes, hasLength(1));
      expect(palettes.single.name, 'Earth tones');
      expect(_colors(palettes.single), [0xFFFF0000, 0xFF0080FF]);
    });

    test('reads RGBA palettes and clamps values', () {
      final data = _text('GIMP Palette\nChannels: RGBA\n300 0 0 128 Red\n');
      final palettes = importPaletteFile(
        data,
        fileExtension: 'gpl',
        name: 'file',
      );
      expect(palettes.single.name, 'file');
      expect(_colors(palettes.single), [0x80FF0000]);
    });

    test('rejects files without the GIMP header', () {
      expect(
        () => importPaletteFile(
          _text('255 0 0\n'),
          fileExtension: 'gpl',
          name: 'file',
        ),
        throwsFormatException,
      );
    });
  });

  group('hex lists', () {
    test('reads Lospec hex files as RRGGBB[AA]', () {
      final data = _text('ff0000\n#00FF00\nFF000080\n');
      final palettes = importPaletteFile(
        data,
        fileExtension: 'hex',
        name: 'lospec',
      );
      expect(_colors(palettes.single), [0xFFFF0000, 0xFF00FF00, 0x80FF0000]);
    });

    test('reads Paint.NET palettes as AARRGGBB with comments', () {
      final data = _text('; paint.net Palette File\n; FFFFFFFF\n80FF0000\n');
      final palettes = importPaletteFile(
        data,
        fileExtension: 'txt',
        name: 'paint',
      );
      expect(_colors(palettes.single), [0x80FF0000]);
    });
  });

  group('ase', () {
    test('reads ungrouped colors and groups as separate palettes', () {
      final data = _ase([
        _aseColor('Red', 'RGB ', [1, 0, 0]),
        _aseGroupStart('Brand / 2026'),
        _aseColor('Cmyk red', 'CMYK', [0, 1, 1, 0]),
        _aseColor('White', 'LAB ', [1, 0, 0]),
        _aseColor('Gray', 'Gray', [0.5]),
        _aseGroupEnd(),
        _aseColor('Blue', 'RGB ', [0, 0, 1]),
      ]);
      final palettes = importPaletteFile(
        data,
        fileExtension: 'ase',
        name: 'swatches',
      );
      expect(palettes.map((e) => e.name), ['swatches', 'Brand - 2026']);
      expect(_colors(palettes[0]), [0xFFFF0000, 0xFF0000FF]);
      expect(_colors(palettes[1]), [0xFFFF0000, 0xFFFFFFFF, 0xFF808080]);
    });

    test('drops the empty ungrouped palette', () {
      final data = _ase([
        _aseGroupStart('Only'),
        _aseColor('Red', 'RGB ', [1, 0, 0]),
        _aseGroupEnd(),
      ]);
      final palettes = importPaletteFile(
        data,
        fileExtension: 'ase',
        name: 'swatches',
      );
      expect(palettes.map((e) => e.name), ['Only']);
    });

    test('rejects bad magic and truncated files', () {
      expect(
        () =>
            importPaletteFile(_text('NOPE'), fileExtension: 'ase', name: 'bad'),
        throwsFormatException,
      );
      final valid = _ase([
        _aseColor('Red', 'RGB ', [1, 0, 0]),
      ]);
      final truncated = Uint8List.sublistView(valid, 0, valid.length - 6);
      expect(
        () => importPaletteFile(truncated, fileExtension: 'ase', name: 'x'),
        throwsFormatException,
      );
    });
  });

  group('aco', () {
    test('reads version 1 color spaces', () {
      final file = _Bytes()
        ..uint16(1)
        ..uint16(5);
      _acoColor(file, 0, [65535, 0, 0]);
      _acoColor(file, 1, [0, 65535, 32768]);
      _acoColor(file, 2, [0, 65535, 65535, 65535]);
      _acoColor(file, 7, [5000, 0, 0]);
      _acoColor(file, 8, [0]);
      final palettes = importPaletteFile(
        file.toBytes(),
        fileExtension: 'aco',
        name: 'photoshop',
      );
      expect(_colors(palettes.single), [
        0xFFFF0000,
        0xFF800000,
        0xFF00FFFF,
        0xFF777777,
        0xFFFFFFFF,
      ]);
    });

    test('prefers the named version 2 section', () {
      final file = _Bytes()
        ..uint16(1)
        ..uint16(1);
      _acoColor(file, 0, [65535, 0, 0]);
      file
        ..uint16(2)
        ..uint16(1);
      _acoColor(file, 0, [0, 0, 65535], 'Blue');
      final palettes = importPaletteFile(
        file.toBytes(),
        fileExtension: 'aco',
        name: 'photoshop',
      );
      expect(_colors(palettes.single), [0xFF0000FF]);
    });

    test('rejects unknown versions and empty files', () {
      final unknown = _Bytes()..uint16(9);
      expect(
        () => importPaletteFile(
          unknown.toBytes(),
          fileExtension: 'aco',
          name: 'x',
        ),
        throwsFormatException,
      );
      expect(
        () => importPaletteFile(Uint8List(0), fileExtension: 'aco', name: 'x'),
        throwsFormatException,
      );
    });
  });

  group('procreate', () {
    test('reads HSB swatches and skips empty slots', () {
      final data = _procreate([
        {
          'name': 'Sketch',
          'swatches': [
            {'hue': 0, 'saturation': 1, 'brightness': 1, 'alpha': 1},
            null,
            {'hue': 0.5, 'saturation': 1, 'brightness': 1, 'alpha': 0.5},
          ],
        },
      ]);
      final palettes = importPaletteFile(
        data,
        fileExtension: 'swatches',
        name: 'file',
      );
      expect(palettes.single.name, 'Sketch');
      expect(_colors(palettes.single), [0xFFFF0000, 0x8000FFFF]);
    });

    test('rejects files that are not zip archives', () {
      expect(
        () => importPaletteFile(
          _text('not a zip'),
          fileExtension: 'swatches',
          name: 'x',
        ),
        throwsFormatException,
      );
    });
  });

  test('rejects unsupported extensions', () {
    expect(
      () => importPaletteFile(_text(''), fileExtension: 'png', name: 'x'),
      throwsFormatException,
    );
  });
}
