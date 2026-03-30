import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../providers/weather_provider.dart';

class OpenMeteoService implements WeatherProvider {
  DateTime _calculateNextAlignedExpiration(int intervalMinutes, int delayMinutes) {
    final now = DateTime.now();
    final totalMinutes = now.millisecondsSinceEpoch ~/ 60000;
    
    final shiftedMinutes = totalMinutes - delayMinutes;
    final currentAligned = (shiftedMinutes ~/ intervalMinutes) * intervalMinutes;
    final nextAligned = currentAligned + intervalMinutes;
    final expirationMinutes = nextAligned + delayMinutes;
    
    return DateTime.fromMillisecondsSinceEpoch(expirationMinutes * 60000);
  }

  Future<dynamic> _getCachedOrFetch({
    required String cacheKey,
    required Future<dynamic> Function() fetchFunction,
    required DateTime expirationTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final cachedDataString = prefs.getString('${cacheKey}_data');
    final expirationString = prefs.getString('${cacheKey}_expiration');

    if (cachedDataString != null && expirationString != null) {
      final expiration = DateTime.parse(expirationString);
      if (DateTime.now().isBefore(expiration)) {
        return json.decode(cachedDataString);
      }
    }

    try {
      final data = await fetchFunction();
      if (data != null) {
        await prefs.setString('${cacheKey}_data', json.encode(data));
        await prefs.setString('${cacheKey}_expiration', expirationTime.toIso8601String());
      }
      return data;
    } catch (e) {
      if (cachedDataString != null) {
        return json.decode(cachedDataString);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchMinutelyWeather(double lat, double lon, {DateTime? start, DateTime? end}) async {
    final cacheKey = 'weather_minutely_${lat}_$lon${start?.millisecondsSinceEpoch}${end?.millisecondsSinceEpoch}';
    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(15, 2),
      fetchFunction: () async {
        final params = {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current': 'temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_gusts_10m',
          'minutely_15': 'precipitation',
          'timezone': 'UTC',
        };

        if (start != null && end != null) {
          final df = DateFormat('yyyy-MM-ddTHH:mm');
          params['start_minutely_15'] = df.format(start);
          params['end_minutely_15'] = df.format(end);
        }

        final url = Uri.https('api.open-meteo.com', '/v1/forecast', params);
        final response = await http.get(url);
        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          throw Exception('Failed to load minutely weather data');
        }
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> _fetchHourlyWeather(double lat, double lon, {DateTime? start, DateTime? end}) async {
    final cacheKey = 'weather_hourly_${lat}_$lon${start?.millisecondsSinceEpoch}${end?.millisecondsSinceEpoch}';
    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(60, 2),
      fetchFunction: () async {
        final params = {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'hourly': 'temperature_2m,precipitation_probability,weather_code,wind_gusts_10m',
          'timezone': 'UTC',
          'forecast_days': '14',
        };

        if (start != null && end != null) {
          final df = DateFormat('yyyy-MM-ddTHH:mm');
          params['start_hour'] = df.format(start);
          params['end_hour'] = df.format(end);
        }

        final url = Uri.https('api.open-meteo.com', '/v1/forecast', params);
        final response = await http.get(url);
        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          throw Exception('Failed to load hourly weather data');
        }
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> _fetchDailyWeather(double lat, double lon) async {
    final cacheKey = 'weather_daily_${lat}_$lon';
    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(360, 5),
      fetchFunction: () async {
        final url = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
          'timezone': 'UTC',
          'forecast_days': '14',
        });
        final response = await http.get(url);
        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          throw Exception('Failed to load daily weather data');
        }
      },
    );
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> _fetchAirQuality(double lat, double lon) async {
    final cacheKey = 'weather_air_quality_${lat}_$lon';
    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(60, 5),
      fetchFunction: () async {
        final url = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current': 'european_aqi,pm2_5,ozone',
          'timezone': 'UTC',
        });
        final response = await http.get(url);
        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          return null; // Don't fail the whole app for AQI
        }
      },
    );
    return result != null ? Map<String, dynamic>.from(result) : {};
  }

  @override
  Future<Map<String, dynamic>> fetchWeather({required double lat, required double lon, DateTime? startTime, DateTime? endTime}) async {
    final results = await Future.wait([
      _fetchMinutelyWeather(lat, lon, start: startTime, end: endTime),
      _fetchHourlyWeather(lat, lon), // Get standard hourly range
      _fetchDailyWeather(lat, lon),
      _fetchAirQuality(lat, lon),
    ]);

    final minutelyResult = results[0];
    final hourlyResult = results[1];
    final dailyResult = results[2];
    final airQualityResult = results[3];

    final combinedData = {
      ...minutelyResult,
      'hourly': hourlyResult['hourly'],
      'daily': dailyResult['daily'],
      'utc_offset_seconds': minutelyResult['utc_offset_seconds'],
      'timezone': minutelyResult['timezone'],
      'air_quality': airQualityResult['current'],
    };

    final alert = _analyzeAlerts(combinedData);
    if (alert != null) {
      combinedData['alert'] = alert;
    }

    return combinedData;
  }

  Map<String, String>? _analyzeAlerts(Map<String, dynamic> data) {
    if (data['current'] == null) return null;

    final current = data['current'];
    final weatherCode = current['weather_code'];
    final windGust = current['wind_gusts_10m'] ?? 0;
    
    if (weatherCode == 95 || weatherCode == 96 || weatherCode == 99) {
      return {
        'title': 'Thunderstorm Warning',
        'message': 'Thunderstorms with possible hail detected in your area.',
        'type': 'thunder',
      };
    }

    if (windGust > 70) {
      return {
        'title': 'High Wind Warning',
        'message': 'Dangerous wind gusts of ${windGust.round()} km/h detected.',
        'type': 'wind',
      };
    }

    final minutely = data['minutely_15'];
    if (minutely != null && minutely['precipitation'] != null) {
      final precipList = List<num>.from(minutely['precipitation']);
      for (int i = 0; i < 4 && i < precipList.length; i++) {
        if (precipList[i] > 2.5) {
          return {
            'title': 'Heavy Rain Alert',
            'message': 'Very heavy rainfall expected within the hour.',
            'type': 'rain',
          };
        }
      }
    }

    if (weatherCode == 75) {
      return {
        'title': 'Heavy Snow Alert',
        'message': 'Significant snow accumulation expected.',
        'type': 'snow',
      };
    }

    return null;
  }
}
