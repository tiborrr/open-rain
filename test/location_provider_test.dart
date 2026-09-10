import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class _FailingLocationService extends LocationService {
  @override
  Future<Position> getCurrentPosition() async {
    throw Exception('GPS disabled');
  }
}

class _SuccessfulLocationService extends LocationService {
  @override
  Future<Position> getCurrentPosition() async {
    return Position(
      latitude: 51.9244,
      longitude: 4.4777,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  @override
  Future<String?> getCityFromCoordinates(double lat, double lon) async {
    return 'Rotterdam';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Location Models Tests', () {
    test('ResolvedLocation equality and fields', () {
      const loc1 = ResolvedLocation(
        lat: 52.3676,
        lon: 4.9041,
        name: 'Amsterdam',
      );
      const loc2 = ResolvedLocation(
        lat: 52.3676,
        lon: 4.9041,
        name: 'Amsterdam',
      );
      const loc3 = ResolvedLocation(
        lat: 52.0,
        lon: 5.0,
        name: 'Utrecht',
        isFallback: true,
        fallbackMessage: 'Warning',
      );

      expect(loc1, equals(loc2));
      expect(loc1.hashCode, equals(loc2.hashCode));
      expect(loc1, isNot(equals(loc3)));
      expect(loc3.isFallback, isTrue);
      expect(loc3.fallbackMessage, 'Warning');
    });

    test('LocationResult equality and getters', () {
      const res1 = LocationResult(
        name: 'Utrecht',
        latitude: 52.0907,
        longitude: 5.1214,
      );
      const res2 = LocationResult(
        name: 'Utrecht',
        latitude: 52.0907,
        longitude: 5.1214,
      );

      expect(res1, equals(res2));
      expect(res1.lat, 52.0907);
      expect(res1.lon, 5.1214);
    });
  });

  group('LocationService / LocationProvider Implementation Tests', () {
    test('getCurrentLocation falls back safely when GPS throws', () async {
      final service = _FailingLocationService();
      final resolved = await service.getCurrentLocation();

      expect(resolved.isFallback, isTrue);
      expect(resolved.lat, LocationService.defaultFallbackLat);
      expect(resolved.lon, LocationService.defaultFallbackLon);
      expect(resolved.name, LocationService.defaultFallbackName);
      expect(resolved.fallbackMessage, contains('Location disabled'));
    });

    test('getCurrentLocation returns resolved coordinate and city name on success', () async {
      final service = _SuccessfulLocationService();
      final resolved = await service.getCurrentLocation();

      expect(resolved.isFallback, isFalse);
      expect(resolved.lat, 51.9244);
      expect(resolved.lon, 4.4777);
      expect(resolved.name, 'Rotterdam');
      expect(resolved.fallbackMessage, isNull);
    });
  });
}
