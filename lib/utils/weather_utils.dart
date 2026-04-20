import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Open-Meteo uses [WMO weather interpretation codes](https://open-meteo.com/en/docs).
/// Icons are drawn from the Material Symbols font (rounded variant) to get
/// dedicated weather glyphs (`rainy_light`, `rainy_heavy`, `snowing_heavy`,
/// `weather_mix`, `weather_hail`, …) instead of overloaded Material Icons.
class WeatherUtils {
  static IconData getWeatherIcon(int code) {
    return switch (code) {
      0 => Symbols.sunny_rounded,
      1 || 2 => Symbols.partly_cloudy_day_rounded,
      3 => Symbols.cloud_rounded,
      45 || 48 => Symbols.foggy_rounded,
      51 || 53 => Symbols.rainy_light_rounded,
      55 => Symbols.rainy_rounded,
      56 || 57 => Symbols.weather_mix_rounded,
      61 => Symbols.rainy_light_rounded,
      63 => Symbols.rainy_rounded,
      65 => Symbols.rainy_heavy_rounded,
      66 || 67 => Symbols.weather_mix_rounded,
      71 => Symbols.weather_snowy_rounded,
      73 => Symbols.snowing_rounded,
      75 => Symbols.snowing_heavy_rounded,
      77 => Symbols.grain_rounded,
      80 => Symbols.rainy_light_rounded,
      81 => Symbols.rainy_rounded,
      82 => Symbols.rainy_heavy_rounded,
      85 => Symbols.weather_snowy_rounded,
      86 => Symbols.snowing_heavy_rounded,
      95 => Symbols.thunderstorm_rounded,
      96 || 99 => Symbols.weather_hail_rounded,
      _ => Symbols.cloud_rounded,
    };
  }

  static Color getWeatherColor(int code) {
    return switch (code) {
      0 => const Color(0xFFE6A300),
      1 || 2 || 3 => const Color(0xFF565E6D),
      45 || 48 => const Color(0xFF7D8592),
      51 || 53 || 55 => const Color(0xFF4A8FE8),
      56 || 57 => const Color(0xFF5B7FA8),
      61 => const Color(0xFF0056D2),
      63 => const Color(0xFF0048B8),
      65 => const Color(0xFF003898),
      66 || 67 => const Color(0xFF3D6B98),
      71 || 73 || 75 || 85 || 86 => const Color(0xFF007DA0),
      77 => const Color(0xFF6A9EAD),
      80 || 81 || 82 => const Color(0xFF0040A1),
      95 || 96 || 99 => const Color(0xFF4A49C9),
      _ => const Color(0xFF565E6D),
    };
  }

  static String getWeatherDescription(int code) {
    return switch (code) {
      0 => 'Clear sky',
      1 => 'Mainly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 => 'Fog',
      48 => 'Rime fog',
      51 => 'Light drizzle',
      53 => 'Moderate drizzle',
      55 => 'Heavy drizzle',
      56 => 'Light freezing drizzle',
      57 => 'Dense freezing drizzle',
      61 => 'Light rain',
      63 => 'Moderate rain',
      65 => 'Heavy rain',
      66 => 'Light freezing rain',
      67 => 'Heavy freezing rain',
      71 => 'Light snow',
      73 => 'Moderate snow',
      75 => 'Heavy snow',
      77 => 'Snow grains',
      80 => 'Light rain showers',
      81 => 'Moderate rain showers',
      82 => 'Violent rain showers',
      85 => 'Light snow showers',
      86 => 'Heavy snow showers',
      95 => 'Thunderstorm',
      96 => 'Thunderstorm & hail',
      99 => 'Severe thunderstorm & hail',
      _ => 'Cloudy',
    };
  }

  /// Precipitation chip line, e.g. `1.2 mm · Light rain` for WMO code 61.
  static String getPrecipitationChipLabel(double mm, int code) {
    return '${mm.toStringAsFixed(1)} mm · ${getWeatherDescription(code)}';
  }
}
