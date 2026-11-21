import 'dart:convert';
import 'dart:ui' as ui;

import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'textures.dart';

/// Folder of the bundled brush definitions, named `<id>.v<version>.json`.
const kBrushAssetFolder = 'assets/brushes/';

final _catalog = BrushCatalog();
final Map<String, ui.Image> _textures = {};
Future<void>? _loading;

/// The brush with [id] at [version] (or the newest version below it, else
/// the newest). Synchronous once [loadBrushRegistry] has finished.
BrushDefinition? brushById(String id, [int? version]) {
  if (id.isEmpty) return null;
  return _catalog.byId(id, version);
}

/// Adds a definition, replacing the same id and version. For tests.
void registerBrush(BrushDefinition definition) => _catalog.register(definition);

/// The generated texture [name], or null before loading.
ui.Image? brushTexture(String name) => _textures[name];

/// Whether the textures have been generated.
bool get brushTexturesReady => _textures.isNotEmpty;

/// Loads every bundled brush and generates the textures, once.
Future<void> loadBrushRegistry([AssetBundle? bundle]) =>
    _loading ??= _load(bundle ?? rootBundle);

Future<void> _load(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths = manifest.listAssets().where(
      (path) => path.startsWith(kBrushAssetFolder) && path.endsWith('.json'),
    );
    for (final path in paths) {
      try {
        final json = jsonDecode(await bundle.loadString(path));
        _catalog.register(
          BrushDefinition.fromJson(Map<String, dynamic>.from(json as Map)),
        );
      } catch (e) {
        debugPrint('Brush $path could not be loaded: $e');
      }
    }
  } catch (e) {
    debugPrint('Brush definitions could not be loaded: $e');
  }
  await loadBrushTextures();
}

/// Generates the textures, once. The brush definitions are not needed.
Future<void> loadBrushTextures() async {
  if (_textures.isNotEmpty) return;
  _textures.addAll(await buildBrushTextures());
}
