import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/precipitation_nowcast.dart';
import '../models/radar_frame.dart';
import '../models/weather_models.dart';
import '../providers/location_provider.dart';
import '../services/precipitation_nowcast_service.dart';
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
    required PrecipitationNowcastService nowcastService,
    required LocationProvider locationProvider,
    Future<void> Function(double lat, double lon)? onLocationResolved,
  })  : _nowcastService = nowcastService,
        _locationProvider = locationProvider,
        _onLocationResolved = onLocationResolved {
    loadDashboard = Command1<void, LocationSelection?>(_loadDashboard);
    searchCities = Command1<List<LocationResult>, String>(_searchCities);
    _initLocationListener();
  }

  final PrecipitationNowcastService _nowcastService;
  final LocationProvider _locationProvider;

  /// Optional callback fired whenever the dashboard has resolved a
  /// concrete (lat, lon). The rain notification service subscribes to this
  /// so the background task always has a recent coordinate to query.
  final Future<void> Function(double lat, double lon)? _onLocationResolved;

  StreamSubscription<ResolvedLocation>? _locationSubscription;
  StreamSubscription<PrecipitationNowcast>? _nowcastSubscription;
  bool _useGps = true;

  /// Set by [refresh] so the *next* dashboard load bypasses the radar cache.
  /// Consumed (and cleared) inside [_loadDashboard] to avoid sticky forced
  /// refreshes on subsequent background polls.
  bool _forceRadarRefresh = false;

  WeatherData? _weatherData;
  List<RadarFrame> _radarFrames = const [];
  String _currentLocationName = 'Unknown Location';
  String? _locationFallbackMessage;

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
  bool get isInitialLoading => loadDashboard.running && _weatherData == null;

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
    _nowcastService.invalidateCaches();
    return loadDashboard.execute(selection);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _initLocationListener() {
    _locationSubscription = _locationProvider
        .getSignificantLocationUpdates()
        .listen(
      (location) {
        if (!_useGps || loadDashboard.running) return;
        loadDashboard.execute(
          LocationSelection(
            lat: location.lat,
            lon: location.lon,
            name: location.name,
          ),
        );
      },
      onError: (Object error) {
        debugPrint('Location stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _nowcastSubscription?.cancel();
    loadDashboard.dispose();
    searchCities.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Command implementations
  // ---------------------------------------------------------------------------

  Future<Result<void>> _loadDashboard(LocationSelection? selection) async {
    _locationFallbackMessage = null;
    await _nowcastSubscription?.cancel();
    _nowcastSubscription = null;

    final resolved = await _resolveLocation(selection);
    final lat = resolved.lat;
    final lon = resolved.lon;
    _currentLocationName = resolved.name;
    // Let the rain notification service know where we are. We don't await
    // — a slow SharedPreferences write should not delay dashboard rendering.
    unawaited(_onLocationResolved?.call(lat, lon) ?? Future<void>.value());

    final forceRadar = _forceRadarRefresh;
    _forceRadarRefresh = false;

    final completer = Completer<Result<void>>();

    _nowcastSubscription = _nowcastService
        .getNowcast(
          lat: lat,
          lon: lon,
          forceRefresh: forceRadar,
        )
        .listen(
          (nowcast) {
            _radarFrames = nowcast.frames;
            _weatherData = nowcast.weather;
            notifyListeners();

            if (!completer.isCompleted) {
              completer.complete(const Result<void>.ok(null));
            }
          },
          onError: (Object error) {
            debugPrint('Nowcast stream error: $error');
            if (!completer.isCompleted) {
              completer.complete(Result<void>.err(
                error is Exception ? error : Exception(error.toString()),
              ));
            }
          },
        );

    return completer.future;
  }

  Future<Result<List<LocationResult>>> _searchCities(String query) {
    return _locationProvider.searchLocations(query);
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

    final resolved = await _locationProvider.getCurrentLocation();
    _locationFallbackMessage = resolved.fallbackMessage;
    return (
      lat: resolved.lat,
      lon: resolved.lon,
      name: resolved.name,
    );
  }
}
