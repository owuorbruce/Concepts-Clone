import 'dart:math';

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/defaults.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/src/generated/i18n/app_localizations.dart';
import 'package:butterfly/views/amaze/shell.dart';
import 'package:butterfly/views/amaze/tool_slots.dart';
import 'package:butterfly/views/amaze/tool_wheel.dart';
import 'package:butterfly/views/amaze/wheel_prefs.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

Tool _withId(Tool tool, String id) => tool.copyWith(id: id);

/// Every length and offset of [geometry], for comparing two diameters.
/// Every length and offset of [geometry], for comparing two diameters.
List<double> _measurements(ToolWheelGeometry geometry) {
  List<double> point(Offset offset) => [offset.dx, offset.dy];
  List<double> sector(WheelSector sector) => [
    sector.innerRadius,
    sector.outerRadius,
  ];
  return [
    geometry.radius,
    geometry.wedgeInnerRadius,
    geometry.discRadius,
    geometry.adjustmentInnerRadius,
    geometry.centerRadius,
    geometry.historyRadius,
    geometry.historyDistance,
    geometry.wedgeIconDistance,
    geometry.wedgeLabelDistance,
    for (var slot = 0; slot < kToolSlotCount; slot++) ...[
      ...sector(geometry.slotSector(slot)),
      ...point(geometry.slotIconCenter(slot)),
      ...point(geometry.slotLabelCenter(slot)),
    ],
    ...point(geometry.undoCenter),
    ...point(geometry.redoCenter),
    for (final adjustment in ToolAdjustment.values) ...[
      ...sector(geometry.adjustmentSector(adjustment)),
      ...point(geometry.adjustmentLabelCenter(adjustment)),
    ],
  ];
}

double _degrees(double radians) => radians * 180 / pi;

Offset _polar(double degrees, double distance) {
  final angle = degrees * pi / 180;
  return Offset(cos(angle), sin(angle)) * distance;
}

