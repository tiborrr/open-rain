import 'package:flutter/foundation.dart';

/// Resolved geographic point for weather dashboard and radar mapping.
@immutable
class ResolvedLocation {
  const ResolvedLocation({
    required this.lat,
    required this.lon,
    required this.name,
    this.isFallback = false,
    this.fallbackMessage,
  });

  final double lat;
  final double lon;
  final String name;
  final bool isFallback;
  final String? fallbackMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedLocation &&
          runtimeType == other.runtimeType &&
          lat == other.lat &&
          lon == other.lon &&
          name == other.name &&
          isFallback == other.isFallback &&
          fallbackMessage == other.fallbackMessage;

  @override
  int get hashCode => Object.hash(lat, lon, name, isFallback, fallbackMessage);

  @override
  String toString() =>
      'ResolvedLocation(lat: $lat, lon: $lon, name: $name, isFallback: $isFallback)';
}

/// Search result representing a candidate city or address.
@immutable
class LocationResult {
  const LocationResult({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;

  double get lat => latitude;
  double get lon => longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationResult &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(name, latitude, longitude);

  @override
  String toString() =>
      'LocationResult(name: $name, latitude: $latitude, longitude: $longitude)';
}
