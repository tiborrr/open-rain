import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/location_provider.dart';
import '../utils/result.dart';

export '../models/location_models.dart';
export '../providers/location_provider.dart';

/// Device-backed implementation of [LocationProvider].
///
/// Uses the [geolocator] and [geocoding] plugins to query GPS, reverse-geocode
/// coordinates into human-readable city names, and filter out minor movements.
/// Automatically falls back to default coordinates (Amsterdam) when permissions
/// are denied or disabled.
class LocationService implements LocationProvider {
  LocationService({Geocoding? geocoding}) : _geocodingOverride = geocoding;

  final Geocoding? _geocodingOverride;
  Geocoding get _geocoding => _geocodingOverride ?? Geocoding();

  static const double defaultFallbackLat = 52.3676;
  static const double defaultFallbackLon = 4.9041;
  static const String defaultFallbackName = 'Amsterdam (Default)';
  static const String defaultFallbackWarning =
      'Location disabled. Using Amsterdam as default. '
      'Enable location in System Settings for your local weather.';

  Position? _lastStreamPosition;

  @override
  Future<ResolvedLocation> getCurrentLocation() async {
    try {
      final position = await getCurrentPosition();
      final city = await getCityFromCoordinates(
        position.latitude,
        position.longitude,
      );
      return ResolvedLocation(
        lat: position.latitude,
        lon: position.longitude,
        name: city ?? 'Current Location',
      );
    } catch (_) {
      return const ResolvedLocation(
        lat: defaultFallbackLat,
        lon: defaultFallbackLon,
        name: defaultFallbackName,
        isFallback: true,
        fallbackMessage: defaultFallbackWarning,
      );
    }
  }

  @override
  Stream<ResolvedLocation> getSignificantLocationUpdates({
    double minDistanceMeters = 100.0,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: minDistanceMeters.round(),
      ),
    ).asyncMap((position) async {
      if (_lastStreamPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastStreamPosition!.latitude,
          _lastStreamPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (distance < minDistanceMeters) {
          return null;
        }
      }
      _lastStreamPosition = position;
      final city = await getCityFromCoordinates(
        position.latitude,
        position.longitude,
      );
      return ResolvedLocation(
        lat: position.latitude,
        lon: position.longitude,
        name: city ?? 'Current Location',
      );
    }).where((loc) => loc != null).cast<ResolvedLocation>();
  }

  @override
  Future<Result<List<LocationResult>>> searchLocations(String query) async {
    try {
      final List<Location> locations =
          await _geocoding.locationFromAddress(query);
      final List<LocationResult> results = [];

      for (final loc in locations) {
        final city = await getCityFromCoordinates(loc.latitude, loc.longitude);
        results.add(LocationResult(
          name: city ?? query,
          latitude: loc.latitude,
          longitude: loc.longitude,
        ));
      }
      return Result.ok(results);
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
  }

  /// Fetches the current position of the device.
  ///
  /// Throws an exception if permissions are denied or services are disabled.
  @visibleForTesting
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

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
  @visibleForTesting
  Future<String?> getCityFromCoordinates(double lat, double lon) async {
    try {
      final List<Placemark> placemarks =
          await _geocoding.placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea;
      }
    } catch (_) {
      // Ignore geocoding errors, just return null
    }
    return null;
  }
}
