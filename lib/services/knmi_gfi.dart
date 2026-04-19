import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather_models.dart';

/// Pure helpers for parsing KNMI WMS `GetFeatureInfo` responses.
abstract final class KnmiGfi {
  KnmiGfi._();

  /// Decodes the JSON GFI body. Returns `null` for non-JSON responses
  /// (typically WMS `<ServiceException>` XML), so callers can skip the chunk
  /// without crashing the dashboard.
  static dynamic decodeBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('json')) {
      return json.decode(response.body);
    }
    if (response.body.startsWith('<?xml') ||
        response.body.contains('<ServiceException>')) {
      debugPrint('KNMI WMS GFI returned XML: ${response.body}');
    }
    return null;
  }

  /// Converts the merged `[{"data": {time: value}}]` GFI shape into a
  /// [MinutelyForecast]. Returns `null` for malformed payloads.
  static MinutelyForecast? parseSeries(dynamic data) {
    try {
      final dataMap = Map<String, dynamic>.from(data[0]['data'] as Map);
      final sortedTimes = dataMap.keys.toList()..sort();
      return MinutelyForecast(
        times: [for (final t in sortedTimes) DateTime.parse(t)],
        precipitation: [
          for (final t in sortedTimes)
            double.tryParse(dataMap[t].toString()) ?? 0.0,
        ],
      );
    } catch (e) {
      debugPrint('Error parsing KNMI WMS GFI: $e');
      return null;
    }
  }
}
