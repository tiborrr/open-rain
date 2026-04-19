import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';
import '../utils/result.dart';

/// Repository for radar imagery + point precipitation.
///
/// Wraps a [RadarProvider] and surfaces [Result] so the UI layer cannot
/// silently inherit network exceptions. Layer-config is exposed as-is
/// because tile rendering happens during `build()` and must be synchronous.
class RadarRepository {
  RadarRepository(this._provider);

  final RadarProvider _provider;

  Future<Result<List<RadarFrame>>> getRadarFrames() =>
      _provider.fetchRadarFrames();

  Future<Result<MinutelyForecast?>> getPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) =>
      _provider.fetchPrecipitationSeries(
        lat: lat,
        lon: lon,
        frames: frames,
      );

  RadarLayerConfig getLayerConfig(RadarFrame frame) =>
      _provider.getLayerConfig(frame);
}
