import 'package:flutter/services.dart';

import '../models/marker_palette.dart';

/// Asset key of the bundled marker reference palette.
const kMarkerPaletteAsset = 'assets/palettes/copic_colors.json';

/// Loads the bundled marker palette from [bundle] (the [rootBundle] by
/// default).
///
/// Returns null if the asset is missing or invalid, so callers can fall back
/// to another palette.
Future<MarkerPalette?> loadMarkerPalette({
  AssetBundle? bundle,
  String key = kMarkerPaletteAsset,
}) async {
  try {
    final json = await (bundle ?? rootBundle).loadString(key, cache: false);
    return MarkerPalette.parse(json);
  } catch (_) {
    return null;
  }
}
