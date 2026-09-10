import '../models/weather_models.dart';
import '../utils/result.dart';

/// Source of weather data for a location.
///
/// Implementations fetch upstream weather data, analyze severe weather alerts,
/// and parse responses into complete [WeatherData] instances before returning.
abstract class WeatherProvider {
  Future<Result<WeatherData>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  });

  /// Fetches 15-minute resolution precipitation forecast data for [lat]/[lon].
  ///
  /// Used by background rain alert checkers or progressive precipitation nowcasts.
  /// When [useCache] is false, bypasses any in-memory cached responses.
  Future<Result<MinutelyForecast>> fetchMinutelyForecast({
    required double lat,
    required double lon,
    int forecastSteps = 8,
    bool useCache = true,
  });
}
