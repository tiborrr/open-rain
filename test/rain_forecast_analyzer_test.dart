import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/services/rain_forecast_analyzer.dart';

void main() {
  group('RainForecastAnalyzer.analyze', () {
    // Anchor "now" to an aligned 15-min boundary so the grid math is easy
    // to read: t0 = now, t1 = now+15m, t2 = now+30m, ...
    final now = DateTime.utc(2026, 4, 20, 12, 0);
    MinutelyForecast forecastFrom(List<double> precip) {
      final times = List<DateTime>.generate(
        precip.length,
        (i) => now.add(Duration(minutes: 15 * i)),
      );
      return MinutelyForecast(times: times, precipitation: precip);
    }

    test('returns null when all future buckets are dry', () {
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.0, 0.0, 0.0, 0.0]),
        nowUtc: now,
      );
      expect(forecast, isNull);
    });

    test('returns null when it is already raining right now', () {
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.5, 0.5, 0.0, 0.0]),
        nowUtc: now.add(const Duration(minutes: 5)),
      );
      expect(forecast, isNull);
    });

    test('ignores rain that starts beyond the 20-min lookahead', () {
      // Rain only at t+45m, which is past the 20-minute lookahead.
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.0, 0.0, 0.0, 2.0]),
        nowUtc: now,
      );
      expect(forecast, isNull);
    });

    test('fires for rain starting within 20 minutes', () {
      // Dry at t0 (covers now), wet at t+15m for two buckets, dry after.
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.0, 0.3, 0.2, 0.0]),
        nowUtc: now,
      );
      expect(forecast, isNotNull);
      expect(forecast!.startUtc, now.add(const Duration(minutes: 15)));
      expect(forecast.untilStart, const Duration(minutes: 15));
      expect(forecast.duration, const Duration(minutes: 30));
    });

    test('duration covers contiguous wet buckets only', () {
      // 3 contiguous wet buckets starting at t+15m, then a dry bucket, then
      // more rain that should NOT extend the duration.
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.0, 0.4, 0.4, 0.4, 0.0, 0.5]),
        nowUtc: now,
      );
      expect(forecast, isNotNull);
      expect(forecast!.duration, const Duration(minutes: 45));
    });

    test('sub-threshold precipitation is treated as dry', () {
      final forecast = RainForecastAnalyzer.analyze(
        minutely: forecastFrom([0.0, 0.05, 0.09, 0.0]),
        nowUtc: now,
      );
      expect(forecast, isNull);
    });

    test('returns null on empty forecast', () {
      final forecast = RainForecastAnalyzer.analyze(
        minutely: MinutelyForecast(times: const [], precipitation: const []),
        nowUtc: now,
      );
      expect(forecast, isNull);
    });
  });
}
