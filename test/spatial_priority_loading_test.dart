import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/radar_frame.dart';
import 'package:flutter_weather/models/radar_layer_config.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/providers/radar_provider.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/repositories/radar_repository.dart';
import 'package:flutter_weather/repositories/weather_repository.dart';
import 'package:flutter_weather/services/location_service.dart';
import 'package:flutter_weather/utils/result.dart';
import 'package:flutter_weather/view_models/home_view_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MockLocationService extends LocationService {
  @override
  Future<Position> getCurrentPosition() async => _pos(52.3676, 4.9041);

  @override
  Future<String?> getCityFromCoordinates(double lat, double lon) async =>
      'Amsterdam';

  @override
  Stream<Position> getPositionStream() => const Stream.empty();

  Position _pos(double lat, double lon) => Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.now(),
    accuracy: 0,
    altitude: 0,
    heading: 0,
    speed: 0,
    speedAccuracy: 0,
    altitudeAccuracy: 0,
    headingAccuracy: 0,
  );
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
}

class MockRadarProvider implements RadarProvider {
  final List<LatLng> callOrder = [];

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames() async => Result.ok([
    RadarFrame(frameId: '2024-01-01T00:00:00Z', time: DateTime.now()),
  ]);

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) =>
      RadarLayerConfig(urlTemplate: 'https://example/{z}/{x}/{y}.png');

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
      final radarRepo = RadarRepository(mockRadarProvider);
      final weatherRepo = WeatherRepository(MockWeatherProvider());

      final viewModel = HomeViewModel(
        weatherRepository: weatherRepo,
        radarRepository: radarRepo,
        locationService: MockLocationService(),
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
