import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_models.dart';
import 'rain_forecast_analyzer.dart';

/// Last known location of the user, persisted across launches/isolates so the
/// background rain check has coordinates to query without re-requesting GPS.
class RainCheckLocation {
  const RainCheckLocation({required this.lat, required this.lon});
  final double lat;
  final double lon;
}

/// Platform-agnostic rain check.
///
/// The background task (Android WorkManager / iOS BGTaskScheduler / a Timer
/// on web) all call [check]. Platform code only owns:
///   * permissions,
///   * how to display the notification,
///   * how/when to wake up this runner.
///
/// Everything else — reading the cached location, calling Open-Meteo,
/// running the analyzer, and deduping repeat alerts — lives here so the
/// logic is unit-testable on the Dart VM.
abstract final class RainCheckRunner {
  RainCheckRunner._();

  static const String _kLatKey = 'rain_check_last_lat';
  static const String _kLonKey = 'rain_check_last_lon';
  static const String _kLastNotifiedStartKey =
      'rain_check_last_notified_start_utc';

  static const String _openMeteoHost = 'api.open-meteo.com';

  /// Single stateless handle. [SharedPreferencesAsync] has no `getInstance`
  /// step — every call hits the platform store directly, which is what we
  /// want here: the foreground and the background isolate both end up
  /// touching the same on-disk preferences without having to share any
  /// cached instance.
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// Persist the user's current location so the BG isolate can reuse it.
  ///
  /// Call this every time the foreground resolves a location, so the BG
  /// check always runs against a recent point.
  static Future<void> saveLocation(double lat, double lon) async {
    await _prefs.setDouble(_kLatKey, lat);
    await _prefs.setDouble(_kLonKey, lon);
  }

  /// Read the last-known location, or `null` if none has been stored yet.
  static Future<RainCheckLocation?> readLocation() async {
    final lat = await _prefs.getDouble(_kLatKey);
    final lon = await _prefs.getDouble(_kLonKey);
    if (lat == null || lon == null) return null;
    return RainCheckLocation(lat: lat, lon: lon);
  }

  /// Runs a full rain-check cycle.
  ///
  /// Returns the forecast to notify on, or `null` when either:
  ///   * no location has been cached yet, or
  ///   * the analyzer found no imminent rain, or
  ///   * we already notified for the same rain event.
  ///
  /// On a notifiable result, [check] persists the start time of the rain
  /// event before returning, so subsequent invocations within the same
  /// event return `null`.
  static Future<RainForecast?> check({
    http.Client? httpClient,
    DateTime? nowUtcOverride,
  }) async {
    final location = await readLocation();
    if (location == null) return null;

    final now = nowUtcOverride ?? DateTime.now().toUtc();
    final ownsClient = httpClient == null;
    final client = httpClient ?? http.Client();
    try {
      final minutely = await _fetchMinutely(client, location);
      final forecast = RainForecastAnalyzer.analyze(
        minutely: minutely,
        nowUtc: now,
      );
      if (forecast == null) return null;

      final thisKey = forecast.startUtc.toIso8601String();
      if (await _prefs.getString(_kLastNotifiedStartKey) == thisKey) {
        return null;
      }
      await _prefs.setString(_kLastNotifiedStartKey, thisKey);

      return forecast;
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Hits Open-Meteo directly (no cache): the background isolate has a
  /// short wall-clock budget and we only need two 15-min buckets worth of
  /// data, so bypassing [CacheStore] keeps this runner self-contained.
  static Future<MinutelyForecast> _fetchMinutely(
    http.Client client,
    RainCheckLocation loc,
  ) async {
    final uri = Uri.https(_openMeteoHost, '/v1/forecast', {
      'latitude': loc.lat.toString(),
      'longitude': loc.lon.toString(),
      'minutely_15': 'precipitation',
      'timezone': 'auto',
      'past_minutely_15': '0',
      // 8 buckets = 2 hours. We only read the first ~2 but grabbing extra
      // keeps the duration field accurate for longer rain events.
      'forecast_minutely_15': '8',
    });
    final resp = await client.get(uri);
    if (resp.statusCode != 200) {
      throw Exception(
        'Open-Meteo minutely failed: HTTP ${resp.statusCode}',
      );
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final offsetSeconds = (body['utc_offset_seconds'] as num).toInt();
    return MinutelyForecast.fromJson(
      Map<String, dynamic>.from(body['minutely_15'] as Map),
      offsetSeconds,
    );
  }
}
