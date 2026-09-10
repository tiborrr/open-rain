import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/providers/location_provider.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/services/open_meteo_service.dart';
import 'package:flutter_weather/services/precipitation_nowcast_service.dart';
import 'package:flutter_weather/services/rainviewer_service.dart';
import 'package:flutter_weather/utils/result.dart';
import 'package:flutter_weather/view_models/home_view_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Flutter's test binding stubs [http.Client] to HTTP 400. These tests exercise
/// repository + view-model wiring with deterministic JSON instead of the network.
Future<http.Response> _stubWeatherHttp(http.Request request) async {
  final uri = request.url;
  if (uri.host == 'api.open-meteo.com' && uri.path == '/v1/forecast') {
    final q = uri.queryParameters;
    if (q.containsKey('minutely_15')) {
      // Keep minutely window in sync with RainViewer stub unix times below so
      // HomeViewModel._alignFramesToMinutely retains frames.
      return http.Response(
        json.encode({
          'utc_offset_seconds': 0,
          'latitude': 52.3676,
          'longitude': 4.9041,
          'timezone': 'UTC',
          'current': {
            'time': '2024-05-29T16:30:00',
            'temperature_2m': 15.0,
            'relative_humidity_2m': 70,
            'precipitation': 0.0,
            'weather_code': 0,
            'wind_gusts_10m': 10.0,
          },
          'minutely_15': {
            'time': [
              '2024-05-29T16:15:00',
              '2024-05-29T16:30:00',
              '2024-05-29T16:45:00',
            ],
            'precipitation': [0.0, 0.05, 0.1],
          },
        }),
        200,
      );
    }
    if (q.containsKey('hourly')) {
      return http.Response(
        json.encode({
          'hourly': {
            'time': ['2024-05-29T16:00:00', '2024-05-29T17:00:00'],
            'temperature_2m': [15.0, 16.0],
            'weather_code': [0, 0],
          },
        }),
        200,
      );
    }
    if (q.containsKey('daily')) {
      return http.Response(
        json.encode({
          'daily': {
            'time': ['2024-05-29', '2024-05-30'],
            'temperature_2m_max': [18.0, 19.0],
            'temperature_2m_min': [10.0, 11.0],
            'weather_code': [0, 0],
          },
        }),
        200,
      );
    }
  }
  if (uri.host == 'air-quality-api.open-meteo.com') {
    return http.Response(
      json.encode({
        'current': {
          'european_aqi': 25,
          'pm2_5': 5.0,
          'ozone': 30.0,
        },
      }),
      200,
    );
  }
  if (uri.host == 'api.rainviewer.com' &&
      uri.path == '/public/weather-maps.json') {
    return http.Response(
      json.encode({
        'radar': {
          'past': [
            {'path': 'v2/1/1/1/1/1/0_0_1.png', 'time': 1717000000},
          ],
          'nowcast': [
            {'path': 'v2/1/1/1/1/1/0_0_2.png', 'time': 1717000900},
          ],
        },
      }),
      200,
    );
  }
  return http.Response('not found', 404);
}

class MockLocationProvider implements LocationProvider {
  @override
  Future<ResolvedLocation> getCurrentLocation() async {
    return const ResolvedLocation(
      lat: 52.3676,
      lon: 4.9041,
      name: 'Amsterdam',
    );
  }

  @override
  Stream<ResolvedLocation> getSignificantLocationUpdates({
    double minDistanceMeters = 100.0,
  }) =>
      const Stream.empty();

  @override
  Future<Result<List<LocationResult>>> searchLocations(String query) async =>
      const Result.ok([]);
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('MVVM Architecture Integration Tests', () {
    late WeatherProvider weatherProvider;
    late HomeViewModel viewModel;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final httpClient = MockClient(_stubWeatherHttp);
      weatherProvider = OpenMeteoService(httpClient: httpClient);
      final radarProvider = RainViewerService(httpClient: httpClient);
      final nowcastService = PrecipitationNowcastService(
        radarProvider: radarProvider,
        weatherProvider: weatherProvider,
      );

      viewModel = HomeViewModel(
        nowcastService: nowcastService,
        locationProvider: MockLocationProvider(),
      );
    });

    test('WeatherProvider should return typed WeatherData', () async {
      final result = await weatherProvider.fetchWeather(
        lat: 52.3676,
        lon: 4.9041,
      );

      expect(result, isA<Ok<WeatherData>>());
      final data = (result as Ok<WeatherData>).value;
      expect(data.current.temperature, isA<double>());
      expect(data.hourly.times, isNotEmpty);
      expect(data.minutely.precipitation, isNotEmpty);
    });

    test('HomeViewModel should manage dashboard state via the load command',
        () async {
      expect(viewModel.loadDashboard.running, isFalse);
      expect(viewModel.loadDashboard.completed, isFalse);

      final future = viewModel.loadDashboard.execute(
        const LocationSelection(
          lat: 52.3676,
          lon: 4.9041,
          name: 'Amsterdam',
        ),
      );
      expect(viewModel.loadDashboard.running, isTrue);

      await future;

      expect(viewModel.loadDashboard.running, isFalse);
      expect(viewModel.loadDashboard.completed, isTrue);
      expect(viewModel.weatherData, isNotNull);
      expect(viewModel.radarFrames, isNotEmpty);
    });

    test('WeatherProvider should return typed MinutelyForecast', () async {
      final result = await weatherProvider.fetchMinutelyForecast(
        lat: 52.3676,
        lon: 4.9041,
        useCache: false,
      );

      expect(result, isA<Ok<MinutelyForecast>>());
      final minutely = (result as Ok<MinutelyForecast>).value;
      expect(minutely.precipitation, isNotEmpty);
      expect(minutely.times, isNotEmpty);
    });

    test('WeatherProvider should detect alerts (smoke test)', () async {
      final result = await weatherProvider.fetchWeather(
        lat: 52.3676,
        lon: 4.9041,
      );
      expect(result, isA<Ok<WeatherData>>());
    });
  });
}
