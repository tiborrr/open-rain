import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  /// Fetches the current position of the device.
  /// 
  /// Throws an exception if permissions are denied or services are disabled.
  Future<Position> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    // First, try for the last known position to be faster
    final lastPosition = await Geolocator.getLastKnownPosition();
    if (lastPosition != null) {
      return lastPosition;
    }
    
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    ).timeout(const Duration(seconds: 10));
  }

  /// Translates coordinates into a city name.
  Future<String?> getCityFromCoordinates(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return place.locality ?? place.subAdministrativeArea ?? place.administrativeArea;
      }
    } catch (_) {
      // Ignore geocoding errors, just return null
    }
    return null;
  }

  /// Returns a stream of location updates.
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100, // Notify only when distance changes by 100m
      ),
    );
  }

  /// Searches for coordinates from a query string.
  Future<List<LocationResult>> searchLocations(String query) async {
    try {
      List<Location> locations = await locationFromAddress(query);
      List<LocationResult> results = [];
      
      for (var loc in locations) {
        // Reverse geocode to get a nice name
        final city = await getCityFromCoordinates(loc.latitude, loc.longitude);
        results.add(LocationResult(
          name: city ?? query,
          latitude: loc.latitude,
          longitude: loc.longitude,
        ));
      }
      return results;
    } catch (_) {
      return [];
    }
  }
}

class LocationResult {
  final String name;
  final double latitude;
  final double longitude;

  LocationResult({required this.name, required this.latitude, required this.longitude});
}
