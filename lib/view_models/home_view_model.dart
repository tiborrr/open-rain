import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants/neighbor_sampling_constants.dart';
import '../models/radar_frame.dart';
import '../models/weather_models.dart';
import '../repositories/radar_repository.dart';
import '../repositories/weather_repository.dart';
import '../services/location_service.dart';
import '../utils/command.dart';
import '../utils/result.dart';

/// User intent for the dashboard load command.
///
/// `null` ⇒ use GPS. Non-null ⇒ pinned location with display [name].
class LocationSelection {
  const LocationSelection({
    required this.lat,
    required this.lon,
    required this.name,
  });

  final double lat;
  final double lon;
  final String name;
}

/// View-model for the dashboard screen.
///
/// State (data, name, error message) is plain fields. Async work is
/// expressed as [Command]s so the view can listen to running/error state
/// without the view-model managing a `HomeStatus` enum + ad-hoc booleans.
///
/// Commands:
///   * [loadDashboard]  — `Command1<void, LocationSelection?>`
///                        (`null` ⇒ resolve via GPS)
///   * [searchCities]   — `Command1<List<LocationResult>, String>`
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required WeatherRepository weatherRepository,
    required RadarRepository radarRepository,
    required LocationService locationService,
    Future<void> Function(double lat, double lon)? onLocationResolved,
  })  : _weatherRepository = weatherRepository,
        _radarRepository = radarRepository,
        _locationService = locationService,
        _onLocationResolved = onLocationResolved {
    loadDashboard = Command1<void, LocationSelection?>(_loadDashboard);
    searchCities =
        Command1<List<LocationResult>, String>(_searchCities);
    _initLocationListener();
  }

  // Fallback used when GPS is denied/disabled.
  static const double _fallbackLat = 52.3676;
  static const double _fallbackLon = 4.9041;
  static const String _fallbackLocationName = 'Amsterdam (Default)';
  static const String _fallbackWarning =
      'Location disabled. Using Amsterdam as default. '
      'Enable location in System Settings for your local weather.';

  static const double _moveThresholdMeters = 100.0;

  final WeatherRepository _weatherRepository;
  final RadarRepository _radarRepository;
  final LocationService _locationService;

  /// Optional callback fired whenever the dashboard has resolved a
  /// concrete (lat, lon). The rain notification service subscribes to this
  /// so the background task always has a recent coordinate to query.
  final Future<void> Function(double lat, double lon)? _onLocationResolved;

  StreamSubscription<Position>? _locationSubscription;
  bool _useGps = true;
  Position? _lastUpdatePosition;

  /// Set by [refresh] so the *next* dashboard load bypasses the radar cache.
  /// Consumed (and cleared) inside [_loadDashboard] to avoid sticky forced
  /// refreshes on subsequent background polls.
  bool _forceRadarRefresh = false;

  WeatherData? _weatherData;
  List<RadarFrame> _radarFrames = const [];
  String _currentLocationName = 'Unknown Location';
  String? _locationFallbackMessage;
  final Map<LatLng, MinutelyForecast> _neighborForecasts = {};

  /// Run the dashboard load. Argument `null` ⇒ resolve via GPS.
  late final Command1<void, LocationSelection?> loadDashboard;

  /// City search. Argument is the user's query string.
  late final Command1<List<LocationResult>, String> searchCities;

  // ---------------------------------------------------------------------------
  // View-model state (read by the UI)
  // ---------------------------------------------------------------------------

  bool get useGps => _useGps;
  WeatherData? get weatherData => _weatherData;
  List<RadarFrame> get radarFrames => _radarFrames;
  String get currentLocationName => _currentLocationName;

  /// Soft warning shown when GPS fell back to Amsterdam (the load itself
  /// still succeeded, so this is *not* the command error).
  String? get locationFallbackMessage => _locationFallbackMessage;

  /// True only on the first load before any data is available.
  bool get isInitialLoading =>
      loadDashboard.running && _weatherData == null;

  // ---------------------------------------------------------------------------
  // User intent helpers
  // ---------------------------------------------------------------------------

  Future<void> setManualLocation(double lat, double lon, String name) {
    _useGps = false;
    return loadDashboard.execute(
      LocationSelection(lat: lat, lon: lon, name: name),
    );
  }

  Future<void> resetToGps() {
    _useGps = true;
    return loadDashboard.execute(null);
  }

  /// User-initiated refresh. Forces the radar provider to bypass its on-disk
  /// cache so stale frames (e.g. a cached timeline whose newest frame has
  /// already aged out of the KNMI nowcast window) get replaced instead of
  /// re-served. Location and selection semantics are preserved: if the user
  /// pinned a manual location, we refresh *that* location.
  Future<void> refresh({LocationSelection? selection}) {
    _forceRadarRefresh = true;
    return loadDashboard.execute(selection);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _initLocationListener() {
    _locationSubscription =
        _locationService.getPositionStream().listen((position) {
      if (!_useGps || loadDashboard.running) return;
      if (_lastUpdatePosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastUpdatePosition!.latitude,
          _lastUpdatePosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (distance < _moveThresholdMeters) {
          debugPrint(
            'Skip dashboard refresh: User moved only ${distance.toStringAsFixed(1)}m',
          );
          return;
        }
      }
      _lastUpdatePosition = position;
      loadDashboard.execute(
        LocationSelection(
          lat: position.latitude,
          lon: position.longitude,
          name: _currentLocationName,
        ),
      );
    }, onError: (error) {
      debugPrint('Location stream error: $error');
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    loadDashboard.dispose();
    searchCities.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Command implementations
  // ---------------------------------------------------------------------------

  Future<Result<void>> _loadDashboard(LocationSelection? selection) async {
    _locationFallbackMessage = null;

    final resolved = await _resolveLocation(selection);
    final lat = resolved.lat;
    final lon = resolved.lon;
    _currentLocationName = resolved.name;

    // Let the rain notification service know where we are. We don't await
    // — a slow SharedPreferences write should not delay dashboard rendering.
    unawaited(_onLocationResolved?.call(lat, lon) ?? Future<void>.value());

    final forceRadar = _forceRadarRefresh;
    _forceRadarRefresh = false;
    final framesResult = await _radarRepository.getRadarFrames(
      forceRefresh: forceRadar,
    );
    final allFrames = framesResult.valueOrNull ?? const <RadarFrame>[];
    if (framesResult is Err<List<RadarFrame>>) {
      debugPrint('Failed to get radar frames: ${framesResult.error}');
    }

    // Hand Open-Meteo a horizon hint covering the last KNMI frame; the
    // service rounds this up to the next 15-min `forecast_minutely_15` step.
    final endHint =
        allFrames.isNotEmpty ? allFrames.last.time : null;

    final weatherResult = await _weatherRepository.getWeatherData(
      lat: lat,
      lon: lon,
      endTime: endHint,
    );

    return switch (weatherResult) {
      Ok<WeatherData>(value: final data) => () {
          // Align the radar timeline with whatever Open-Meteo actually
          // returned. KNMI publishes 5-min frames spanning history + forecast
          // (`historyLookback` past + capabilities `END` future); Open-Meteo's
          // `minutely_15` is on the 15-min grid with no history. By clipping
          // KNMI frames to `[minutely.times.first, minutely.times.last]`, the
          // chart x-range and the radar playback range share the exact same
          // start and end instants.
          _radarFrames = _alignFramesToMinutely(allFrames, data.minutely);
          _weatherData = _withNeighbors(data);
          notifyListeners();
          if (_radarFrames.isNotEmpty) {
            unawaited(_fetchNeighbors(lat, lon, _radarFrames));
          }
          return const Result<void>.ok(null);
        }(),
      Err<WeatherData>(error: final e) => Result<void>.err(e),
    };
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

  Future<Result<List<LocationResult>>> _searchCities(String query) async {
    try {
      final results = await _locationService.searchLocations(query);
      return Result.ok(results);
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<({double lat, double lon, String name})> _resolveLocation(
    LocationSelection? selection,
  ) async {
    if (selection != null) {
      return (lat: selection.lat, lon: selection.lon, name: selection.name);
    }

    try {
      final position = await _locationService.getCurrentPosition();
      final city = await _locationService.getCityFromCoordinates(
        position.latitude,
        position.longitude,
      );
      return (
        lat: position.latitude,
        lon: position.longitude,
        name: city ?? 'Current Location',
      );
    } catch (_) {
      _locationFallbackMessage = _fallbackWarning;
      return (
        lat: _fallbackLat,
        lon: _fallbackLon,
        name: _fallbackLocationName,
      );
    }
  }

  WeatherData _withNeighbors(WeatherData data) {
    return WeatherData(
      current: data.current,
      hourly: data.hourly,
      minutely: data.minutely,
      daily: data.daily,
      utcOffset: data.utcOffset,
      timezone: data.timezone,
      alert: data.alert,
      airQuality: data.airQuality,
      neighbors: Map.from(_neighborForecasts),
    );
  }

  Future<void> _fetchNeighbors(
    double lat,
    double lon,
    List<RadarFrame> frames,
  ) async {
    _neighborForecasts.clear();

    final step = NeighborSamplingConstants.gridStepDegrees;
    final offsets = [-step, 0.0, step];
    final points = <LatLng>[
      for (final dLat in offsets)
        for (final dLon in offsets)
          if (dLat != 0 || dLon != 0) LatLng(lat + dLat, lon + dLon),
    ];

    points.sort((a, b) {
      final distA =
          Geolocator.distanceBetween(lat, lon, a.latitude, a.longitude);
      final distB =
          Geolocator.distanceBetween(lat, lon, b.latitude, b.longitude);
      return distA.compareTo(distB);
    });

    for (final point in points) {
      final result = await _radarRepository.getPrecipitationSeries(
        lat: point.latitude,
        lon: point.longitude,
        frames: frames,
      );
      switch (result) {
        case Ok<MinutelyForecast?>(value: final forecast):
          if (forecast == null) continue;
          _neighborForecasts[point] = forecast;
          if (_weatherData != null) {
            _weatherData = _withNeighbors(_weatherData!);
            notifyListeners();
          }
        case Err<MinutelyForecast?>(error: final e):
          debugPrint('Background neighbor fetch failed for $point: $e');
      }
    }
  }
}
