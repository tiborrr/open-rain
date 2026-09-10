import '../models/location_models.dart';
import '../utils/result.dart';

export '../models/location_models.dart';

/// Source of device location, reverse geocoding, and city search.
///
/// Implementations handle platform GPS permissions, fallback coordinates,
/// distance threshold filtering, and geocoding translation behind this interface.
abstract class LocationProvider {
  /// Resolves the current location with a reverse-geocoded city name.
  ///
  /// Automatically and safely falls back to default coordinates (Amsterdam)
  /// if GPS permissions are denied, location services are disabled, or an error occurs.
  Future<ResolvedLocation> getCurrentLocation();

  /// Returns a stream of significant location updates.
  ///
  /// Emits a new [ResolvedLocation] when the device moves beyond [minDistanceMeters].
  /// Handles internal stream errors and jitter filtering.
  Stream<ResolvedLocation> getSignificantLocationUpdates({
    double minDistanceMeters = 100.0,
  });

  /// Searches for matching locations given a query string.
  Future<Result<List<LocationResult>>> searchLocations(String query);
}
