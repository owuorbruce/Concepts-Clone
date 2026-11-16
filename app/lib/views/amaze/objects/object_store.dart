import 'package:butterfly/api/file_system.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset paths of the object packs that ship with the app.
const kBundledObjectPacks = <String>[
  'assets/object_packs/furniture.bfly',
  'assets/object_packs/architecture.bfly',
];

/// Prefix of the id of a pack loaded from the app bundle.
const kBundledObjectPackPrefix = 'bundled:';

/// Where an [ObjectPack] comes from. It decides the order of the packs.
enum ObjectPackSource { bundled, core, user }

/// A pack shown in the object library.
@immutable
class ObjectPack {
  const ObjectPack({
    required this.id,
    required this.name,
    required this.editable,
    required this.source,
    required this.objects,
  });

  /// The pack's file name from the pack system, or `bundled:<asset path>`.
  final String id;

  /// The name in the pack's metadata, else the [id].
  final String name;

  /// Whether the user can change the pack. The core pack and bundled packs
  /// cannot be changed.
  final bool editable;

  final ObjectPackSource source;
  final List<ObjectEntry> objects;
}

/// One component of a pack, shown as a tile in the object library.
@immutable
class ObjectEntry {
  const ObjectEntry({
    required this.packId,
    required this.packName,
    required this.key,
    required this.name,
    required this.category,
    required this.component,
  });

  factory ObjectEntry.fromComponent(
    String packId,
    String packName,
    NamedItem<ButterflyComponent> item,
  ) {
    final (:category, :name) = splitObjectName(item.name);
    return ObjectEntry(
      packId: packId,
      packName: packName,
      key: item.name,
      name: name,
      category: category,
      component: item.item,
    );
  }

  final String packId;
  final String packName;

  /// The component's name in the pack.
  final String key;

  /// The name shown on the tile.
  final String name;
  final String? category;
  final ButterflyComponent component;

  /// The id favorites are stored under.
  String get favoriteId => '$packId|$key';

  @override
  bool operator ==(Object other) =>
      other is ObjectEntry && other.packId == packId && other.key == key;

  @override
  int get hashCode => Object.hash(packId, key);
}

/// Separator between category and name in a component name.
const kObjectCategorySeparator = ' — ';

/// Splits `"Living — Sofa"` into the category `Living` and the name `Sofa`.
///
/// Only the first separator splits; a key without one has no category.
({String? category, String name}) splitObjectName(String key) {
  final index = key.indexOf(kObjectCategorySeparator);
  if (index < 0) return (category: null, name: key);
  return (
    category: key.substring(0, index),
    name: key.substring(index + kObjectCategorySeparator.length),
  );
}

ObjectPack? _buildPack(
  String id,
  NoteData data,
  ObjectPackSource source, {
  required bool editable,
}) {
  final metadataName = data.name?.trim();
  final name = metadataName == null || metadataName.isEmpty ? id : metadataName;
  final objects = data
      .getNamedComponents()
      .map((item) => ObjectEntry.fromComponent(id, name, item))
      .toList();
  if (objects.isEmpty) return null;
  return ObjectPack(
    id: id,
    name: name,
    editable: editable,
    source: source,
    objects: objects,
  );
}

/// Loads every pack with components: the bundled packs first, then the core
/// pack and the user's packs.
///
/// A pack that fails to load is skipped and logged; this never throws.
Future<List<ObjectPack>> loadObjectPacks(
  ButterflyFileSystem fs, {
  List<String> bundled = kBundledObjectPacks,
  AssetBundle? bundle,
}) async {
  final packs = <ObjectPack>[];
  for (final path in bundled) {
    try {
      final bytes = await (bundle ?? rootBundle).load(path);
      final data = NoteData.fromData(Uint8List.sublistView(bytes));
      final pack = _buildPack(
        '$kBundledObjectPackPrefix$path',
        data,
        .bundled,
        editable: false,
      );
      if (pack != null) packs.add(pack);
    } catch (e) {
      debugPrint('Could not load the object pack $path: $e');
    }
  }
  List<(String, NoteData)> installed;
  try {
    installed = await fs.getCoreAndUserPacks();
  } catch (e) {
    debugPrint('Could not load the installed object packs: $e');
    installed = const [];
  }
  for (final (id, data) in installed) {
    try {
      final core = id == kCorePackFileName;
      final pack = _buildPack(id, data, core ? .core : .user, editable: !core);
      if (pack != null) packs.add(pack);
    } catch (e) {
      debugPrint('Could not load the object pack $id: $e');
    }
  }
  return packs;
}
