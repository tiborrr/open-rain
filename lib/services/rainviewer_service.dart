import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';
import '../utils/cache_store.dart';
import '../utils/result.dart';

/// RainViewer radar provider. Returns past + nowcast frames from a single
/// `weather-maps.json` index, cached on the 10-minute publish boundary.
///
/// On each read we also apply [RadarFreshness.isStale] to the decoded
/// payload. A cache entry can still be within its wall-clock TTL while its
/// newest frame already aged out — in that case we invalidate and refetch
/// so the tile template we hand the map does not 404.
class RainViewerService implements RadarProvider {
  RainViewerService({CacheStore? cacheStore, http.Client? httpClient})
      : _cache = cacheStore ?? CacheStore(),
        _http = httpClient ?? http.Client();

  static const String _indexUrl =
      'https://api.rainviewer.com/public/weather-maps.json';
  static const String _framesCacheKey = 'radar_timestamps_v2';

  final CacheStore _cache;
  final http.Client _http;

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames({
    bool forceRefresh = false,
  }) async {
    try {
      var frames = _decodeFrames(
        await _fetchFramesRaw(forceRefresh: forceRefresh),
      );
      if (RadarFreshness.isStale(frames, DateTime.now().toUtc())) {
        await _cache.invalidate(_framesCacheKey);
        frames = _decodeFrames(
          await _fetchFramesRaw(forceRefresh: true),
        );
      }
      return Result.ok(frames);
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
  }

  Future<dynamic> _fetchFramesRaw({required bool forceRefresh}) {
    return _cache.getOrFetch(
      key: _framesCacheKey,
      forceRefresh: forceRefresh,
      expiresAt: CacheExpiration.alignedNext(10, 2),
      fetch: () async {
        final response = await _http.get(Uri.parse(_indexUrl));
        if (response.statusCode != 200) return null;
        final data = json.decode(response.body);
        final past = (data['radar']['past'] as List?) ?? const [];
        final nowcast = (data['radar']['nowcast'] as List?) ?? const [];
        final frames = <Map<String, dynamic>>[
          for (final item in [...past, ...nowcast])
            {
              'frameId': item['path'],
              'time': DateTime.fromMillisecondsSinceEpoch(
                      (item['time'] as num).toInt() * 1000)
                  .toIso8601String(),
            },
        ];
        return frames.isEmpty ? null : frames;
      },
    );
  }

  List<RadarFrame> _decodeFrames(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw) RadarFrame.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  @override
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) =>
      Future.value(const Result.ok(null));

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) {
    return RadarLayerConfig(
      urlTemplate:
          'https://tilecache.rainviewer.com${frame.frameId}/256/{z}/{x}/{y}/2/1_1.png',
    );
  }
}
