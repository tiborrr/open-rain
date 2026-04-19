import '../models/weather_models.dart';
import '../providers/weather_provider.dart';
import '../utils/result.dart';
import 'weather_alert_analyzer.dart';

/// Repository for [WeatherData].
///
/// Delegates raw fetching+parsing to a [WeatherProvider] (e.g. Open-Meteo)
/// and layers cross-cutting business logic on top:
///   * alert analysis (severe weather)
///
/// Returns a [Result] so callers see failures explicitly instead of
/// inheriting whatever exception bubbled out of HTTP/parsing.
class WeatherRepository {
  WeatherRepository(this._provider);

  final WeatherProvider _provider;

  Future<Result<WeatherData>> getWeatherData({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final providerResult = await _provider.fetchWeather(
      lat: lat,
      lon: lon,
      startTime: startTime,
      endTime: endTime,
    );

    return switch (providerResult) {
      Ok<WeatherData>(value: final data) => Result.ok(_enrich(data)),
      Err<WeatherData>(error: final e) => Result.err(e),
    };
  }

  WeatherData _enrich(WeatherData data) {
    final alert = WeatherAlertAnalyzer.analyze(
      current: data.current,
      minutely: data.minutely,
    );
    if (alert == null) return data;
    return WeatherData(
      current: data.current,
      hourly: data.hourly,
      minutely: data.minutely,
      daily: data.daily,
      utcOffset: data.utcOffset,
      timezone: data.timezone,
      airQuality: data.airQuality,
      alert: alert,
      neighbors: data.neighbors,
    );
  }
}
