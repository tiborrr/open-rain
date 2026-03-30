import 'package:flutter/material.dart';

class WeatherUtils {
  static IconData getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_rounded;
    if (code >= 45 && code <= 48) return Icons.filter_drama_rounded;
    if (code >= 51 && code <= 67) return Icons.water_drop_rounded;
    if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
    if (code >= 80 && code <= 82) return Icons.umbrella_rounded;
    if (code >= 95 && code <= 99) return Icons.thunderstorm_rounded;
    return Icons.wb_cloudy_rounded;
  }

  static Color getWeatherColor(int code) {
    if (code == 0) return const Color(0xFFE6A300); // Darker Vibrant Sun
    if (code >= 1 && code <= 3) return const Color(0xFF565E6D); // Deep Slate Clouds
    if (code >= 45 && code <= 48) return const Color(0xFF7D8592); // Darker Fog
    if (code >= 51 && code <= 67) return const Color(0xFF0056D2); // Deep Rain Blue
    if (code >= 71 && code <= 77) return const Color(0xFF007DA0); // Arctic Deep Blue for Snow
    if (code >= 80 && code <= 82) return const Color(0xFF0040A1); // Deep Shower Blue
    if (code >= 95 && code <= 99) return const Color(0xFF4A49C9); // Deep Thunder Purple
    return const Color(0xFF565E6D);
  }

  static String getWeatherDescription(int code) {
    if (code == 0) return 'Sunny';
    if (code >= 1 && code <= 3) return 'Partly Cloudy';
    if (code >= 45 && code <= 48) return 'Foggy';
    if (code >= 51 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Showers';
    if (code >= 95 && code <= 99) return 'Thunderstorm';
    return 'Cloudy';
  }
}
