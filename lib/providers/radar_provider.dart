import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';
import '../models/weather_models.dart';

abstract class RadarProvider {
  Future<List<RadarFrame>> fetchRadarFrames();
  RadarLayerConfig getLayerConfig(RadarFrame frame);
  Future<MinutelyForecast?> fetchPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) => Future.value(null);
}
