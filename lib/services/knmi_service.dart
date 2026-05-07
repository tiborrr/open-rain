import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import '../constants/knmi_radar_constants.dart';
import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';
import '../utils/cache_store.dart';
import '../utils/knmi_api_client.dart';
import '../utils/result.dart';
import 'knmi_capabilities.dart';
import 'knmi_gfi.dart';

/// KNMI WMS radar provider.
///
/// Responsibilities split out so this file stays small:
/// * HTTP/quota: [KnmiApiClient]
/// * JSON+expiry caching: [CacheStore]
/// * `GetCapabilities` XML parsing: [KnmiCapabilities]
/// * `GetFeatureInfo` JSON parsing: [KnmiGfi]
///
/// What lives here: dataset URL composition, fallback frame timeline, and
/// chunked GFI orchestration. Returns [Result] from every async path so
/// callers cannot drop exceptions silently.
class KNMIService implements RadarProvider {
  KNMIService({
    String? wmsApiKey,
    KnmiApiClient? apiClient,
    CacheStore? cacheStore,
  })  : wmsApiKey = _sanitizeKey(wmsApiKey),
        _client = apiClient ?? KnmiApiClient(),
        _cache = cacheStore ?? CacheStore();

  static const String _placeholderKey = 'your_knmi_wms_api_key_here';
  static const String _authenticatedHost =
      'https://api.dataplatform.knmi.nl/wms/adaguc-server';
  static const String _anonymousHost =
      'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server';

  final String? wmsApiKey;
  final KnmiApiClient _client;
  final CacheStore _cache;

  String get _baseHost =>
      wmsApiKey != null ? _authenticatedHost : _anonymousHost;

  Map<String, String>? get _authHeaders =>
      wmsApiKey != null ? {'Authorization': wmsApiKey!} : null;

