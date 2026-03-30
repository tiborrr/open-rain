import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/radar_provider.dart';
import '../models/radar_frame.dart';
import '../models/radar_layer_config.dart';

class RainViewerService extends RadarProvider {

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
    final result = await _getCachedOrFetch(
      cacheKey: 'radar_timestamps_v2',
      expirationTime: _calculateNextAlignedExpiration(10, 2),
      fetchFunction: () async {
        final url = Uri.parse('https://api.rainviewer.com/public/weather-maps.json');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final past = data['radar']['past'] as List;
          final nowcast = data['radar']['nowcast'] as List;
          
          final List<Map<String, dynamic>> frames = [];
          for (var item in past) {
            frames.add({
              'path': item['path'],
              'time': DateTime.fromMillisecondsSinceEpoch(item['time'] * 1000).toIso8601String(),
            });
          }
          for (var item in nowcast) {
            frames.add({
              'path': item['path'],
              'time': DateTime.fromMillisecondsSinceEpoch(item['time'] * 1000).toIso8601String(),
            });
          }
          
          return frames.isNotEmpty ? frames : null;
        }
        return null;
      },
    );
    
    if (result != null && result is List) {
      return result.map((e) => RadarFrame.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  @override
  RadarLayerConfig getLayerConfig(RadarFrame frame) {
    return RadarLayerConfig(
      urlTemplate: 'https://tilecache.rainviewer.com${frame.path}/256/{z}/{x}/{y}/2/1_1.png',
    );
  }
}
