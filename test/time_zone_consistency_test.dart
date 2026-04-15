import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';

void main() {
  group('Time Zone Consistency', () {
    test('WeatherData.localNow should return accurate local time for a specific offset', () {
      final weather = WeatherData(
        current: CurrentWeather(temperature: 20, humidity: 50, precipitation: 0, weatherCode: 1, windGust: 10, lat: 0, lon: 0),
        hourly: HourlyForecast(times: [], temperatures: [], weatherCodes: []),
        minutely: MinutelyForecast(times: [], precipitation: []),
        daily: DailyForecast(times: [], maxTemps: [], minTemps: [], weatherCodes: []),
        utcOffset: const Duration(hours: 9), // Tokyo
        timezone: 'Asia/Tokyo',
      );

      final nowUtc = DateTime.now().toUtc();
      final expectedLocal = nowUtc.add(const Duration(hours: 9));
      
      // Allow 1 second tolerance for execution time
      expect(weather.localNow.difference(expectedLocal).inSeconds.abs() <= 1, true);
    });

    test('toLocalLocation should correctly convert a specific UTC time', () {
       final weather = WeatherData(
        current: CurrentWeather(temperature: 20, humidity: 50, precipitation: 0, weatherCode: 1, windGust: 10, lat: 0, lon: 0),
        hourly: HourlyForecast(times: [], temperatures: [], weatherCodes: []),
        minutely: MinutelyForecast(times: [], precipitation: []),
        daily: DailyForecast(times: [], maxTemps: [], minTemps: [], weatherCodes: []),
        utcOffset: const Duration(hours: -5), // New York
        timezone: 'America/New_York',
      );

      final utcTime = DateTime.parse('2024-04-02T12:00:00Z');
      final localTime = weather.toLocalLocation(utcTime);

      expect(localTime.hour, 7);
      expect(localTime.day, 2);
    });

    test('parseTime should convert local time to UTC using the offset', () {
      final t1 = WeatherData.parseTime('2024-04-02T12:00:00', 3600); // 12:00 local (UTC+1)
      final t2 = WeatherData.parseTime('2024-04-02T11:00:00Z'); // 11:00 UTC
      
      expect(t1.isUtc, true);
      expect(t2.isUtc, true);
      expect(t1, t2);
    });
  });
}
