import 'dart:collection';
import 'dart:typed_data';

/// In-memory LRU of raw WMS tile bytes keyed by full tile URL.
///
/// Cleared on app process restart. Call [clear] from a manual refresh so tiles
/// re-fetch; automatic dashboard reloads should not clear this cache.
final class KnmiRasterTileCache {
  KnmiRasterTileCache._();

  static final KnmiRasterTileCache instance = KnmiRasterTileCache._();

  static const int _maxEntries = 512;

  final LinkedHashMap<String, Uint8List> _bytesByUrl = LinkedHashMap();

  Uint8List? get(String url) {
    final bytes = _bytesByUrl.remove(url);
    if (bytes == null) return null;
    _bytesByUrl[url] = bytes;
    return bytes;
  }

  void put(String url, Uint8List bytes) {
    _bytesByUrl.remove(url);
    _bytesByUrl[url] = bytes;
    while (_bytesByUrl.length > _maxEntries) {
      _bytesByUrl.remove(_bytesByUrl.keys.first);
    }
  }

  void clear() => _bytesByUrl.clear();
}
