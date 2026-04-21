import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../utils/result.dart';

/// Shared freshness policy for radar frame caches.
///
/// Upstream nowcasts (KNMI, RainViewer) publish roughly every 5–10 minutes
/// and reject `TIME=` values older than ~30 minutes, so any cached frame
/// list whose newest frame is older than [maxAge] can no longer produce
/// valid tiles and must be refetched. Also used as the user-facing contract
/// for "drop frames older than 30 min".
abstract final class RadarFreshness {
  RadarFreshness._();

  static const Duration maxAge = Duration(minutes: 30);

  /// True when [frames] contain no frame within [maxAge] of [now].
  static bool isStale(List<RadarFrame> frames, DateTime now) {
    if (frames.isEmpty) return true;
    final newest = frames
        .map((f) => f.time)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return now.difference(newest) > maxAge;
  }
}

/// Source of radar imagery + optional point precipitation lookups.
///
/// `getLayerConfig` stays synchronous because tile rendering happens during
/// the build phase. Network-bound methods return [Result] so callers cannot
/// silently lose exceptions through async boundaries.
abstract class RadarProvider {
  /// Fetch the current frame timeline.
  ///
  /// Implementations must:
  /// * bypass any on-disk cache when [forceRefresh] is true (user-initiated
  ///   reloads cannot keep serving yesterday's frames);
  /// * treat a cached payload whose newest frame is older than
  ///   [RadarFreshness.maxAge] as stale and re-fetch, otherwise the KNMI
  ///   nowcast layer rejects the expired `TIME` and tiles stop rendering.
  Future<Result<List<RadarFrame>>> fetchRadarFrames({
    bool forceRefresh = false,
  });

  RadarLayerConfig getLayerConfig(RadarFrame frame);

  /// Optional: pull a precipitation time series for [lat]/[lon] aligned to
  /// the available [frames]. Returns `Ok(null)` when the provider does not
  /// support it (e.g. RainViewer).
  Future<Result<MinutelyForecast?>> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) =>
      Future.value(const Result.ok(null));
}
