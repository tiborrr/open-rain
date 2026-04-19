import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../utils/result.dart';

/// Source of radar imagery + optional point precipitation lookups.
///
/// `getLayerConfig` stays synchronous because tile rendering happens during
/// the build phase. Network-bound methods return [Result] so callers cannot
/// silently lose exceptions through async boundaries.
abstract class RadarProvider {
  Future<Result<List<RadarFrame>>> fetchRadarFrames();

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