void main() {
  group('wheel layout', () {
    test('lengths are fractions of the outer radius', () {
      const geometry = ToolWheelGeometry();
      expect(geometry.diameter, kToolWheelDefaultDiameter);
      expect(kToolWheelMinDiameter, 240);
      expect(kToolWheelMaxDiameter, 480);
      final r = geometry.radius;
      expect(r, 160);
      expect(geometry.wedgeInnerRadius, closeTo(0.60 * r, 1e-9));
      expect(geometry.discRadius, closeTo(0.57 * r, 1e-9));
      expect(geometry.adjustmentInnerRadius, closeTo(0.23 * r, 1e-9));
      expect(geometry.centerRadius, closeTo(0.20 * r, 1e-9));
      expect(geometry.historyRadius, closeTo(0.12 * r, 1e-9));
      expect(geometry.historyDistance, closeTo(0.80 * r, 1e-9));
      expect(geometry.wedgeIconDistance, closeTo(0.78 * r, 1e-9));
      expect(geometry.wedgeLabelDistance, closeTo(0.92 * r, 1e-9));
    });

    test('every length doubles with the diameter', () {
      final small = _measurements(const ToolWheelGeometry(diameter: 320));
      final large = _measurements(const ToolWheelGeometry(diameter: 640));
      expect(large, hasLength(small.length));
      for (var i = 0; i < small.length; i++) {
        expect(large[i], closeTo(2 * small[i], 1e-9), reason: '$i');
      }
    });

    test('the wedges cover 300° clockwise from 210°', () {
      const geometry = ToolWheelGeometry();
      final first = geometry.slotSector(0);
      final last = geometry.slotSector(kToolSlotCount - 1);
      expect(_degrees(first.startAngle), closeTo(210, 1e-9));
      expect(_degrees(last.startAngle + last.sweepAngle), closeTo(510, 1e-9));
      var total = 0.0;
      for (var slot = 0; slot < kToolSlotCount; slot++) {
        final sector = geometry.slotSector(slot);
        expect(_degrees(sector.sweepAngle), closeTo(37.5, 1e-9));
        if (slot > 0) {
          final previous = geometry.slotSector(slot - 1);
          expect(
            sector.startAngle,
            closeTo(previous.startAngle + previous.sweepAngle, 1e-9),
          );
        }
        total += _degrees(sector.sweepAngle);
      }
      expect(total, closeTo(300, 1e-9));
    });

    test('undo and redo sit in the gap on the left', () {
      const geometry = ToolWheelGeometry();
      final r = geometry.radius;
      expect(geometry.undoCenter.dx, closeTo(_polar(195, 0.8 * r).dx, 1e-9));
      expect(geometry.undoCenter.dy, lessThan(0));
      expect(geometry.redoCenter.dy, greaterThan(0));
      expect(geometry.undoCenter.dx, lessThan(0));
    });

    test('adjustment sectors: size top, opacity right, smoothing left', () {
      const geometry = ToolWheelGeometry();
      final size = geometry.adjustmentLabelCenter(ToolAdjustment.size);
      final opacity = geometry.adjustmentLabelCenter(ToolAdjustment.opacity);
      final smoothing = geometry.adjustmentLabelCenter(
        ToolAdjustment.smoothing,
      );
      expect(size.dx, closeTo(0, 1e-9));
      expect(size.dy, lessThan(0));
      expect(opacity.dx, greaterThan(0));
      expect(opacity.dy, greaterThan(0));
      expect(smoothing.dx, lessThan(0));
      expect(smoothing.dy, greaterThan(0));
      for (final adjustment in ToolAdjustment.values) {
        final sector = geometry.adjustmentSector(adjustment);
        expect(_degrees(sector.sweepAngle), closeTo(120, 1e-9));
      }
    });
  });

  for (final diameter in [
    kToolWheelMinDiameter,
    kToolWheelDefaultDiameter,
    kToolWheelMaxDiameter,
  ]) {
    group('hit test at diameter $diameter', () {
      final geometry = ToolWheelGeometry(diameter: diameter);
      final r = geometry.radius;

      test('the middle of each wedge belongs to its slot', () {
        for (var slot = 0; slot < kToolSlotCount; slot++) {
          final middle = geometry.slotSector(slot).middle;
          expect(geometry.hitTest(middle), WheelHit.slot(slot));
        }
      });

      test('slots own their whole wedge', () {
        for (var slot = 0; slot < kToolSlotCount; slot++) {
          final sector = geometry.slotSector(slot);
          for (final t in [0.01, 0.25, 0.5, 0.75, 0.99]) {
            final angle = sector.startAngle + sector.sweepAngle * t;
            for (final w in [0.01, 0.5, 0.99]) {
              final distance = sector.innerRadius + sector.width * w;
              final point = Offset(cos(angle), sin(angle)) * distance;
              expect(geometry.hitTest(point), WheelHit.slot(slot));
            }
          }
        }
      });

      test('each control owns its center point', () {
        for (final control in geometry.controls) {
          final point = geometry.controlCenter(control);
          expect(geometry.hitTest(point), control, reason: '$control');
        }
        expect(geometry.hitTest(geometry.undoCenter), WheelHit.undo);
        expect(geometry.hitTest(geometry.redoCenter), WheelHit.redo);
        expect(geometry.hitTest(Offset.zero), WheelHit.center);
      });

      test('the gap and the thin rings belong to the ring', () {
        // In the gap, between and beside undo and redo.
        expect(geometry.hitTest(_polar(180, 0.80 * r)), WheelHit.ring);
        expect(geometry.hitTest(_polar(180, 0.65 * r)), WheelHit.ring);
        expect(geometry.hitTest(_polar(155, 0.95 * r)), WheelHit.ring);
        expect(geometry.hitTest(_polar(205, 0.95 * r)), WheelHit.ring);
        for (var degrees = 0; degrees < 360; degrees += 30) {
          // Between the disc and the wedges.
          expect(
            geometry.hitTest(_polar(degrees + 5.0, 0.585 * r)),
            WheelHit.ring,
          );
          // Between the color dot and the adjustments.
          expect(
            geometry.hitTest(_polar(degrees + 5.0, 0.215 * r)),
            WheelHit.ring,
          );
        }
      });

      test('each disc sector belongs to its adjustment', () {
        for (final adjustment in ToolAdjustment.values) {
          final sector = geometry.adjustmentSector(adjustment);
          expect(
            geometry.hitTest(sector.middle),
            WheelHit.adjustment(adjustment),
          );
          for (final t in [0.01, 0.5, 0.99]) {
            final angle = sector.startAngle + sector.sweepAngle * t;
            for (final w in [0.01, 0.99]) {
              final distance = sector.innerRadius + sector.width * w;
              final point = Offset(cos(angle), sin(angle)) * distance;
              expect(geometry.hitTest(point), WheelHit.adjustment(adjustment));
            }
          }
        }
      });

      test('points beyond the rim are outside', () {
        for (var degrees = 0; degrees < 360; degrees += 15) {
          expect(
            geometry.hitTest(_polar(degrees.toDouble(), r + 1)),
            WheelHit.outside,
          );
        }
        expect(geometry.hitTest(Offset(0, r)), isNot(WheelHit.outside));
      });

      test('controls do not overlap', () {
        final controls = geometry.controls;
        for (var y = -r; y <= r; y += 1) {
          for (var x = -r; x <= r; x += 1) {
            final point = Offset(x, y);
            final owners = controls.where(
              (control) => geometry.controlContains(control, point),
            );
            expect(owners.length, lessThanOrEqualTo(1), reason: '$point');
          }
        }
        // Undo and redo stay clear of the wedges and of each other.
        final gap = (geometry.undoCenter - geometry.redoCenter).distance;
        expect(gap, greaterThan(2 * geometry.historyRadius));
        for (final center in [geometry.undoCenter, geometry.redoCenter]) {
          final angle = _degrees(atan2(center.dy, center.dx)) % 360;
          final half = _degrees(asin(geometry.historyRadius / center.distance));
          expect(angle - half, greaterThan(150));
          expect(angle + half, lessThan(210));
        }
      });

      test('controls lie inside the rim', () {
        for (final center in [geometry.undoCenter, geometry.redoCenter]) {
          expect(
            center.distance + geometry.historyRadius,
            lessThanOrEqualTo(r),
          );
          expect(
            center.distance - geometry.historyRadius,
            greaterThan(geometry.discRadius),
          );
        }
        for (var slot = 0; slot < kToolSlotCount; slot++) {
          expect(geometry.slotSector(slot).outerRadius, lessThanOrEqualTo(r));
        }
        for (final adjustment in ToolAdjustment.values) {
          final sector = geometry.adjustmentSector(adjustment);
          expect(sector.outerRadius, lessThan(geometry.wedgeInnerRadius));
          expect(sector.innerRadius, greaterThan(geometry.centerRadius));
        }
      });
    });
  }

  group('wheel taps', () {
    setUpAll(() {
      registerFallbackValue(const AssetLocation(path: 'fallback.bfly'));
    });

    /// Pumps the wheel layer with the first default tool of type [T] active.
    Future<DocumentBloc> pumpWheel<T extends Tool>(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final fileSystem = MockButterflyFileSystem();
      final settings = fileSystem.settingsCubit as MockSettingsCubit;
      when(() => settings.state)
          .thenReturn(const ButterflySettings(autosave: false));
      when(() => settings.stream).thenAnswer((_) => const Stream.empty());
      when(() => settings.addRecentHistory(any())).thenAnswer((_) async {});
      final editor = EditorController(
        settings,
        TransformCubit(1),
        CameraViewport.unbaked(),
      );
      final window = WindowCubit(fullScreen: false);
      final data = DocumentDefaults.createDocument(name: 'wheel');
      final bloc = (await tester.runAsync(() async {
        final bloc = DocumentBloc(
          fileSystem,
          editor,
          window,
          data,
          const AssetLocation(path: 'wheel.bfly'),
        );
        await pumpEventQueue();
        return bloc;
      }))!;
      final state = bloc.state as DocumentLoadSuccess;
      final index = state.info.tools.indexWhere((tool) => tool is T);
      final tools = ToolCubit(
        ToolRuntimeState(
          index: index,
          handler: Handler.fromTool(state.info.tools[index]),
        ),
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          await tools.close();
          await bloc.close();
          await editor.close();
          await window.close();
        });
      });
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<DocumentBloc>.value(value: bloc),
            BlocProvider<ToolCubit>.value(value: tools),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              ...AppLocalizations.localizationsDelegates,
              LeapLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AmazeToolWheelLayer()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return bloc;
    }

    const geometry = ToolWheelGeometry();
    const panel = ValueKey('amaze-adjustment-panel');

    /// A point on the sector of [adjustment] away from its label.
    Offset sectorPoint(ToolAdjustment adjustment) {
      final sector = geometry.adjustmentSector(adjustment);
      final angle = sector.startAngle + sector.sweepAngle * 0.12;
      final distance = sector.innerRadius + sector.width * 0.2;
      final point = Offset(cos(angle), sin(angle)) * distance;
      final label = Rect.fromCenter(
        center: geometry.adjustmentLabelCenter(adjustment),
        width: geometry.radius * 0.36,
        height: geometry.radius * 0.16,
      );
      expect(label.contains(point), isFalse);
      expect(geometry.hitTest(point), WheelHit.adjustment(adjustment));
      return point;
    }

    Offset wheelCenter(WidgetTester tester) {
      return tester.getCenter(find.byKey(const ValueKey('amaze-tool-wheel')));
    }

    testWidgets('tapping anywhere on a disc sector opens the adjustment', (
      tester,
    ) async {
      await pumpWheel<PenTool>(tester);
      for (final adjustment in ToolAdjustment.values) {
        await tester.tapAt(wheelCenter(tester) + sectorPoint(adjustment));
        await tester.pumpAndSettle();
        expect(find.byKey(panel), findsOneWidget, reason: '$adjustment');
        await tester.tapAt(wheelCenter(tester) + sectorPoint(adjustment));
        await tester.pumpAndSettle();
        expect(find.byKey(panel), findsNothing, reason: '$adjustment');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an unsupported adjustment changes nothing', (
      tester,
    ) async {
      final bloc = await pumpWheel<EraserTool>(tester);
      final before = (bloc.state as DocumentLoadSuccess).info.tools;
      for (final adjustment in [
        ToolAdjustment.opacity,
        ToolAdjustment.smoothing,
      ]) {
        await tester.tapAt(wheelCenter(tester) + sectorPoint(adjustment));
        await tester.pumpAndSettle();
        await tester.tapAt(
          wheelCenter(tester) + geometry.adjustmentLabelCenter(adjustment),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(panel), findsNothing, reason: '$adjustment');
      }
      expect((bloc.state as DocumentLoadSuccess).info.tools, before);
      await tester.tapAt(
        wheelCenter(tester) + sectorPoint(ToolAdjustment.size),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(panel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('tool slots', () {
    final tools = [
      _withId(Tool.select(), 'select'),
      _withId(Tool.undo(), 'undo'),
      _withId(Tool.pen(), 'pen'),
      _withId(Tool.redo(), 'redo'),
      _withId(Tool.eraser(), 'eraser'),
      _withId(Tool.hand(), 'hand'),
    ];

    test('skip undo and redo', () {
      expect(slotToolIndices(tools), [0, 2, 4, 5]);
    });

    test('hold at most eight tools', () {
      final many = [for (var i = 0; i < 12; i++) _withId(Tool.pen(), '$i')];
      expect(slotToolIndices(many), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('move targets swap two slots with ToolReordered semantics', () {
      expect(slotMoveTarget(tools, 0, 1), ('select', 3));
      expect(slotMoveTarget(tools, 1, 0), ('pen', 0));
      expect(slotMoveTarget(tools, 3, 2), ('hand', 4));
      expect(slotMoveTarget(tools, 0, 4), isNull);
      expect(slotMoveTarget(tools, -1, 0), isNull);
    });

    test('the catalog offers tools but not undo or redo', () {
      final catalog = slotToolCatalog();
      expect(catalog, isNotEmpty);
      expect(catalog.whereType<UndoTool>(), isEmpty);
      expect(catalog.whereType<RedoTool>(), isEmpty);
      expect(catalog.whereType<PenTool>(), isNotEmpty);
      expect(catalog.whereType<ShapeTool>(), isNotEmpty);
    });
  });

  group('tool adjustments', () {
    test('only lists properties the tool has', () {
      expect(Tool.pen().adjustments, ToolAdjustment.values);
      expect(Tool.eraser().adjustments, [ToolAdjustment.size]);
      expect(Tool.laser().adjustments, [ToolAdjustment.size]);
      expect(Tool.hand().adjustments, isEmpty);
      expect(Tool.select().adjustments, isEmpty);
      final shape = Tool.shape(
        property: const ShapeProperty(shape: RectangleShape()),
      );
      expect(shape.adjustments, [ToolAdjustment.size, ToolAdjustment.opacity]);
    });

    test('opacity needs a solid paint', () {
      final tool = Tool.pen(
        property: const PenProperty(paint: ElementPaint.gradient()),
      );
      expect(tool.readAdjustment(ToolAdjustment.opacity), isNull);
      expect(tool.adjustments, [ToolAdjustment.size, ToolAdjustment.smoothing]);
    });

    test('writes the pen properties the renderer uses', () {
      final pen = Tool.pen() as PenTool;
      final wide = pen.writeAdjustment(ToolAdjustment.size, 12) as PenTool;
      expect(wide.property.strokeWidth, 12);
      final faded = pen.writeAdjustment(ToolAdjustment.opacity, 0.5) as PenTool;
      final paint = faded.property.paint as SolidElementPaint;
      expect(paint.color.a, 128);
      expect(paint.color.withValues(a: 255), pen.property.paint.previewColor);
      final smooth = pen.writeAdjustment(ToolAdjustment.smoothing, 0.9);
      expect((smooth as PenTool).property.smoothing, 0.9);
    });

    test('clamps to the range and keeps other tools unchanged', () {
      final pen = Tool.pen();
      final huge = pen.writeAdjustment(ToolAdjustment.size, 500) as PenTool;
      expect(huge.property.strokeWidth, 70);
      final eraser = Tool.eraser().writeAdjustment(ToolAdjustment.size, 0);
      expect((eraser as EraserTool).strokeWidth, 1);
      final hand = Tool.hand();
      expect(hand.writeAdjustment(ToolAdjustment.size, 10), same(hand));
    });

    test('formats values for the wheel', () {
      expect(formatAdjustment(ToolAdjustment.size, 5), '5.0');
      expect(formatAdjustment(ToolAdjustment.size, 12.4), '12');
      expect(formatAdjustment(ToolAdjustment.opacity, 0.5), '50%');
      expect(formatAdjustment(ToolAdjustment.smoothing, 1), '100%');
    });
  });

  test('clampToolWheelPosition keeps the wheel inside its bounds', () {
    const size = Size(100, 100);
    const bounds = Size(400, 300);
    expect(
      clampToolWheelPosition(const Offset(-20, 500), size, bounds),
      const Offset(0, 200),
    );
    expect(
      clampToolWheelPosition(const Offset(50, 50), size, const Size(60, 60)),
      Offset.zero,
    );
  });

  test('the wheel layout survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await loadToolWheelLayout()).mode, ToolWheelMode.wheel);
    await saveToolWheelLayout(
      const ToolWheelLayout(
        mode: ToolWheelMode.bar,
        position: Offset(0.25, 0.75),
        collapsed: true,
      ),
    );
    final loaded = await loadToolWheelLayout();
    expect(loaded.mode, ToolWheelMode.bar);
    expect(loaded.position, const Offset(0.25, 0.75));
    expect(loaded.collapsed, isTrue);
  });

  group('AmazeShellSettings', () {
    test('the classic flag wins over the aMaze flag', () {
      const settings = ButterflySettings(
        defaultTemplate: 'default',
        flags: [kAmazeShellFlag, kClassicEditorFlag],
      );
      expect(settings.usesAmazeShell, isFalse);
      expect(settings.usesFloatingEditor, isFalse);
    });

    test('the aMaze flag turns the shell on and the inline tools off', () {
      const settings = ButterflySettings(
        defaultTemplate: 'default',
        flags: [kAmazeShellFlag],
      );
      expect(settings.usesAmazeShell, isTrue);
      expect(settings.usesFloatingEditor, isTrue);
      expect(settings.usesInlineTools, isFalse);
    });

    test('follows the platform default without flags', () {
      const settings = ButterflySettings();
      expect(settings.usesAmazeShell, amazeShellIsDefault);
    });
  });
}
