import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final now = DateTime.now().toUtc();
    final alignedNow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 5) * 5,
    );

    final List<RadarFrame> frames = [];
    final startTime = alignedNow.subtract(const Duration(hours: 2));

    for (int i = 0; i < 48; i++) {
      final time = startTime.add(Duration(minutes: i * 5));
      frames.add(RadarFrame(
        path: _formatTime(time),
        time: time,
      ));
    }

    return frames;
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

    final startTime = frames.first.time;
    final endTime = frames.last.time;

    final cacheKey =
        'knmi_precip_${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}'
        '_${frames.first.path}_${frames.last.path}';

    final result = await _getCachedOrFetch(
      cacheKey: cacheKey,
      expirationTime: _calculateNextAlignedExpiration(5, 1),
      fetchFunction: () async {
        final Map<String, String> headers = wmsApiKey != null
            ? {'Authorization': wmsApiKey!, 'Accept': 'application/json'}
            : {'Accept': 'application/json'};

        final queryUri = Uri.parse(
          '$_baseHost'
          '?service=WMS&request=GetFeatureInfo'
          '&layers=precipitation_nowcast&query_layers=precipitation_nowcast'
          '&format=image%2Fpng&info_format=application%2Fjson'
          '&crs=EPSG%3A4326&width=1&height=1&x=0&y=0'
          '&bbox=${lon - 0.01},${lat - 0.01},${lon + 0.01},${lat + 0.01}'
          '&DATASET=radar_forecast_2.0'
          '&TIME=${startTime.toIso8601String().substring(0, 19)}Z'
          '/${endTime.toIso8601String().substring(0, 19)}Z',
        );

        debugPrint('KNMI WMS GFI Request: $queryUri');
        final result = await _client.get(queryUri, headers: headers);

        return switch (result) {
          KnmiSuccess s => _decodeGfiBody(s.response),
          KnmiQuotaExceeded _ => null, // Circuit breaker already logged once
          KnmiError e => () {
              debugPrint('KNMI WMS GFI Error: ${e.statusCode} ${e.body}');
              return null;
            }(),
        };
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
        otherParameters: {'TIME': frame.path},
      ),
      headers: headers,
      apiClient: _client, // Thread the shared client to the tile provider
    );
  }
}
