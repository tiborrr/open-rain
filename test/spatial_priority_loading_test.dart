import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/models/radar_frame.dart';
import 'package:flutter_weather/view_models/home_view_model.dart';
import 'package:flutter_weather/repositories/weather_repository.dart';
import 'package:flutter_weather/repositories/radar_repository.dart';
import 'package:flutter_weather/services/location_service.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/providers/radar_provider.dart';
import 'package:flutter_weather/models/radar_layer_config.dart';

class MockLocationService extends LocationService {
  @override
  Future<Position> getCurrentPosition() async => _pos(52.3676, 4.9041);
  @override
  Future<String?> getCityFromCoordinates(double lat, double lon) async => 'Amsterdam';
  
  @override
  Stream<Position> getPositionStream() => const Stream.empty();
  
  Position _pos(double lat, double lon) => Position(
    latitude: lat, longitude: lon, timestamp: DateTime.now(),
    accuracy: 0, altitude: 0, heading: 0, speed: 0,
    speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
  );
}

class MockWeatherProvider extends WeatherProvider {
  @override
  Future<Map<String, dynamic>> fetchWeather({
    required double lat, required double lon, DateTime? startTime, DateTime? endTime,
  }) async => {
    'latitude': lat, 'longitude': lon, 'utc_offset_seconds': 3600, 'timezone': 'Europe/Amsterdam',
    'current': {'temperature_2m': 15.0, 'relative_humidity_2m': 80, 'precipitation': 0, 'weather_code': 1, 'wind_gusts_10m': 5.0},
    'hourly': {'time': [], 'temperature_2m': [], 'weather_code': []},
    'minutely_15': {'time': [], 'precipitation': []},
    'daily': {'time': [], 'temperature_2m_max': [], 'temperature_2m_min': [], 'weather_code': []},
  };
}

class MockRadarProvider extends RadarProvider {
  final List<LatLng> callOrder = [];

  @override
  Future<List<RadarFrame>> fetchRadarFrames() async => [
    RadarFrame(frameId: '2024-01-01T00:00:00Z', time: DateTime.now()),
  ];

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) => RadarLayerConfig(wmsOptions: null as dynamic);

  @override
  Future<MinutelyForecast?> fetchPrecipitationSeries({
    required double lat, required double lon, required List<RadarFrame> frames,
  }) async {
    callOrder.add(LatLng(lat, lon));
    return MinutelyForecast(times: [], precipitation: []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HomeViewModel should fetch center first then neighbors by distance', () async {
    final mockRadarProvider = MockRadarProvider();
    final radarRepo = RadarRepository(mockRadarProvider);
    final weatherRepo = WeatherRepository(MockWeatherProvider());
    
    final viewModel = HomeViewModel(
      weatherRepository: weatherRepo,
      radarRepository: radarRepo,
      locationService: MockLocationService(),
    );

    // Initial load for Amsterdam (52.3676, 4.9041)
    await viewModel.loadDashboard(lat: 52.3676, lon: 4.9041);

    // The loadDashboard finishes after the center point is fetched,
    // but the background neighbor fetch might still be running.
    // We wait a bit for background tasks to complete.
    await Future.delayed(const Duration(milliseconds: 500));

    final calls = mockRadarProvider.callOrder;
    
    // Total calls should be 1 (center) + 8 (neighbors) = 9
    expect(calls.length, 9);
    
    // First call must be the center point
    expect(calls[0].latitude, closeTo(52.3676, 0.0001));
    expect(calls[0].longitude, closeTo(4.9041, 0.0001));

    // Verify distance ordering for neighbors (calls[1] to calls[8])
    for (int i = 1; i < calls.length - 1; i++) {
      final distCurrent = Geolocator.distanceBetween(52.3676, 4.9041, calls[i].latitude, calls[i].longitude);
      final distNext = Geolocator.distanceBetween(52.3676, 4.9041, calls[i+1].latitude, calls[i+1].longitude);
      
      expect(distCurrent <= distNext, isTrue, reason: 'Call at index $i is further than call at index ${i+1}');
    }

    // Verify neighbors map in weatherData is populated
    expect(viewModel.weatherData?.neighbors.length, 8);
  });
}
