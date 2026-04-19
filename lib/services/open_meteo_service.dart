import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_models.dart';
import '../providers/weather_provider.dart';
import '../utils/cache_store.dart';
import '../utils/result.dart';

/// Open-Meteo client. Composes 4 endpoints (current/minutely, hourly, daily,
/// air quality) and parses them into a single [WeatherData] (no alert).
///
/// All endpoints share one [CacheStore]: the previous implementation
/// inlined identical SharedPreferences logic three times.
class OpenMeteoService implements WeatherProvider {
  OpenMeteoService({
    CacheStore? cacheStore,
    http.Client? httpClient,
  })  : _cache = cacheStore ?? CacheStore(),
        _http = httpClient ?? http.Client();

  static const String _host = 'api.open-meteo.com';
  static const String _airQualityHost = 'air-quality-api.open-meteo.com';

  /// Cap for how many 15-min steps we ever request from Open-Meteo. Open-Meteo
  /// publishes minutely_15 up to ~16 days; we never need more than the radar
  /// horizon (~2-3 h). Acts as a safety bound on the count derived from
  /// `endTime`.
  static const int _maxMinutelyForecastSteps = 192;

  final CacheStore _cache;
  final http.Client _http;

  @override
  Future<Result<WeatherData>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      final results = await Future.wait([
        _fetchMinutely(lat, lon, start: startTime, end: endTime),
        _fetchHourly(lat, lon),
        _fetchDaily(lat, lon),
        _fetchAirQuality(lat, lon),
      ]);

      final minutelyJson = results[0];
      final hourlyJson = results[1];
      final dailyJson = results[2];
      final airQualityJson = results[3];

      final offsetSeconds = (minutelyJson['utc_offset_seconds'] as num).toInt();
      final currentMap = Map<String, dynamic>.from(minutelyJson['current']);
      currentMap['latitude'] = minutelyJson['latitude'];
      currentMap['longitude'] = minutelyJson['longitude'];

      return Result.ok(
        WeatherData(
          current: CurrentWeather.fromJson(currentMap),
          hourly: HourlyForecast.fromJson(hourlyJson['hourly'], offsetSeconds),
          minutely: MinutelyForecast.fromJson(
              minutelyJson['minutely_15'], offsetSeconds),
          daily: DailyForecast.fromJson(dailyJson['daily'], offsetSeconds),
          utcOffset: Duration(seconds: offsetSeconds),
          timezone: minutelyJson['timezone'] as String,
          airQuality: airQualityJson['current'] != null
              ? AirQuality.fromJson(
                  Map<String, dynamic>.from(airQualityJson['current']))
              : null,
        ),
      );
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
  }

  Future<Map<String, dynamic>> _fetchMinutely(
    double lat,
    double lon, {
    DateTime? start,
    DateTime? end,
  }) async {
    // Use count-based windowing (`past_minutely_15` / `forecast_minutely_15`)
    // instead of `start_minutely_15` / `end_minutely_15`.
    //
    // Open-Meteo with `timezone=auto` interprets absolute `start_*`/`end_*`
    // values as the *location's local time*. Sending UTC ISO strings was
    // therefore being read as local time, which silently shifted the chart
    // window by the location's UTC offset (e.g. 2h of "past" data instead of
    // the requested future window for Europe in DST).
    //
    // Counts are timezone-agnostic and always anchored at "now".
    final forecastSteps = _forecastMinutelyStepsFor(end);
    final key = 'weather_minutely_${lat}_${lon}_$forecastSteps';
    final raw = await _cache.getOrFetch(
      key: key,
      expiresAt: CacheExpiration.alignedNext(15, 2),
      fetch: () async {
        final params = <String, String>{
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current':
              'temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_gusts_10m',
          'minutely_15': 'precipitation',
          'timezone': 'auto',
          'past_minutely_15': '0',
          'forecast_minutely_15': forecastSteps.toString(),
        };
        return _getJson(Uri.https(_host, '/v1/forecast', params),
            failure: 'Failed to load minutely weather data');
      },
    );
    return Map<String, dynamic>.from(raw);
  }

  /// Number of 15-min steps from "now" that covers up to [end], inclusive.
  ///
  /// Open-Meteo returns N points where the LAST point sits at
  /// `start + (N - 1) * 15 min`. Using `ceil(minutesAhead / 15)` would place
  /// the final sample one bucket *short* of [end], so the chart would stop
  /// ~15 min before the last radar frame. We add one step to guarantee
  /// `times.last >= end`. The caller (HomeViewModel) clips the KNMI frame
  /// list to the actual returned range, so a tiny overshoot is harmless.
  int _forecastMinutelyStepsFor(DateTime? end) {
    const fallback = 12; // 3 hours
    if (end == null) return fallback;
    final minutesAhead =
        end.toUtc().difference(DateTime.now().toUtc()).inMinutes;
    if (minutesAhead <= 0) return 2;
    final steps = ((minutesAhead + 14) ~/ 15) + 1;
    if (steps > _maxMinutelyForecastSteps) return _maxMinutelyForecastSteps;
    return steps;
  }

  Future<Map<String, dynamic>> _fetchHourly(double lat, double lon) async {
    final key = 'weather_hourly_${lat}_$lon';
    final raw = await _cache.getOrFetch(
      key: key,
      expiresAt: CacheExpiration.alignedNext(60, 2),
      fetch: () => _getJson(
        Uri.https(_host, '/v1/forecast', {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'hourly':
              'temperature_2m,precipitation_probability,weather_code,wind_gusts_10m',
          'timezone': 'auto',
          'forecast_days': '14',
        }),
        failure: 'Failed to load hourly weather data',
      ),
    );
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> _fetchDaily(double lat, double lon) async {
    final key = 'weather_daily_${lat}_$lon';
    final raw = await _cache.getOrFetch(
      key: key,
      expiresAt: CacheExpiration.alignedNext(360, 5),
      fetch: () => _getJson(
        Uri.https(_host, '/v1/forecast', {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
          'timezone': 'auto',
          'forecast_days': '14',
        }),
        failure: 'Failed to load daily weather data',
      ),
    );
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> _fetchAirQuality(double lat, double lon) async {
    final key = 'weather_air_quality_${lat}_$lon';
    final raw = await _cache.getOrFetch(
      key: key,
      expiresAt: CacheExpiration.alignedNext(60, 5),
      // Air quality is non-essential: tolerate failures by returning {} so the
      // rest of the dashboard still loads.
      fetch: () async {
        try {
          return await _getJson(
            Uri.https(_airQualityHost, '/v1/air-quality', {
              'latitude': lat.toString(),
              'longitude': lon.toString(),
              'current': 'european_aqi,pm2_5,ozone',
              'timezone': 'auto',
            }),
            failure: 'air quality unavailable',
          );
        } catch (_) {
          return <String, dynamic>{};
        }
      },
    );
    return raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
  }

  Future<dynamic> _getJson(Uri uri, {required String failure}) async {
    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('$failure (${response.statusCode})');
    }
    return json.decode(response.body);
  }
}
