import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/constants/neighbor_sampling_constants.dart';
import 'package:flutter_weather/models/precipitation_nowcast.dart';
import 'package:flutter_weather/models/radar_frame.dart';
import 'package:flutter_weather/models/radar_layer_config.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/providers/radar_provider.dart';
import 'package:flutter_weather/providers/weather_provider.dart';
import 'package:flutter_weather/services/precipitation_nowcast_service.dart';
import 'package:flutter_weather/utils/result.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class _FakeRadarProvider implements RadarProvider {
  _FakeRadarProvider({
    this.frames = const [],
    this.centerForecast,
    this.neighborForecasts = const {},
    this.onFetchPrecipitation,
  });

  List<RadarFrame> frames;
  MinutelyForecast? centerForecast;
  Map<LatLng, MinutelyForecast> neighborForecasts;
  void Function(double lat, double lon)? onFetchPrecipitation;

  @override
  void invalidateCaches() {}

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames({
    bool forceRefresh = false,
  }) async {
    return Result.ok(frames);
  }

  @override
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async {
    onFetchPrecipitation?.call(lat, lon);
    for (final entry in neighborForecasts.entries) {
      if ((entry.key.latitude - lat).abs() < 0.0001 &&
          (entry.key.longitude - lon).abs() < 0.0001) {
        return Result.ok(entry.value);
      }
    }
    if ((lat - 52.3676).abs() < 0.0001 && (lon - 4.9041).abs() < 0.0001) {
      return Result.ok(centerForecast);
    }
    return const Result.ok(null);
  }

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) =>
      RadarLayerConfig(urlTemplate: '');
}

