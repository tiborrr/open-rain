import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/services/rain_check_runner.dart';
import 'package:flutter_weather/utils/result.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeWeatherProvider implements WeatherProvider {
  _FakeWeatherProvider({this.minutelyResult});

  Result<MinutelyForecast>? minutelyResult;

  double? lastLat;
  double? lastLon;
  int? lastForecastSteps;
  bool? lastUseCache;

  @override
  Future<Result<WeatherData>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return Result.err(Exception('Not implemented'));
  }

  @override
  Future<Result<MinutelyForecast>> fetchMinutelyForecast({
    required double lat,
    required double lon,
    int forecastSteps = 8,
    bool useCache = true,
  }) async {
    lastLat = lat;
    lastLon = lon;
    lastForecastSteps = forecastSteps;
    lastUseCache = useCache;
    return minutelyResult ?? Result.err(Exception('No minutely result configured'));
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('returns null when no location is saved', () async {
    final fakeProvider = _FakeWeatherProvider();
    final result = await RainCheckRunner.check(weatherProvider: fakeProvider);

    expect(result, isNull);
    expect(fakeProvider.lastLat, isNull);
  });

  test('returns null when weather provider returns an error', () async {
    await RainCheckRunner.saveLocation(52.3676, 4.9041);
    final fakeProvider = _FakeWeatherProvider(
      minutelyResult: Result.err(Exception('Network error')),
    );

    final result = await RainCheckRunner.check(weatherProvider: fakeProvider);
    expect(result, isNull);
    expect(fakeProvider.lastLat, 52.3676);
    expect(fakeProvider.lastLon, 4.9041);
    expect(fakeProvider.lastUseCache, isFalse);
  });

  test('returns forecast and dedupes on subsequent check for same event', () async {
    await RainCheckRunner.saveLocation(52.3676, 4.9041);

    final now = DateTime.utc(2024, 6, 1, 12);
    final rainStart = now.add(const Duration(minutes: 10));

    final fakeProvider = _FakeWeatherProvider(
      minutelyResult: Result.ok(
        MinutelyForecast(
          times: [
            now,
            rainStart,
            rainStart.add(const Duration(minutes: 15)),
          ],
          precipitation: const [0.0, 1.5, 2.0],
        ),
      ),
    );

    // First check finds imminent rain and notifies
    final firstResult = await RainCheckRunner.check(
      weatherProvider: fakeProvider,
      nowUtcOverride: now,
    );

    expect(firstResult, isNotNull);
    expect(firstResult!.startUtc, rainStart);
    expect(firstResult.duration, const Duration(minutes: 30));

    // Second check within same event is deduped
    final secondResult = await RainCheckRunner.check(
      weatherProvider: fakeProvider,
      nowUtcOverride: now.add(const Duration(minutes: 2)),
    );

    expect(secondResult, isNull);
  });
}
