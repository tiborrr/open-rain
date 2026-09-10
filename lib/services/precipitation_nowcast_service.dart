import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants/neighbor_sampling_constants.dart';
import '../models/precipitation_nowcast.dart';
import '../models/radar_frame.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';
import '../providers/weather_provider.dart';
import '../utils/result.dart';

/// Service coordinating short-term precipitation nowcasts.
///
/// Coordinates [RadarProvider] and [WeatherProvider] to fuse radar imagery
/// frames with high-resolution point precipitation series, weather conditions,
/// and progressive spatial neighbor samples.
class PrecipitationNowcastService {
  PrecipitationNowcastService({
    required RadarProvider radarProvider,
    required WeatherProvider weatherProvider,
  })  : _radarProvider = radarProvider,
        _weatherProvider = weatherProvider;

  final RadarProvider _radarProvider;
  final WeatherProvider _weatherProvider;

  /// Fetch radar frames directly from the underlying provider.
  Future<List<RadarFrame>> getRadarFrames({bool forceRefresh = false}) async {
    final result = await _radarProvider.fetchRadarFrames(
      forceRefresh: forceRefresh,
    );
    return switch (result) {
      Ok<List<RadarFrame>>(value: final frames) => frames,
      Err<List<RadarFrame>>(error: final e) => () {
        debugPrint(
          'PrecipitationNowcastService: Failed to get radar frames: $e',
        );
        return const <RadarFrame>[];
      }(),
    };
  }

  /// Invalidates provider-specific tile and image caches.
  void invalidateCaches() => _radarProvider.invalidateCaches();

  /// Produces a stream of [PrecipitationNowcast] emissions for ([lat], [lon]).
  ///
  /// Concurrently/sequentially resolves radar frames and weather conditions,
  /// fusing radar precipitation with the fallback minutely timeline.
  ///
  /// The initial emission delivers the center forecast, enriched weather conditions,
  /// and timeline-aligned radar frames immediately for instantaneous rendering.
  /// Subsequent emissions deliver progressive spatial neighbor updates sorted by
  /// distance from the queried coordinate.
  ///
  /// Canceling the returned stream subscription immediately stops pending
  /// neighbor queries to conserve rate limits.
  Stream<PrecipitationNowcast> getNowcast({
    required double lat,
    required double lon,
    bool forceRefresh = false,
    List<RadarFrame>? preloadedFrames,
    MinutelyForecast? fallback,
  }) {
    late final StreamController<PrecipitationNowcast> controller;
    var isCanceled = false;

    controller = StreamController<PrecipitationNowcast>(
      onCancel: () {
        isCanceled = true;
      },
    );

    void run() async {
      try {
        final framesFuture = preloadedFrames != null
            ? Future.value(preloadedFrames)
            : getRadarFrames(forceRefresh: forceRefresh);
        final weatherFuture = _weatherProvider.fetchWeather(
          lat: lat,
          lon: lon,
        );

        final results = await Future.wait([framesFuture, weatherFuture]);
        if (isCanceled) return;

        final allFrames = results[0] as List<RadarFrame>;
        final weatherResult = results[1] as Result<WeatherData>;

        if (weatherResult is! Ok<WeatherData>) {
          final error = (weatherResult as Err<WeatherData>).error;
          if (!isCanceled && !controller.isClosed) {
            controller.addError(error);
            await controller.close();
          }
          return;
        }

        final initialWeather = weatherResult.value;
        final effectiveFallback = fallback ?? initialWeather.minutely;

        final centerSeries = await _resolveCenterSeries(
          lat: lat,
          lon: lon,
          frames: allFrames,
          fallback: effectiveFallback,
        );
        if (isCanceled) return;

        final alignedFrames = _alignFramesToMinutely(allFrames, centerSeries);

        var currentWeather = initialWeather.copyWith(
          minutely: centerSeries,
        );

        var nowcast = PrecipitationNowcast(
          weather: currentWeather,
          frames: alignedFrames,
        );

        controller.add(nowcast);

        if (alignedFrames.isEmpty || isCanceled) {
          if (!isCanceled) await controller.close();
          return;
        }

        final neighborPoints = computeNeighborPoints(lat, lon);
        final currentNeighbors = <LatLng, MinutelyForecast>{};

        for (final point in neighborPoints) {
          if (isCanceled) return;

          final result = await _radarProvider.fetchPrecipitationSeries(
            lat: point.latitude,
            lon: point.longitude,
            frames: alignedFrames,
          );
          if (isCanceled) return;

          if (result is Ok<MinutelyForecast?> && result.value != null) {
            currentNeighbors[point] = result.value!;
            currentWeather = currentWeather.copyWith(
              neighbors: Map.unmodifiable(currentNeighbors),
            );
            nowcast = nowcast.copyWith(weather: currentWeather);
            controller.add(nowcast);
          }
        }

        if (!isCanceled) {
          await controller.close();
        }
      } catch (e, st) {
        debugPrint(
          'PrecipitationNowcastService: Error running nowcast pipeline: $e\n$st',
        );
        if (!isCanceled && !controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }

    run();
    return controller.stream;
  }

  /// Calculates the 8 spatial grid neighbor coordinates around ([lat], [lon])
  /// sorted in ascending order by distance from the center.
  @visibleForTesting
  static List<LatLng> computeNeighborPoints(double lat, double lon) {
    const step = NeighborSamplingConstants.gridStepDegrees;
    final offsets = [-step, 0.0, step];
    final points = <LatLng>[
      for (final dLat in offsets)
        for (final dLon in offsets)
          if (dLat != 0 || dLon != 0) LatLng(lat + dLat, lon + dLon),
    ];

    points.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        lat,
        lon,
        a.latitude,
        a.longitude,
      );
      final distB = Geolocator.distanceBetween(
        lat,
        lon,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });

    return points;
  }

  Future<MinutelyForecast> _resolveCenterSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
    required MinutelyForecast fallback,
  }) async {
    if (frames.isEmpty) return fallback;
    final result = await _radarProvider.fetchPrecipitationSeries(
      lat: lat,
      lon: lon,
      frames: frames,
    );
    return switch (result) {
      Ok<MinutelyForecast?>(value: final forecast)
          when _isUsableForecast(forecast) =>
        forecast!,
      Ok<MinutelyForecast?>(value: _) => fallback,
      Err<MinutelyForecast?>(error: final e) => () {
        debugPrint(
          'PrecipitationNowcastService: Failed to get center KNMI precipitation: $e',
        );
        return fallback;
      }(),
    };
  }

  static bool _isUsableForecast(MinutelyForecast? forecast) {
    if (forecast == null) return false;
    if (forecast.times.isEmpty || forecast.precipitation.isEmpty) return false;
    return forecast.times.length == forecast.precipitation.length;
  }

  static List<RadarFrame> _alignFramesToMinutely(
    List<RadarFrame> frames,
    MinutelyForecast minutely,
  ) {
    if (frames.isEmpty || minutely.times.isEmpty) return frames;
    final start = minutely.times.first;
    final end = minutely.times.last;
    return [
      for (final f in frames)
        if (!f.time.isBefore(start) && !f.time.isAfter(end)) f,
    ];
  }
}