class _FakeWeatherProvider implements WeatherProvider {
  _FakeWeatherProvider({required this.fallbackForecast});
  final MinutelyForecast fallbackForecast;

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
          humidity: 60,
          precipitation: 0,
          weatherCode: 1,
          windGust: 5,
          lat: lat,
          lon: lon,
        ),
        hourly: HourlyForecast(times: [], temperatures: [], weatherCodes: []),
        minutely: fallbackForecast,
        daily: DailyForecast(
          times: [],
          maxTemps: [],
          minTemps: [],
          weatherCodes: [],
        ),
        utcOffset: Duration.zero,
        timezone: 'UTC',
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
    return Result.ok(fallbackForecast);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime.utc(2024, 4, 1, 12);

  final sampleFrames = [
    RadarFrame(frameId: 'f1', time: baseTime),
    RadarFrame(frameId: 'f2', time: baseTime.add(const Duration(minutes: 5))),
    RadarFrame(frameId: 'f3', time: baseTime.add(const Duration(minutes: 10))),
  ];

  MinutelyForecast makeForecast(List<double> values) {
    return MinutelyForecast(
      times: [
        baseTime,
        baseTime.add(const Duration(minutes: 5)),
        baseTime.add(const Duration(minutes: 10)),
      ],
      precipitation: values,
    );
  }

  final fallbackForecast = makeForecast([0.1, 0.2, 0.3]);
  final knmiForecast = makeForecast([1.0, 2.0, 3.0]);

  group('PrecipitationNowcastService', () {
    test('computeNeighborPoints returns 8 points strictly ordered by distance',
        () {
      const centerLat = 52.3676;
      const centerLon = 4.9041;
      const step = NeighborSamplingConstants.gridStepDegrees;

      final points = PrecipitationNowcastService.computeNeighborPoints(
        centerLat,
        centerLon,
      );

      expect(points.length, equals(8));

      // Assert strictly ascending or equal distance ordering
      for (var i = 0; i < points.length - 1; i++) {
        final d1 = Geolocator.distanceBetween(
          centerLat,
          centerLon,
          points[i].latitude,
          points[i].longitude,
        );
        final d2 = Geolocator.distanceBetween(
          centerLat,
          centerLon,
          points[i + 1].latitude,
          points[i + 1].longitude,
        );
        expect(
          d1 <= d2,
          isTrue,
          reason: 'Point $i ($d1 m) must be <= point ${i + 1} ($d2 m)',
        );
      }

      // The 4 cardinal neighbors (N, S, E, W) must come before diagonal points
      final cardinalPoints = [
        const LatLng(centerLat + step, centerLon),
        const LatLng(centerLat - step, centerLon),
        const LatLng(centerLat, centerLon + step),
        const LatLng(centerLat, centerLon - step),
      ];

      for (var i = 0; i < 4; i++) {
        final match = cardinalPoints.any(
          (c) =>
              (c.latitude - points[i].latitude).abs() < 1e-6 &&
              (c.longitude - points[i].longitude).abs() < 1e-6,
        );
        expect(match, isTrue);
      }
    });

    test(
        'getNowcast emits initial nowcast with center forecast and aligned frames',
        () async {
      final fakeProvider = _FakeRadarProvider(
        frames: sampleFrames,
        centerForecast: knmiForecast,
      );
      final weatherProvider = _FakeWeatherProvider(
        fallbackForecast: fallbackForecast,
      );

      final service = PrecipitationNowcastService(
        radarProvider: fakeProvider,
        weatherProvider: weatherProvider,
      );

      final events = <PrecipitationNowcast>[];
      await for (final event in service.getNowcast(
        lat: 52.3676,
        lon: 4.9041,
      )) {
        events.add(event);
      }

      expect(events.isNotEmpty, isTrue);
      final initial = events.first;
      expect(initial.centerForecast, equals(knmiForecast));
      expect(initial.frames.length, equals(sampleFrames.length));
    });

    test(
        'getNowcast falls back to fallback series when center series is null or unusable',
        () async {
      final fakeProvider = _FakeRadarProvider(
        frames: sampleFrames, // GFI failure (centerForecast defaults to null)
      );
      final weatherProvider = _FakeWeatherProvider(
        fallbackForecast: fallbackForecast,
      );

      final service = PrecipitationNowcastService(
        radarProvider: fakeProvider,
        weatherProvider: weatherProvider,
      );

      final initial = await service
          .getNowcast(
            lat: 52.3676,
            lon: 4.9041,
          )
          .first;

      expect(initial.centerForecast, equals(fallbackForecast));
    });

    test('getNowcast emits progressive neighbor updates', () async {
      const centerLat = 52.3676;
      const centerLon = 4.9041;
      final neighborPoints = PrecipitationNowcastService.computeNeighborPoints(
        centerLat,
        centerLon,
      );

      final neighborMap = <LatLng, MinutelyForecast>{
        neighborPoints[0]: makeForecast([0.5, 0.5, 0.5]),
        neighborPoints[1]: makeForecast([0.8, 0.8, 0.8]),
      };

      final fakeProvider = _FakeRadarProvider(
        frames: sampleFrames,
        centerForecast: knmiForecast,
        neighborForecasts: neighborMap,
      );
      final weatherProvider = _FakeWeatherProvider(
        fallbackForecast: fallbackForecast,
      );

      final service = PrecipitationNowcastService(
        radarProvider: fakeProvider,
        weatherProvider: weatherProvider,
      );

      final events = await service
          .getNowcast(
            lat: centerLat,
            lon: centerLon,
          )
          .toList();

      // Initial event + 2 neighbor updates
      expect(events.length, equals(3));
      expect(events[0].neighbors.isEmpty, isTrue);
      expect(events[1].neighbors.length, equals(1));
      expect(events[2].neighbors.length, equals(2));
    });

    test('canceling stream subscription aborts subsequent neighbor fetches',
        () async {
      const centerLat = 52.3676;
      const centerLon = 4.9041;
      int fetchCount = 0;

      final fakeProvider = _FakeRadarProvider(
        frames: sampleFrames,
        centerForecast: knmiForecast,
        onFetchPrecipitation: (lat, lon) {
          fetchCount++;
        },
      );
      final weatherProvider = _FakeWeatherProvider(
        fallbackForecast: fallbackForecast,
      );

      final service = PrecipitationNowcastService(
        radarProvider: fakeProvider,
        weatherProvider: weatherProvider,
      );

      final stream = service.getNowcast(
        lat: centerLat,
        lon: centerLon,
      );

      late StreamSubscription<PrecipitationNowcast> sub;
      final completer = Completer<void>();

      sub = stream.listen((event) async {
        // Cancel immediately on initial emission
        await sub.cancel();
        completer.complete();
      });

      await completer.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Center query was made (1), but neighbor loop was aborted immediately
      expect(fetchCount, lessThan(3));
    });
  });
}
