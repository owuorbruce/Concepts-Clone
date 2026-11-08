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
List<double> _measurements(ToolWheelGeometry geometry) {
  List<double> point(Offset offset) => [offset.dx, offset.dy];
  List<double> sector(WheelSector sector) => [
    sector.innerRadius,
    sector.outerRadius,
  ];
  return [
    geometry.radius,
    geometry.slotSize,
    geometry.historySize,
    geometry.slotDistance,
    geometry.middleRadius,
    geometry.middleInnerRadius,
    geometry.middleGap,
    geometry.centerRadius,
    geometry.adjustmentDistance,
    geometry.adjustmentSize.width,
    geometry.adjustmentSize.height,
    for (var slot = 0; slot < kToolSlotCount; slot++)
      ...point(geometry.slotCenter(slot)),
    ...point(geometry.undoCenter),
    ...point(geometry.redoCenter),
    for (final adjustment in ToolAdjustment.values) ...[
      ...point(geometry.adjustmentCenter(adjustment)),
      ...sector(geometry.adjustmentSector(adjustment)),
    ],
    for (var index = 0; index < 10; index++)
      ...sector(geometry.ringSector(index)),
  ];
}

void main() {
  group('proportional geometry', () {
    test('the default wheel keeps the current sizes', () {
      const geometry = ToolWheelGeometry();
      expect(geometry.diameter, kToolWheelDefaultDiameter);
      expect(kToolWheelDefaultDiameter, 320);
      expect(kToolWheelMinDiameter, 240);
      expect(kToolWheelMaxDiameter, 480);
      expect(geometry.slotDistance, closeTo(130, 0.5));
      expect(geometry.middleRadius, closeTo(104, 0.5));
      expect(geometry.centerRadius, closeTo(30, 0.5));
      expect(geometry.adjustmentDistance, closeTo(68, 0.5));
      expect(geometry.slotSize, closeTo(46, 0.5));
      expect(geometry.historySize, closeTo(40, 0.5));
      expect(geometry.adjustmentSize.width, closeTo(60, 0.5));
      expect(geometry.adjustmentSize.height, closeTo(40, 0.5));
      expect(geometry.middleInnerRadius, closeTo(36, 0.5));
    });

    test('every length doubles with the diameter', () {
      final small = _measurements(const ToolWheelGeometry(diameter: 320));
      final large = _measurements(const ToolWheelGeometry(diameter: 640));
      expect(large, hasLength(small.length));
      for (var i = 0; i < small.length; i++) {
        expect(large[i], 2 * small[i], reason: 'measurement $i');
      }
    });

    test('angles do not depend on the diameter', () {
      const small = ToolWheelGeometry(diameter: 240);
      const large = ToolWheelGeometry(diameter: 480);
      for (final adjustment in ToolAdjustment.values) {
        final a = small.adjustmentSector(adjustment);
        final b = large.adjustmentSector(adjustment);
        expect(b.startAngle, a.startAngle);
        expect(b.sweepAngle, a.sweepAngle);
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

      test('each control owns its center point', () {
        for (final control in geometry.controls) {
          final point = geometry.controlCenter(control);
          expect(geometry.hitTest(point), control, reason: '$control');
        }
      });

      test('gaps between outer ring buttons belong to the ring', () {
        for (var index = 0; index < 10; index++) {
          final angle = geometry.ringAngle(index) + pi / 10;
          final point = Offset(cos(angle), sin(angle)) * geometry.slotDistance;
          expect(geometry.hitTest(point), WheelHit.ring, reason: '$index');
        }
      });

      test('the gap around the center belongs to the ring', () {
        final distance =
            (geometry.centerRadius + geometry.middleInnerRadius) / 2;
        for (final adjustment in ToolAdjustment.values) {
          final angle = geometry.adjustmentAngle(adjustment);
          final point = Offset(cos(angle), sin(angle)) * distance;
          expect(geometry.hitTest(point), WheelHit.ring);
        }
      });

      test('slots, undo and redo only own their circle', () {
        final corner = Offset(geometry.slotSize, geometry.slotSize) * 0.45;
        expect(
          geometry.hitTest(geometry.slotCenter(0) + corner),
          isNot(const WheelHit.slot(0)),
        );
        final historyCorner =
            Offset(geometry.historySize, geometry.historySize) * 0.45;
        expect(
          geometry.hitTest(geometry.undoCenter + historyCorner),
          isNot(WheelHit.undo),
        );
      });

      test('adjustments own their whole segment', () {
        for (final adjustment in ToolAdjustment.values) {
          final sector = geometry.adjustmentSector(adjustment);
          for (final t in [0.02, 0.25, 0.5, 0.75, 0.98]) {
            final angle = sector.startAngle + sector.sweepAngle * t;
            for (final r in [0.02, 0.5, 0.98]) {
              final distance = sector.innerRadius + sector.width * r;
              final point = Offset(cos(angle), sin(angle)) * distance;
              expect(geometry.hitTest(point), WheelHit.adjustment(adjustment));
            }
          }
        }
      });

      test('points beyond the rim are outside', () {
        for (var degrees = 0; degrees < 360; degrees += 15) {
          final angle = degrees * pi / 180;
          final point = Offset(cos(angle), sin(angle)) * (geometry.radius + 1);
          expect(geometry.hitTest(point), WheelHit.outside);
        }
        expect(
          geometry.hitTest(Offset(0, geometry.radius)),
          isNot(WheelHit.outside),
        );
      });

      test('controls do not overlap', () {
        final controls = geometry.controls;
        final radius = geometry.radius;
        for (var y = -radius; y <= radius; y += 1) {
          for (var x = -radius; x <= radius; x += 1) {
            final point = Offset(x, y);
            final owners = controls.where(
              (control) => geometry.controlContains(control, point),
            );
            expect(owners.length, lessThanOrEqualTo(1), reason: '$point');
          }
        }
      });

      test('controls lie inside the rim', () {
        final circles = [
          for (var slot = 0; slot < kToolSlotCount; slot++)
            (geometry.slotCenter(slot), geometry.slotSize / 2),
          (geometry.undoCenter, geometry.historySize / 2),
          (geometry.redoCenter, geometry.historySize / 2),
        ];
        for (final (center, size) in circles) {
          expect(center.distance + size, lessThanOrEqualTo(geometry.radius));
          expect(
            center.distance - size,
            greaterThanOrEqualTo(geometry.middleRadius),
          );
        }
        for (final adjustment in ToolAdjustment.values) {
          final sector = geometry.adjustmentSector(adjustment);
          expect(sector.outerRadius, lessThanOrEqualTo(geometry.radius));
          expect(sector.innerRadius, greaterThan(geometry.centerRadius));
        }
        expect(geometry.centerRadius, lessThan(geometry.radius));
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

    /// A point on the segment of [adjustment] outside its old 60x40 button.
    Offset arcPoint(ToolAdjustment adjustment) {
      final sector = geometry.adjustmentSector(adjustment);
      final angle = sector.startAngle + sector.sweepAngle * 0.15;
      final point = Offset(cos(angle), sin(angle)) * sector.middleRadius;
      final button = Rect.fromCenter(
        center: geometry.adjustmentCenter(adjustment),
        width: geometry.adjustmentSize.width,
        height: geometry.adjustmentSize.height,
      );
      expect(button.contains(point), isFalse);
      expect(geometry.hitTest(point), WheelHit.adjustment(adjustment));
      return point;
    }

    Offset wheelCenter(WidgetTester tester) {
      return tester.getCenter(find.byKey(const ValueKey('amaze-tool-wheel')));
    }

    testWidgets('tapping the arc beside the button opens the adjustment', (
      tester,
    ) async {
      await pumpWheel<PenTool>(tester);
      for (final adjustment in ToolAdjustment.values) {
        await tester.tapAt(wheelCenter(tester) + arcPoint(adjustment));
        await tester.pumpAndSettle();
        expect(find.byKey(panel), findsOneWidget, reason: '$adjustment');
        await tester.tapAt(wheelCenter(tester) + arcPoint(adjustment));
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
        await tester.tapAt(wheelCenter(tester) + arcPoint(adjustment));
        await tester.pumpAndSettle();
        await tester.tapAt(
          wheelCenter(tester) + geometry.adjustmentCenter(adjustment),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(panel), findsNothing, reason: '$adjustment');
      }
      expect((bloc.state as DocumentLoadSuccess).info.tools, before);
      await tester.tapAt(wheelCenter(tester) + arcPoint(ToolAdjustment.size));
      await tester.pumpAndSettle();
      expect(find.byKey(panel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ToolWheelGeometry', () {
    const geometry = ToolWheelGeometry();

    List<(Offset, double)> ringButtons() => [
      for (var slot = 0; slot < kToolSlotCount; slot++)
        (geometry.slotCenter(slot), geometry.slotSize / 2),
      (geometry.undoCenter, geometry.historySize / 2),
      (geometry.redoCenter, geometry.historySize / 2),
    ];

    test('puts undo and redo at the bottom, outside the slots', () {
      expect(geometry.undoCenter.dy, greaterThan(geometry.radius / 2));
      expect(geometry.redoCenter.dy, greaterThan(geometry.radius / 2));
      expect(geometry.undoCenter.dx, lessThan(0));
      expect(geometry.redoCenter.dx, greaterThan(0));
    });

    test('keeps the outer ring buttons apart and inside the rim', () {
      final buttons = ringButtons();
      for (var i = 0; i < buttons.length; i++) {
        final (center, radius) = buttons[i];
        expect(center.distance + radius, lessThan(geometry.radius));
        expect(center.distance - radius, greaterThan(geometry.middleRadius));
        for (var j = i + 1; j < buttons.length; j++) {
          final (other, otherRadius) = buttons[j];
          final gap = (center - other).distance - radius - otherRadius;
          expect(gap, greaterThan(0), reason: 'buttons $i and $j overlap');
        }
      }
    });

    test('keeps adjustments clear of the slots and the center', () {
      for (final adjustment in ToolAdjustment.values) {
        final rect = Rect.fromCenter(
          center: geometry.adjustmentCenter(adjustment),
          width: geometry.adjustmentSize.width,
          height: geometry.adjustmentSize.height,
        );
        for (final (center, radius) in ringButtons()) {
          final closest = Offset(
            center.dx.clamp(rect.left, rect.right),
            center.dy.clamp(rect.top, rect.bottom),
          );
          expect((center - closest).distance, greaterThan(radius));
        }
        final nearest = Offset(
          0.0.clamp(rect.left, rect.right),
          0.0.clamp(rect.top, rect.bottom),
        );
        expect(nearest.distance, greaterThan(geometry.centerRadius));
      }
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
