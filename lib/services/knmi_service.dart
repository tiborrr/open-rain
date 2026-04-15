import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';
import '../utils/knmi_api_client.dart';

class KNMIService extends RadarProvider {
  final String? wmsApiKey;

  /// Single shared client for all KNMI WMS requests.
  /// Both tile fetching and GetFeatureInfo go through this client, ensuring
  /// the rate limit and quota are tracked in one place.
  final KnmiApiClient _client = KnmiApiClient();

  KNMIService({String? wmsApiKey})
      : wmsApiKey = _sanitizeKey(wmsApiKey);

  static const String _placeholderKey = 'your_knmi_wms_api_key_here';

  static String? _sanitizeKey(String? key) {
    if (key == _placeholderKey) {
      debugPrint(
        'KNMIService: KNMI_WMS_API_KEY is still set to the example placeholder. '
        'Falling back to anonymous access.',
      );
      return null;
    }
    return key;
  }

  static const String _authenticatedHost =
      'https://api.dataplatform.knmi.nl/wms/adaguc-server';
  static const String _anonymousHost =
      'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server';

  /// Selects the correct base host depending on whether an API key is available.
  String get _baseHost => wmsApiKey != null ? _authenticatedHost : _anonymousHost;

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

  @override
  Future<List<RadarFrame>> fetchRadarFrames() async {
    try {
      final times = await _discoverAvailableTimes();
      if (times.isNotEmpty) {
        return times
            .map((t) => RadarFrame(
                  frameId: _formatTime(t),
                  time: t,
                ))
            .toList();
      }
    } catch (e) {
      debugPrint('KNMI WMS: Failed to discover dynamic frames, using fallback. Error: $e');
    }

    // Fallback: Generate 36 frames (3 hours) starting from 1 hour ago
    final now = DateTime.now().toUtc();
    final alignedNow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 5) * 5,
    );

    final List<RadarFrame> frames = [];
    final startTime = alignedNow.subtract(const Duration(hours: 1));

    for (int i = 0; i < 36; i++) {
      final time = startTime.add(Duration(minutes: i * 5));
      frames.add(RadarFrame(
        frameId: _formatTime(time),
        time: time,
      ));
    }

    return frames;
  }

  Future<List<DateTime>> _discoverAvailableTimes() async {
    final cacheKey = 'knmi_wms_capabilities_times';
    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(5, 1),
      fetchFunction: () async {
        final queryUri = Uri.parse(
          '$_baseHost?SERVICE=WMS&REQUEST=GetCapabilities&DATASET=radar_forecast_2.0',
        );

        final headers = wmsApiKey != null ? {'Authorization': wmsApiKey!} : null;
        final response = await _client.get(queryUri, headers: headers);

        return switch (response) {
          KnmiSuccess s => () {
              final resp = s.response as dynamic;
              final body = resp.body as String;
              final document = XmlDocument.parse(body);
              
              // Find the time dimension for the precipitation_nowcast layer
              final layers = document.findAllElements('Layer');
              final nowcastLayer = layers.firstWhere(
                (l) => l.findElements('Name').any((n) => n.innerText == 'precipitation_nowcast'),
                orElse: () => throw Exception('Layer precipitation_nowcast not found in GetCapabilities'),
              );

              final timeDim = nowcastLayer.findElements('Dimension').firstWhere(
                (d) => d.getAttribute('name') == 'time',
                orElse: () => throw Exception('Time dimension not found for nowcast layer'),
              );

              final timeText = timeDim.innerText.trim();
              final defaultTimeStr = timeDim.getAttribute('default');
              
              debugPrint('KNMI WMS: Discovered time dimension: $timeText (default: $defaultTimeStr)');
              
              // Format: START/END/PERIOD (e.g. 2024-04-02T13:00:00Z/2024-04-02T17:00:00Z/PT5M)
              final parts = timeText.split('/');
              if (parts.length != 3) {
                throw Exception('Unexpected time dimension format: $timeText');
              }

              final fullStart = DateTime.parse(parts[0]);
              final fullEnd = DateTime.parse(parts[1]);
              final periodStr = parts[2]; // e.g. PT5M
              
              int intervalMinutes = 5;
              if (periodStr.contains('PT')) {
                 final m = RegExp(r'(\d+)M').firstMatch(periodStr);
                 if (m != null) {
                    intervalMinutes = int.parse(m.group(1)!);
                 }
              }

              final now = DateTime.now().toUtc();
              final alignedNow = DateTime.utc(
                now.year,
                now.month,
                now.day,
                now.hour,
                (now.minute ~/ 5) * 5,
              );

              // Apply User Window: 1h history, 2h forecast centered around current time
              DateTime windowStart = alignedNow.subtract(const Duration(hours: 1));
              DateTime windowEnd = alignedNow.add(const Duration(hours: 2));


              // Clamp to absolute bounds of API
              if (windowStart.isBefore(fullStart)) windowStart = fullStart;
              if (windowEnd.isAfter(fullEnd)) windowEnd = fullEnd;

              final List<String> times = [];
              DateTime current = windowStart;
              while (current.isBefore(windowEnd) || current.isAtSameMomentAs(windowEnd)) {
                times.add(current.toIso8601String());
                current = current.add(Duration(minutes: intervalMinutes));
              }

              return times;
            }(),
          _ => throw Exception('Failed to fetch GetCapabilities'),
        };
      },
    );

    if (result != null && result is List) {
      return result.map((t) => DateTime.parse(t.toString())).toList();
    }
    return [];
  }

  String _formatTime(DateTime time) {
    return '${time.toIso8601String().split('.').first}Z';
  }

  @override
  Future<MinutelyForecast?> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async {
    if (frames.isEmpty) return null;

    final cacheKey =
        'knmi_precip_${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}'
        '_${frames.first.frameId}_${frames.last.frameId}';

    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(5, 1),
      fetchFunction: () async {
        final Map<String, String> headers = wmsApiKey != null
            ? {'Authorization': wmsApiKey!, 'Accept': 'application/json'}
            : {'Accept': 'application/json'};

        final Map<String, dynamic> mergedData = {};

        // Chunk frames into groups of 12 (1 hour) to avoid KNMI maxquerylimit
        for (int i = 0; i < frames.length; i += 12) {
          final chunk = frames.skip(i).take(12).toList();
          final start = chunk.first.time;
          final end = chunk.last.time;

          final queryUri = Uri.parse(
            '$_baseHost'
            '?service=WMS&request=GetFeatureInfo'
            '&layers=precipitation_nowcast&query_layers=precipitation_nowcast'
            '&format=image%2Fpng&info_format=application%2Fjson'
            '&crs=EPSG%3A4326&width=1&height=1&x=0&y=0'
            '&bbox=${lon - 0.01},${lat - 0.01},${lon + 0.01},${lat + 0.01}'
            '&DATASET=radar_forecast_2.0'
            '&TIME=${start.toIso8601String().substring(0, 19)}Z'
            '/${end.toIso8601String().substring(0, 19)}Z',
          );

          debugPrint('KNMI WMS GFI Request (chunk): $queryUri');
          final result = await _client.get(queryUri, headers: headers);

          switch (result) {
            case KnmiSuccess s:
              final decoded = _decodeGfiBody(s.response);
              if (decoded != null && decoded is List && decoded.isNotEmpty) {
                mergedData.addAll(decoded[0]['data'] as Map<String, dynamic>);
              }
              break;
            case KnmiQuotaExceeded _:
              return null; // Circuit breaker triggers abort
            case KnmiError e:
              debugPrint('KNMI WMS GFI Error: ${e.statusCode} ${e.body}');
              return null; // Return null on any chunk error to prevent partial charts
          }
        }

        if (mergedData.isEmpty) return null;
        return [{'data': mergedData}];
      },
    );

    if (result != null) {
      return _parseWmsGfiJson(result);
    }
    return null;
  }

  dynamic _decodeGfiBody(Object response) {
    // response is http.Response, imported via KnmiSuccess
    final resp = response as dynamic;
    final contentType = resp.headers['content-type'] as String? ?? '';
    if (contentType.toLowerCase().contains('json')) {
      return json.decode(resp.body as String);
    }
    if ((resp.body as String).startsWith('<?xml') ||
        (resp.body as String).contains('<ServiceException>')) {
      debugPrint('KNMI WMS GFI returned XML: ${resp.body}');
    }
    return null;
  }

  MinutelyForecast? _parseWmsGfiJson(dynamic data) {
    try {
      final Map<String, dynamic> dataMap = data[0]['data'];
      final List<String> sortedTimes = dataMap.keys.toList()..sort();
      return MinutelyForecast(
        times: sortedTimes.map((t) => DateTime.parse(t)).toList(),
        precipitation:
            sortedTimes.map((t) => double.tryParse(dataMap[t].toString()) ?? 0.0).toList(),
      );
    } catch (e) {
      debugPrint('Error parsing KNMI WMS GFI: $e');
      return null;
    }
  }

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) {
    final baseUrl = '$_baseHost?DATASET=radar_forecast_2.0';
    final headers = wmsApiKey != null ? {'Authorization': wmsApiKey!} : null;

    return RadarLayerConfig(
      wmsOptions: WMSTileLayerOptions(
        baseUrl: baseUrl,
        layers: ['precipitation_nowcast'],
        format: 'image/png',
        transparent: true,
        otherParameters: {'TIME': frame.frameId},
      ),
      headers: headers,
      apiClient: _client, // Thread the shared client to the tile provider
    );
  }
}
