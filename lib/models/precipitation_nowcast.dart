import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'radar_frame.dart';
import 'weather_models.dart';

/// Represents a short-term precipitation projection for a location,
/// synchronizing radar imagery frames with enriched weather conditions
/// and spatial neighbor samples.
@immutable
class PrecipitationNowcast {
  const PrecipitationNowcast({
    required this.weather,
    required this.frames,
  });

  /// Full weather data for the location (current, hourly, daily, minutely nowcast, and neighbors).
  final WeatherData weather;

  /// Radar frames clipped to the visible forecast time window.
  final List<RadarFrame> frames;

  /// Convenience getter for the primary precipitation series.
  MinutelyForecast get centerForecast => weather.minutely;

  /// Convenience getter for the spatial neighbor samples.
  Map<LatLng, MinutelyForecast> get neighbors => weather.neighbors;

  PrecipitationNowcast copyWith({
    WeatherData? weather,
    List<RadarFrame>? frames,
  }) {
    return PrecipitationNowcast(
      weather: weather ?? this.weather,
      frames: frames ?? this.frames,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrecipitationNowcast &&
          runtimeType == other.runtimeType &&
          weather == other.weather &&
          listEquals(frames, other.frames);

  @override
  int get hashCode => weather.hashCode ^ Object.hashAll(frames);
}