  static String? _sanitizeKey(String? key) {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed == _placeholderKey) {
      debugPrint(
        'KNMIService: KNMI_WMS_API_KEY is still set to the example placeholder. '
        'Falling back to anonymous access.',
      );
      return null;
    }
    return trimmed;
  }

  // ---------------------------------------------------------------------------
  // Frame discovery
  // ---------------------------------------------------------------------------

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames() async {
    try {
      final times = await _discoverAvailableTimes();
      if (times.isNotEmpty) {
        return Result.ok([
          for (final t in times) RadarFrame(frameId: _formatTime(t), time: t),
        ]);
      }
    } catch (e) {
      debugPrint('KNMI WMS: capabilities discovery failed: $e');
    }

    return Result.ok(_fallbackFrames());
  }

  List<RadarFrame> _fallbackFrames() {
    final stepMinutes = KnmiRadarConstants.fallbackFrameStep.inMinutes;
    final now = DateTime.now().toUtc();
    final alignedNow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ stepMinutes) * stepMinutes,
    );
    final start = alignedNow.subtract(KnmiRadarConstants.historyLookback);
    return [
      for (var i = 0; i < KnmiRadarConstants.fallbackFrameCount; i++)
        () {
          final t = start.add(Duration(minutes: i * stepMinutes));
          return RadarFrame(frameId: _formatTime(t), time: t);
        }(),
    ];
  }

  Future<List<DateTime>> _discoverAvailableTimes() async {
    final raw = await _cache.getOrFetch(
      key: 'knmi_wms_capabilities_times',
      expiresAt: CacheExpiration.alignedNext(
        KnmiRadarConstants.cacheExpirationIntervalMinutes,
        KnmiRadarConstants.cacheExpirationDelayMinutes,
      ),
      fetch: () async {
        final uri = Uri.parse(
          '$_baseHost?SERVICE=WMS&REQUEST=GetCapabilities&DATASET=radar_forecast_2.0',
        );
        final response = await _client.get(uri, headers: _authHeaders);
        return switch (response) {
          KnmiSuccess s => [
              for (final t in KnmiCapabilities.computeFrameTimes(
                s.response.body,
                nowUtc: DateTime.now().toUtc(),
              ))
                t.toIso8601String(),
            ],
          _ => throw Exception('GetCapabilities failed: $response'),
        };
      },
    );
    if (raw is! List) return const [];
    return [for (final t in raw) DateTime.parse(t.toString())];
  }

  String _formatTime(DateTime time) =>
      '${time.toIso8601String().split('.').first}Z';

  // ---------------------------------------------------------------------------
  // GFI precipitation series
  // ---------------------------------------------------------------------------

  @override
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async {
    if (frames.isEmpty) return const Result.ok(null);

    final cacheKey = 'knmi_precip_'
        '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}'
        '_${frames.first.frameId}_${frames.last.frameId}';

    try {
      final raw = await _cache.getOrFetch(
        key: cacheKey,
        expiresAt: CacheExpiration.alignedNext(
          KnmiRadarConstants.cacheExpirationIntervalMinutes,
          KnmiRadarConstants.cacheExpirationDelayMinutes,
        ),
        fetch: () => _fetchGfiSeriesRaw(lat: lat, lon: lon, frames: frames),
      );
      if (raw == null) return const Result.ok(null);
      return Result.ok(KnmiGfi.parseSeries(raw));
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
  }

  Future<dynamic> _fetchGfiSeriesRaw({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      // ignore: use_null_aware_elements -- map-value null guard, not a key.
      if (wmsApiKey != null) 'Authorization': wmsApiKey!,
    };

    final mergedData = <String, dynamic>{};
    final chunkSize = KnmiRadarConstants.gfiTimestampsPerRequest;

    for (var i = 0; i < frames.length; i += chunkSize) {
      final chunk = frames.skip(i).take(chunkSize).toList();
      final uri = _buildGfiUri(lat: lat, lon: lon, chunk: chunk);

      final result = await _client.get(uri, headers: headers);
      switch (result) {
        case KnmiSuccess s:
          final decoded = KnmiGfi.decodeBody(s.response);
          if (decoded is List && decoded.isNotEmpty) {
            mergedData.addAll(decoded[0]['data'] as Map<String, dynamic>);
          }
        case KnmiQuotaExceeded _:
          // Circuit breaker open — surface a partial-or-null payload rather
          // than letting an exception take down the dashboard.
          return null;
        case KnmiError e:
          debugPrint('KNMI WMS GFI Error: ${e.statusCode} ${e.body}');
          return null;
      }
    }

    if (mergedData.isEmpty) return null;
    return [
      {'data': mergedData},
    ];
  }

  Uri _buildGfiUri({
    required double lat,
    required double lon,
    required List<RadarFrame> chunk,
  }) {
    final delta = KnmiRadarConstants.gfiBoundingBoxHalfDeltaDegrees;
    final start = chunk.first.time.toIso8601String().substring(0, 19);
    final end = chunk.last.time.toIso8601String().substring(0, 19);
    return Uri.parse(
      '$_baseHost'
      '?service=WMS&request=GetFeatureInfo'
      '&layers=precipitation_nowcast&query_layers=precipitation_nowcast'
      '&format=image%2Fpng&info_format=application%2Fjson'
      '&crs=EPSG%3A4326&width=1&height=1&x=0&y=0'
      '&bbox=${lon - delta},${lat - delta},${lon + delta},${lat + delta}'
      '&DATASET=radar_forecast_2.0'
      '&TIME=${start}Z/${end}Z',
    );
  }

  // ---------------------------------------------------------------------------
  // Layer config
  // ---------------------------------------------------------------------------

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) {
    return RadarLayerConfig(
      wmsOptions: WMSTileLayerOptions(
        baseUrl: '$_baseHost?DATASET=radar_forecast_2.0',
        layers: const ['precipitation_nowcast'],
        format: 'image/png',
        transparent: true,
        otherParameters: {'TIME': frame.frameId},
      ),
      headers: _authHeaders,
      apiClient: _client,
    );
  }
}
