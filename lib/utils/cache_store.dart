import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight JSON cache backed by [SharedPreferences].
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
/// Use [CacheExpiration.alignedNext] to compute a wall-clock-aligned
/// expiration matching the upstream API's update cadence (e.g. KNMI's
/// 5-minute radar tile renewal), so multiple devices/processes converge on
/// the same refresh moment instead of drifting per-session.
class CacheStore {
  CacheStore({Future<SharedPreferences> Function()? prefsFactory})
      : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  /// Read [key] if present and not yet expired.
  Future<dynamic> read(String key) async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString('${key}_data');
    final exp = prefs.getString('${key}_expiration');
    if (raw == null || exp == null) return null;

    final expiresAt = DateTime.tryParse(exp);
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) return null;

    return json.decode(raw);
  }

  /// Write [value] under [key] with [expiresAt] expiration.
  Future<void> write(String key, dynamic value, DateTime expiresAt) async {
    final prefs = await _prefsFactory();
    await prefs.setString('${key}_data', json.encode(value));
    await prefs.setString('${key}_expiration', expiresAt.toIso8601String());
  }

  /// Read [key] if fresh, otherwise call [fetch], cache the non-null result,
  /// and return it. On [fetch] failure with a stale cached value, return the
  /// stale value instead of throwing.
  Future<dynamic> getOrFetch({
    required String key,
    required Future<dynamic> Function() fetch,
    required DateTime expiresAt,
  }) async {
    final fresh = await read(key);
    if (fresh != null) return fresh;

    final prefs = await _prefsFactory();
    final staleRaw = prefs.getString('${key}_data');

    try {
      final value = await fetch();
      if (value != null) await write(key, value, expiresAt);
      return value;
    } catch (_) {
      if (staleRaw != null) return json.decode(staleRaw);
      rethrow;
    }
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
    final totalMinutes = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final shifted = totalMinutes - delayMinutes;
    final currentAligned = (shifted ~/ intervalMinutes) * intervalMinutes;
    final nextAligned = currentAligned + intervalMinutes;
    final expirationMinutes = nextAligned + delayMinutes;
    return DateTime.fromMillisecondsSinceEpoch(
      expirationMinutes * Duration.millisecondsPerMinute,
    );
  }
}
