
abstract class WeatherProvider {
  Future<Map<String, dynamic>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  });
}
