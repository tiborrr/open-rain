import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_models.dart';
import '../providers/weather_provider.dart';
import '../utils/result.dart';
import 'open_meteo_service.dart';
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
/// Everything else — reading the cached location, querying [WeatherProvider],
/// running the analyzer, and deduping repeat alerts — lives here so the
/// logic is unit-testable on the Dart VM.
abstract final class RainCheckRunner {
  RainCheckRunner._();

  static const String _kLatKey = 'rain_check_last_lat';
  static const String _kLonKey = 'rain_check_last_lon';
  static const String _kLastNotifiedStartKey =
      'rain_check_last_notified_start_utc';

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
  ///   * upstream weather provider returned an error, or
  ///   * the analyzer found no imminent rain, or
  ///   * we already notified for the same rain event.
  ///
  /// On a notifiable result, [check] persists the start time of the rain
  /// event before returning, so subsequent invocations within the same
  /// event return `null`.
  static Future<RainForecast?> check({
    WeatherProvider? weatherProvider,
    DateTime? nowUtcOverride,
  }) async {
    final location = await readLocation();
    if (location == null) return null;

    final now = nowUtcOverride ?? DateTime.now().toUtc();
    final provider = weatherProvider ?? OpenMeteoService();

    final result = await provider.fetchMinutelyForecast(
      lat: location.lat,
      lon: location.lon,
      useCache: false,
    );

    if (result is! Ok<MinutelyForecast>) return null;
    final minutely = result.value;

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
  }
}
