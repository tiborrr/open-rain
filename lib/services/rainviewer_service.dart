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
class RainViewerService implements RadarProvider {
  RainViewerService({CacheStore? cacheStore, http.Client? httpClient})
      : _cache = cacheStore ?? CacheStore(),
        _http = httpClient ?? http.Client();

  static const String _indexUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  final CacheStore _cache;
  final http.Client _http;

  @override
  Future<Result<List<RadarFrame>>> fetchRadarFrames() async {
    try {
      final raw = await _cache.getOrFetch(
        key: 'radar_timestamps_v2',
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

      if (raw is! List) return const Result.ok([]);

      return Result.ok([
        for (final e in raw) RadarFrame.fromJson(Map<String, dynamic>.from(e)),
      ]);
    } on Exception catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(Exception(e.toString()));
    }
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
