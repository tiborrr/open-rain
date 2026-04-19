import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';

void main() {
  group('MinutelyForecast.nearestTimeUtcToMillis', () {
    test('returns null when times is empty', () {
      final forecast = MinutelyForecast(times: const [], precipitation: const []);
      expect(forecast.nearestTimeUtcToMillis(DateTime.utc(2024, 4, 2, 12).millisecondsSinceEpoch), isNull);
    });

    test('returns the only entry when times has one point', () {
      final only = DateTime.utc(2024, 4, 2, 12);
      final forecast = MinutelyForecast(times: [only], precipitation: const [0.1]);
      final query = DateTime.utc(2024, 4, 2, 18).millisecondsSinceEpoch;
      expect(forecast.nearestTimeUtcToMillis(query), only);
    });

    test('picks the closer of two surrounding points', () {
      final earlier = DateTime.utc(2024, 4, 2, 12, 0);
      final later = DateTime.utc(2024, 4, 2, 12, 15);
      final forecast = MinutelyForecast(times: [earlier, later], precipitation: const [0.0, 0.0]);

      final closeToEarlier = DateTime.utc(2024, 4, 2, 12, 5).millisecondsSinceEpoch;
      final closeToLater = DateTime.utc(2024, 4, 2, 12, 12).millisecondsSinceEpoch;

      expect(forecast.nearestTimeUtcToMillis(closeToEarlier), earlier);
      expect(forecast.nearestTimeUtcToMillis(closeToLater), later);
    });

    test('on exact tie, prefers the earlier timestamp', () {
      final earlier = DateTime.utc(2024, 4, 2, 12, 0);
      final later = DateTime.utc(2024, 4, 2, 12, 10);
      final forecast = MinutelyForecast(times: [earlier, later], precipitation: const [0.0, 0.0]);

      final midpoint = DateTime.utc(2024, 4, 2, 12, 5).millisecondsSinceEpoch;
      expect(forecast.nearestTimeUtcToMillis(midpoint), earlier);
    });
  });
}
