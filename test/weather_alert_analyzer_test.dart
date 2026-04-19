import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/repositories/weather_alert_analyzer.dart';

CurrentWeather _current({double temp = 20, double gust = 5}) => CurrentWeather(
      temperature: temp,
      humidity: 50,
      precipitation: 0,
      weatherCode: 1,
      windGust: gust,
      lat: 0,
      lon: 0,
    );

void main() {
  group('WeatherAlertAnalyzer', () {
    test('returns null when nothing is severe', () {
      final alert = WeatherAlertAnalyzer.analyze(
        current: _current(),
        minutely: MinutelyForecast(
          times: [DateTime.utc(2024)],
          precipitation: const [0.1],
        ),
      );
      expect(alert, isNull);
    });

    test('flags heavy rain in lookahead window', () {
      final alert = WeatherAlertAnalyzer.analyze(
        current: _current(),
        minutely: MinutelyForecast(
          times: List.generate(8, (i) => DateTime.utc(2024, 1, 1, 0, 15 * i)),
          precipitation: const [0, 0, 6.0, 0, 0, 0, 0, 0],
        ),
      );
      expect(alert?.type, 'danger');
      expect(alert?.title, contains('Heavy Rain'));
    });

    test('ignores heavy rain past the lookahead', () {
      final alert = WeatherAlertAnalyzer.analyze(
        current: _current(),
        minutely: MinutelyForecast(
          times: List.generate(10, (i) => DateTime.utc(2024, 1, 1, 0, 15 * i)),
          precipitation: const [0, 0, 0, 0, 0, 0, 0, 0, 99, 99],
        ),
      );
      expect(alert, isNull);
    });

    test('flags heat advisory above threshold', () {
      final alert = WeatherAlertAnalyzer.analyze(
        current: _current(temp: 36),
        minutely: MinutelyForecast(times: const [], precipitation: const []),
      );
      expect(alert?.type, 'warning');
    });

    test('rain takes precedence over heat', () {
      final alert = WeatherAlertAnalyzer.analyze(
        current: _current(temp: 40),
        minutely: MinutelyForecast(
          times: [DateTime.utc(2024)],
          precipitation: const [10.0],
        ),
      );
      expect(alert?.type, 'danger');
    });
  });
}
