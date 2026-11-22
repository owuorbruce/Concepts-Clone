import 'dart:convert';

import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/cubits/editor_controller.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/dialogs/display_calibration.dart';
import 'package:butterfly/helpers/actual_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lw_sysapi/lw_sysapi.dart';
import 'package:material_ui/material_ui.dart';

Future<DisplayCalibrationProfile> readDisplayCalibrationProfile(
  BuildContext context,
) async {
  final display = View.of(context).display;
  final ratio = MediaQuery.devicePixelRatioOf(context);
  final metrics = await SysAPI.getDisplayMetrics();
  // Prefer the model name across restarts; native session IDs are only a
  // fallback. Browsers may not distinguish monitors with identical reports.
  final key = jsonEncode([
    kIsWeb ? 'web' : defaultTargetPlatform.name,
    metrics?.name ?? metrics?.displayId ?? display.id,
    display.size.width,
    display.size.height,
    ratio,
    metrics?.dpiX,
    metrics?.dpiY,
  ]);
  return DisplayCalibrationProfile(key, metrics, ratio);
}

/// The camera scale shown as 100 %, or null while calibrated zoom is off.
double? _calibratedZoom(BuildContext context, bool listen) {
  final settings = listen
      ? context.watch<SettingsCubit>().state
      : context.read<SettingsCubit>().state;
  if (!settings.hasFlag('calibratedZoom') || !settings.useCalibratedZoom) {
    return null;
  }
  final profile = listen
      ? context.select<EditorViewCubit, DisplayCalibrationProfile?>(
          (cubit) => cubit.state.displayCalibration,
        )
      : context.read<EditorViewCubit>().state.displayCalibration;
  if (profile == null) return null;
  final zoom =
      settings.getDisplayCalibration(profile.key) ?? profile.automaticZoom;
  return zoom != null && zoom.isFinite && zoom >= kMinZoom && zoom <= kMaxZoom
      ? zoom
      : null;
}

double displayZoom(BuildContext context, {bool listen = false}) =>
    _calibratedZoom(context, listen) ?? 1;

/// Camera scales the zoom controls may reach. Calibrated zoom keeps its own
/// range so its percentages stay physical; otherwise the canvas is endless.
({double min, double max}) cameraZoomRange(
  BuildContext context, {
  bool listen = false,
}) => _calibratedZoom(context, listen) == null
    ? (min: kMinZoom, max: kMaxZoom)
    : (min: kMinCalibrationZoom, max: kMaxCalibrationZoom);

Future<bool> calibrateDisplay(BuildContext context) async {
  final profile = await readDisplayCalibrationProfile(context);
  if (!context.mounted) return false;
  final settings = context.read<SettingsCubit>();
  final saved = settings.state.getDisplayCalibration(profile.key);
  final zoom = await showDialog<double>(
    context: context,
    builder: (_) => DisplayCalibrationDialog(
      initialZoom: saved ?? profile.automaticZoom,
      metrics: profile.metrics,
    ),
  );
  if (zoom == null || !context.mounted) return false;
  final current = await readDisplayCalibrationProfile(context);
  if (current.key != profile.key) return false;
  await settings.changeDisplayCalibration(profile.key, zoom);
  return true;
}
