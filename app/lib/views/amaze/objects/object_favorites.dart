import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'object_store.dart';

/// Favorite objects, stored as `<packId>|<key>`.
const kObjectFavoritesKey = 'amaze.objects.favorites';

/// Ids of the favorite packs.
const kObjectFavoritePacksKey = 'amaze.objects.favoritePacks';

/// Ids of the collapsed packs.
const kObjectCollapsedKey = 'amaze.objects.collapsed';

/// The object library's favorites and collapsed packs.
///
/// Each toggle stores the changed list in the shared preferences and returns
/// the new state.
@immutable
class ObjectFavorites {
  const ObjectFavorites({
    this.favorites = const [],
    this.favoritePacks = const [],
    this.collapsed = const [],
  });

  /// Favorite objects as `<packId>|<key>`, oldest first.
  final List<String> favorites;
  final List<String> favoritePacks;
  final List<String> collapsed;

  static Future<ObjectFavorites> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ObjectFavorites(
      favorites: prefs.getStringList(kObjectFavoritesKey) ?? const [],
      favoritePacks: prefs.getStringList(kObjectFavoritePacksKey) ?? const [],
      collapsed: prefs.getStringList(kObjectCollapsedKey) ?? const [],
    );
  }

  bool isFavorite(ObjectEntry entry) => favorites.contains(entry.favoriteId);
  bool isFavoritePack(String packId) => favoritePacks.contains(packId);
  bool isCollapsed(String packId) => collapsed.contains(packId);

  /// The favorite objects that still exist in [packs], in favorite order.
  List<ObjectEntry> resolve(Iterable<ObjectPack> packs) {
    final entries = {
      for (final pack in packs)
        for (final entry in pack.objects) entry.favoriteId: entry,
    };
    return favorites.map((id) => entries[id]).nonNulls.toList();
  }

  Future<ObjectFavorites> toggleFavorite(ObjectEntry entry) async {
    final next = _toggled(favorites, entry.favoriteId);
    await _store(kObjectFavoritesKey, next);
    return _copyWith(favorites: next);
  }

  Future<ObjectFavorites> toggleFavoritePack(String packId) async {
    final next = _toggled(favoritePacks, packId);
    await _store(kObjectFavoritePacksKey, next);
    return _copyWith(favoritePacks: next);
  }

  Future<ObjectFavorites> toggleCollapsed(String packId) async {
    final next = _toggled(collapsed, packId);
    await _store(kObjectCollapsedKey, next);
    return _copyWith(collapsed: next);
  }

  ObjectFavorites _copyWith({
    List<String>? favorites,
    List<String>? favoritePacks,
    List<String>? collapsed,
  }) => ObjectFavorites(
    favorites: favorites ?? this.favorites,
    favoritePacks: favoritePacks ?? this.favoritePacks,
    collapsed: collapsed ?? this.collapsed,
  );

  static List<String> _toggled(List<String> list, String value) =>
      list.contains(value)
      ? list.where((e) => e != value).toList()
      : [...list, value];

  static Future<void> _store(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value);
  }
}
