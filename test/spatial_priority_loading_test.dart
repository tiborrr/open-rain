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
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MockLocationProvider implements LocationProvider {
  @override
  Future<ResolvedLocation> getCurrentLocation() async =>
      const ResolvedLocation(lat: 52.3676, lon: 4.9041, name: 'Amsterdam');

  @override
  Stream<ResolvedLocation> getSignificantLocationUpdates({
    double minDistanceMeters = 100.0,
  }) =>
      const Stream.empty();

  @override
  Future<Result<List<LocationResult>>> searchLocations(String query) async =>
      const Result.ok([]);
}

class MockWeatherProvider implements WeatherProvider {
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
          temperature: 15,
          humidity: 80,
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
        minutely: MinutelyForecast(times: const [], precipitation: const []),
        daily: DailyForecast(
          times: const [],
          maxTemps: const [],
          minTemps: const [],
          weatherCodes: const [],
        ),
        utcOffset: const Duration(hours: 1),
        timezone: 'Europe/Amsterdam',
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
      MinutelyForecast(times: const [], precipitation: const []),
    );
  }
}

class MockRadarProvider implements RadarProvider {
  final List<LatLng> callOrder = [];

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames({
    bool forceRefresh = false,
  }) async => Result.ok([
    RadarFrame(frameId: '2024-01-01T00:00:00Z', time: DateTime.now()),
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
  }) async {
    callOrder.add(LatLng(lat, lon));
    return Result.ok(
      MinutelyForecast(times: const [], precipitation: const []),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'HomeViewModel should fetch center first, then neighbors by distance',
    () async {
      final mockRadarProvider = MockRadarProvider();
      final nowcastService = PrecipitationNowcastService(
        radarProvider: mockRadarProvider,
        weatherProvider: MockWeatherProvider(),
      );

      final viewModel = HomeViewModel(
        nowcastService: nowcastService,
        locationProvider: MockLocationProvider(),
      );

      await viewModel.loadDashboard.execute(
        const LocationSelection(lat: 52.3676, lon: 4.9041, name: 'Amsterdam'),
      );

      // Background neighbor fetch fires-and-forgets after the command completes.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final calls = mockRadarProvider.callOrder;
      expect(calls.length, 9);
      expect(calls.first.latitude, closeTo(52.3676, 1e-6));
      expect(calls.first.longitude, closeTo(4.9041, 1e-6));

      final neighborCalls = calls.skip(1).toList();
      for (var i = 0; i < neighborCalls.length - 1; i++) {
        final distCurrent = Geolocator.distanceBetween(
          52.3676,
          4.9041,
          neighborCalls[i].latitude,
          neighborCalls[i].longitude,
        );
        final distNext = Geolocator.distanceBetween(
          52.3676,
          4.9041,
          neighborCalls[i + 1].latitude,
          neighborCalls[i + 1].longitude,
        );
        expect(
          distCurrent <= distNext,
          isTrue,
          reason: 'Call at index $i is further than call at index ${i + 1}',
        );
      }

      expect(viewModel.weatherData?.neighbors.length, 8);
    },
  );
}
