import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/views/amaze/library.dart';
import 'package:butterfly/src/generated/i18n/app_localizations_en.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new documents get the library pen drawing with amaze.pen', () {
    final pens = DocumentDefaults.createTools().whereType<PenTool>().toList();
    expect(pens, hasLength(1));
    final pen = pens.single;
    expect(pen.property.brush, 'amaze.pen');
    expect(pen.property.brushVersion, greaterThanOrEqualTo(1));
    expect(libraryEntryOf(pen), LibraryEntry.pen);
    expect(pen.id, isNotNull);
  });

  test('a document that already has a classic pen keeps it', () {
    final classic = PenTool(id: 'old');
    final roundTrip = Tool.fromJson(classic.toJson()) as PenTool;
    expect(roundTrip.property.brush, '');
    expect(ToolFamily.ofTool(roundTrip), ToolFamily.classicPen);
  });

  test('a slot names the classic pen Pen; only More tools says classic', () {
    final loc = AppLocalizationsEn();
    expect(ToolFamily.classicPen.getSlotName(loc), 'Pen');
    expect(ToolFamily.classicPen.getLocalizedName(loc), 'Pen (classic)');
    expect(ToolFamily.eraser.getSlotName(loc), loc.amazeToolEraser);
  });

  test('Fill explains that it fills a closed shape', () {
    final loc = AppLocalizationsEn();
    expect(
      LibraryEntry.fill.getLocalizedInfo(loc),
      "Draw a closed shape; it's filled with the current color.",
    );
    expect(LibraryEntry.pen.getLocalizedInfo(loc), isNull);
  });
}
