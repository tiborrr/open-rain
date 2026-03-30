import '../models/weather_models.dart';
import '../providers/weather_provider.dart';

class WeatherRepository {
  final WeatherProvider _provider;

  WeatherRepository(this._provider);

  Future<WeatherData> getWeatherData({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final rawData = await _provider.fetchWeather(
      lat: lat,
      lon: lon,
      startTime: startTime,
      endTime: endTime,
    );

    final currentMap = Map<String, dynamic>.from(rawData['current']);
    currentMap['latitude'] = rawData['latitude'];
    currentMap['longitude'] = rawData['longitude'];
    
    final current = CurrentWeather.fromJson(currentMap);
    final hourly = HourlyForecast.fromJson(rawData['hourly']);
    final minutely = MinutelyForecast.fromJson(rawData['minutely_15']);
    final daily = DailyForecast.fromJson(rawData['daily']);

    final alert = _analyzeAlerts(current, minutely);

    final airQuality = rawData['air_quality'] != null
        ? AirQuality.fromJson(Map<String, dynamic>.from(rawData['air_quality']))
        : null;

    return WeatherData(
      current: current,
      hourly: hourly,
      minutely: minutely,
      daily: daily,
      utcOffset: Duration(seconds: (rawData['utc_offset_seconds'] as num).toInt()),
      timezone: rawData['timezone'] as String,
      alert: alert,
      airQuality: airQuality,
    );
  }

  WeatherAlert? _analyzeAlerts(CurrentWeather current, MinutelyForecast minutely) {
    // Check for heavy rain in the next 2 hours (8 intervals of 15 min)
    bool willRainHeavily = false;
    final nextTwoHours = minutely.precipitation.take(8);
    for (var p in nextTwoHours) {
      if (p > 5.0) { // 5mm/15min is very heavy
        willRainHeavily = true;
        break;
      }
    }

    if (willRainHeavily) {
      return WeatherAlert(
        title: 'Heavy Rain Warning',
        message: 'Extreme precipitation expected in the next 2 hours.',
        type: 'danger',
      );
    }

    if (current.temperature > 35) {
      return WeatherAlert(
        title: 'Heat Advisory',
        message: 'Extreme heat detected. Stay hydrated.',
        type: 'warning',
      );
    }

    return null;
  }
}
