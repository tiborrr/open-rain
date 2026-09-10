import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/radar_frame.dart';
import 'package:flutter_weather/models/radar_layer_config.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/providers/location_provider.dart';
import 'package:flutter_weather/providers/radar_provider.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/services/precipitation_nowcast_service.dart';
import 'package:flutter_weather/utils/result.dart';
import 'package:flutter_weather/view_models/home_view_model.dart';

class _FixedLocationProvider implements LocationProvider {
  @override
  Future<ResolvedLocation> getCurrentLocation() async =>
      const ResolvedLocation(lat: 52.0, lon: 5.0, name: 'Test');

  @override
  Stream<ResolvedLocation> getSignificantLocationUpdates({
    double minDistanceMeters = 100.0,
  }) =>
      const Stream.empty();

  @override
  Future<Result<List<LocationResult>>> searchLocations(String query) async =>
      const Result.ok([]);
}

class _OpenMeteoWithMinutely implements WeatherProvider {
  @override
  Future<Result<WeatherData>> fetchWeather({
    required double lat,
    required double lon,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return Result.ok(
      WeatherData(
        current: CurrentWeather(
          temperature: 10,
          humidity: 50,
          precipitation: 0,
          weatherCode: 1,
          windGust: 5,
          lat: lat,
          lon: lon,
        ),
        hourly: HourlyForecast(
          times: const [],
          temperatures: const [],
          weatherCodes: const [],
        ),
        minutely: MinutelyForecast(
          times: [
            DateTime.utc(2024, 4, 2, 12),
            DateTime.utc(2024, 4, 2, 12, 15),
          ],
          precipitation: const [0.25, 0.5],
        ),
        daily: DailyForecast(
          times: const [],
          maxTemps: const [],
          minTemps: const [],
          weatherCodes: const [],
        ),
        utcOffset: Duration.zero,
        timezone: 'UTC',
      ),
    );
  }

  @override
  Future<Result<MinutelyForecast>> fetchMinutelyForecast({
    required double lat,
    required double lon,
    int forecastSteps = 8,
    bool useCache = true,
  }) async {
    return Result.ok(
      MinutelyForecast(
        times: [
          DateTime.utc(2024, 4, 2, 12),
          DateTime.utc(2024, 4, 2, 12, 15),
        ],
        precipitation: const [0.25, 0.5],
      ),
    );
  }
}

class _KnmiStyleRadar implements RadarProvider {
  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames({
    bool forceRefresh = false,
  }) async => Result.ok([
    RadarFrame(
      frameId: '2024-04-02T12:00:00Z',
      time: DateTime.utc(2024, 4, 2, 12),
    ),
  ]);

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) =>
      RadarLayerConfig(urlTemplate: 'https://example/{z}/{x}/{y}.png');

  @override
  void invalidateCaches() {}

  @override
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async => Result.ok(
    MinutelyForecast(
      times: [DateTime.utc(2024, 4, 2, 12), DateTime.utc(2024, 4, 2, 13)],
      precipitation: const [99.0, 99.0],
    ),
  );
}

class _NoKnmiSeriesRadar extends _KnmiStyleRadar {
  @override
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async => const Result.ok(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'HomeViewModel uses KNMI GFI minutely for chart when available',
    () async {
      final vm = HomeViewModel(
        nowcastService: PrecipitationNowcastService(
          radarProvider: _KnmiStyleRadar(),
          weatherProvider: _OpenMeteoWithMinutely(),
        ),
        locationProvider: _FixedLocationProvider(),
      );

      await vm.loadDashboard.execute(
        const LocationSelection(lat: 52.0, lon: 5.0, name: 'Test'),
      );

      expect(vm.weatherData, isNotNull);
      expect(vm.weatherData!.minutely.precipitation, [99.0, 99.0]);
    },
  );

  test(
    'HomeViewModel falls back to Open-Meteo minutely when KNMI GFI is empty',
    () async {
      final vm = HomeViewModel(
        nowcastService: PrecipitationNowcastService(
          radarProvider: _NoKnmiSeriesRadar(),
          weatherProvider: _OpenMeteoWithMinutely(),
        ),
        locationProvider: _FixedLocationProvider(),
      );

      await vm.loadDashboard.execute(
        const LocationSelection(lat: 52.0, lon: 5.0, name: 'Test'),
      );

      expect(vm.weatherData, isNotNull);
      expect(vm.weatherData!.minutely.precipitation, [0.25, 0.5]);
    },
  );
}
