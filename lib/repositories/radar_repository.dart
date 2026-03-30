import '../models/radar_frame.dart';
import '../models/weather_models.dart';
import '../providers/radar_provider.dart';

class RadarRepository {
  final RadarProvider _provider;

  RadarRepository(this._provider);

  Future<List<RadarFrame>> getRadarFrames() async {
    return await _provider.fetchRadarFrames();
  }

  Future<MinutelyForecast?> getPrecipitationSeries({
    required double lat,
    required double lon,
    required List<RadarFrame> frames,
  }) async {
    return await _provider.fetchPrecipitationSeries(
      lat: lat,
      lon: lon,
      frames: frames,
    );
  }
}
