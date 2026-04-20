import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight JSON cache backed by [SharedPreferencesAsync].
///
/// Was duplicated across `OpenMeteoService`, `RainViewerService` and
/// `KNMIService` as a private `_getCachedOrFetch` helper. Centralising it
/// here removes ~60 lines of duplicated logic and gives every data source the
/// same stale-on-error fallback contract:
///
/// 1. If a non-expired value is cached → return it without calling [fetch].
/// 2. Otherwise call [fetch], store its non-null result with [expiresAt],
///    and return it.
/// 3. If [fetch] throws *and* a (possibly stale) cached value exists, return
///    the cached value instead of letting the exception escape.
///
/// Storage format: one key per cache entry, containing a JSON envelope with
/// both the data and the expiration. This replaces the previous two-key
/// layout (`<key>_data` + `<key>_expiration`) so reads and writes are a
/// single round-trip.
///
/// Use [CacheExpiration.alignedNext] to compute a wall-clock-aligned
/// expiration matching the upstream API's update cadence (e.g. KNMI's
/// 5-minute radar tile renewal), so multiple devices/processes converge on
/// the same refresh moment instead of drifting per-session.
class CacheStore {
  CacheStore({SharedPreferencesAsync? prefs}) : _injected = prefs;

  final SharedPreferencesAsync? _injected;

  // Lazily resolved: `SharedPreferencesAsync()` throws unless the platform
  // instance has been registered, so creating it in the constructor would
  // force every call site (incl. widget tests that never hit the cache) to
  // set up the plugin mock up front. Defer until the first real read/write.
  SharedPreferencesAsync? _cached;
  SharedPreferencesAsync get _prefs =>
      _injected ?? (_cached ??= SharedPreferencesAsync());

  /// Read [key] if present and not yet expired.
  Future<dynamic> read(String key) async {
    final entry = await _readEntry(key);
    if (entry == null || !entry.isFresh) return null;
    return entry.data;
  }

  /// Write [value] under [key] with [expiresAt] expiration.
  Future<void> write(String key, dynamic value, DateTime expiresAt) {
    return _prefs.setString(
      key,
      json.encode(_CacheEntry(data: value, expiresAt: expiresAt).toJson()),
    );
  }

  /// Read [key] if fresh, otherwise call [fetch], cache the non-null result,
  /// and return it. On [fetch] failure with a stale cached value, return the
  /// stale value instead of throwing.
  Future<dynamic> getOrFetch({
    required String key,
    required Future<dynamic> Function() fetch,
    required DateTime expiresAt,
  }) async {
    final entry = await _readEntry(key);
    if (entry != null && entry.isFresh) return entry.data;

    try {
      final value = await fetch();
      if (value != null) await write(key, value, expiresAt);
      return value;
    } catch (_) {
      if (entry != null) return entry.data;
      rethrow;
    }
  }

  Future<_CacheEntry?> _readEntry(String key) async {
    final raw = await _prefs.getString(key);
    if (raw == null) return null;
    return _CacheEntry.tryDecode(raw);
  }
}

/// Expiration helpers for [CacheStore].
abstract final class CacheExpiration {
  CacheExpiration._();

  /// Returns the next wall-clock instant that is a multiple of
  /// [intervalMinutes] minutes plus [delayMinutes], strictly after now.
  ///
  /// Used to align multiple clients with an upstream API's refresh cadence.
  static DateTime alignedNext(int intervalMinutes, int delayMinutes) {
    final now = DateTime.now();
    final totalMinutes =
        now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final shifted = totalMinutes - delayMinutes;
    final currentAligned = (shifted ~/ intervalMinutes) * intervalMinutes;
    final nextAligned = currentAligned + intervalMinutes;
    final expirationMinutes = nextAligned + delayMinutes;
    return DateTime.fromMillisecondsSinceEpoch(
      expirationMinutes * Duration.millisecondsPerMinute,
    );
  }
}

class _CacheEntry {
  const _CacheEntry({required this.data, required this.expiresAt});

  final dynamic data;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
        'data': data,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static _CacheEntry? tryDecode(String raw) {
    try {
      final m = json.decode(raw);
      if (m is! Map<String, dynamic>) return null;
      final exp = DateTime.tryParse(m['expiresAt'] as String? ?? '');
      if (exp == null) return null;
      return _CacheEntry(data: m['data'], expiresAt: exp);
    } catch (_) {
      return null;
    }
  }
}
