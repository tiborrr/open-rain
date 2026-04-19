import '../models/weather_models.dart';
import '../utils/result.dart';

/// Source of weather data for a location.
///
/// Per the Flutter architecture guide, services own knowledge of the upstream
/// API shape: implementations parse responses into [WeatherData] before
/// returning. Repositories then add cross-cutting business logic such as
/// alert analysis. The returned [WeatherData] has `alert == null`; alerts
/// are computed in the repository layer.
abstract class WeatherProvider {
  Future<Result<WeatherData>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  });
}
