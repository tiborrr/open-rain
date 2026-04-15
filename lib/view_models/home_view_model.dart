import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/weather_models.dart';
import '../models/radar_frame.dart';
import '../repositories/weather_repository.dart';
import '../repositories/radar_repository.dart';
import '../services/location_service.dart';

enum HomeStatus { initial, loading, success, error }

class HomeViewModel extends ChangeNotifier {
  final WeatherRepository _weatherRepository;
  final RadarRepository _radarRepository;
  final LocationService _locationService;
  StreamSubscription<Position>? _locationSubscription;
  bool _isAutoUpdating = false;
  bool _useGps = true;
  bool get useGps => _useGps;

  Position? _lastUpdatePosition;
  static const double _moveThreshold = 100.0; // Meters

  final Map<LatLng, MinutelyForecast> _neighborForecasts = {};

  HomeViewModel({
    required WeatherRepository weatherRepository,
    required RadarRepository radarRepository,
    required LocationService locationService,
  })  : _weatherRepository = weatherRepository,
        _radarRepository = radarRepository,
        _locationService = locationService {
    _initLocationListener();
  }

  void _initLocationListener() {
    _locationSubscription = _locationService.getPositionStream().listen(
      (position) {
        if (_useGps && !_isAutoUpdating) {
          // Only update if moved meaningfully or first update
          if (_lastUpdatePosition != null) {
            final distance = Geolocator.distanceBetween(
              _lastUpdatePosition!.latitude,
              _lastUpdatePosition!.longitude,
              position.latitude,
              position.longitude,
            );
            if (distance < _moveThreshold) {
              debugPrint('Skip dashboard refresh: User moved only ${distance.toStringAsFixed(1)}m');
              return;
            }
          }

          _isAutoUpdating = true;
          _lastUpdatePosition = position;
          loadDashboard(lat: position.latitude, lon: position.longitude).then((_) {
            _isAutoUpdating = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Location stream error: $error');
        // If we fail to get location from stream, we don't need to do anything
        // as loadDashboard() will handle the static fallback if it fails too.
      },
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  HomeStatus _status = HomeStatus.initial;
  HomeStatus get status => _status;

  WeatherData? _weatherData;
  WeatherData? get weatherData => _weatherData;

  bool get isInitialLoading => _status == HomeStatus.loading && _weatherData == null;

  List<RadarFrame> _radarFrames = [];
  List<RadarFrame> get radarFrames => _radarFrames;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _currentLocationName = 'Unknown Location';
  String get currentLocationName => _currentLocationName;

  Future<void> loadDashboard({double? lat, double? lon}) async {
    _status = HomeStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      if (lat == null || lon == null) {
        try {
          final position = await _locationService.getCurrentPosition();
          lat = position.latitude;
          lon = position.longitude;
        } catch (e) {
          // Fallback to Amsterdam if location is disabled/denied
          lat = 52.3676;
          lon = 4.9041;
          _errorMessage = 'Location disabled. Using Amsterdam as default. Enable location in System Settings for your local weather.';
        }
      }
      
      // Start independent tasks in parallel
      final cityFuture = _locationService.getCityFromCoordinates(lat, lon).catchError((e) {
        debugPrint('Failed to get city name: $e');
        return null;
      });
      
      final framesFuture = _radarRepository.getRadarFrames().catchError((e) {
        debugPrint('Failed to get radar frames: $e');
        return <RadarFrame>[]; // Return empty list rather than failing
      });

      // We need frames to get time bounds for weather fetching, but we can await them separately
      final results = await Future.wait([cityFuture, framesFuture]);
      _currentLocationName = results[0] as String? ?? (lat == 52.3676 ? 'Amsterdam (Default)' : 'Current Location');
      _radarFrames = results[1] as List<RadarFrame>;
      notifyListeners();

      DateTime? startTime;
      DateTime? endTime;
      if (_radarFrames.isNotEmpty) {
        startTime = _radarFrames.first.time;
        endTime = _radarFrames.last.time;
      }

      // 2. Fetch Weather Data and Precipitation Series in parallel
      final weatherFuture = _weatherRepository.getWeatherData(
        lat: lat,
        lon: lon,
        startTime: startTime,
        endTime: endTime,
      ); // If weather mapping fails entirely, we still want it to throw so we show the error state

      final precipFuture = _radarFrames.isNotEmpty 
          ? _radarRepository.getPrecipitationSeries(lat: lat, lon: lon, frames: _radarFrames).catchError((e) {
              debugPrint('Failed to get precipitation series: $e');
              return null; // Swallow error to prevent crashing entire dashboard
            })
          : Future<MinutelyForecast?>.value(null);

      final weatherResults = await Future.wait([weatherFuture, precipFuture]);
      final weatherData = weatherResults[0] as WeatherData;
      final radarPrecipitation = weatherResults[1] as MinutelyForecast?;

      if (radarPrecipitation != null) {
        _weatherData = WeatherData(
          current: weatherData.current,
          hourly: weatherData.hourly,
          minutely: radarPrecipitation,
          daily: weatherData.daily,
          utcOffset: weatherData.utcOffset,
          timezone: weatherData.timezone,
          alert: weatherData.alert,
          airQuality: weatherData.airQuality,
          neighbors: Map.from(_neighborForecasts),
        );
      } else {
        _weatherData = weatherData;
      }

      _status = HomeStatus.success;
      notifyListeners();

      // 3. Kick off background neighbor fetching (don't await)
      if (_radarFrames.isNotEmpty) {
        _fetchNeighbors(lat, lon, _radarFrames);
      }
    } catch (e) {
      _status = HomeStatus.error;
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> setManualLocation(double lat, double lon, String name) async {
    _useGps = false;
    _currentLocationName = name;
    await loadDashboard(lat: lat, lon: lon);
  }

  Future<void> resetToGps() async {
    _useGps = true;
    await loadDashboard();
  }

  Future<List<LocationResult>> searchCities(String query) async {
    return await _locationService.searchLocations(query);
  }

  Future<void> _fetchNeighbors(double lat, double lon, List<RadarFrame> frames) async {
    _neighborForecasts.clear();

    // Define a 3x3 grid around the user (~15km steps)
    const offsets = [-0.15, 0.0, 0.15];
    final List<LatLng> points = [];
    for (var dLat in offsets) {
      for (var dLon in offsets) {
        if (dLat == 0 && dLon == 0) continue; // Skip center (already fetched)
        points.add(LatLng(lat + dLat, lon + dLon));
      }
    }

    // Sort by distance (Nearest first)
    points.sort((a, b) {
      final distA = Geolocator.distanceBetween(lat, lon, a.latitude, a.longitude);
      final distB = Geolocator.distanceBetween(lat, lon, b.latitude, b.longitude);
      return distA.compareTo(distB);
    });

    for (var point in points) {
      try {
        final forecast = await _radarRepository.getPrecipitationSeries(
          lat: point.latitude,
          lon: point.longitude,
          frames: frames,
        );

        if (forecast != null) {
          _neighborForecasts[point] = forecast;
          // Optimistically update weather data with the new neighbor
          if (_weatherData != null) {
            _weatherData = WeatherData(
              current: _weatherData!.current,
              hourly: _weatherData!.hourly,
              minutely: _weatherData!.minutely,
              daily: _weatherData!.daily,
              utcOffset: _weatherData!.utcOffset,
              timezone: _weatherData!.timezone,
              alert: _weatherData!.alert,
              airQuality: _weatherData!.airQuality,
              neighbors: Map.from(_neighborForecasts),
            );
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('Background neighbor fetch failed for $point: $e');
      }
    }
  }
}
