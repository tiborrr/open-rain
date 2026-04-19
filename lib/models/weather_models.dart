import 'package:latlong2/latlong.dart';

class WeatherData {
  final CurrentWeather current;
  final HourlyForecast hourly;
  final MinutelyForecast minutely;
  final DailyForecast daily;
  final Duration utcOffset;
  final String timezone;
  final WeatherAlert? alert;
  final AirQuality? airQuality;
  
  /// Surrounding precipitation data points, mapped by their coordinates.
  final Map<LatLng, MinutelyForecast> neighbors;

  WeatherData({
    required this.current,
    required this.hourly,
    required this.minutely,
    required this.daily,
    required this.utcOffset,
    required this.timezone,
    this.alert,
    this.airQuality,
    this.neighbors = const {},
  });

  /// The current time at the weather location.
  DateTime get localNow => DateTime.now().toUtc().add(utcOffset);

  /// Converts a UTC [time] to the local time at the weather location.
  DateTime toLocalLocation(DateTime utc) => utc.toUtc().add(utcOffset);

  /// Parses a time string from the API.
  /// If [offsetSeconds] is provided, it assumes the input is local time and converts it to UTC.
  static DateTime parseTime(String t, [int offsetSeconds = 0]) {
    if (t.contains('T')) {
      final dt = DateTime.parse(t.endsWith('Z') ? t : '${t}Z');
      return dt.subtract(Duration(seconds: offsetSeconds));
    } else {
      final dt = DateTime.parse('${t}T00:00:00Z');
      return dt.subtract(Duration(seconds: offsetSeconds));
    }
  }
}

class CurrentWeather {
  final double temperature;
  final int humidity;
  final double precipitation;
  final int weatherCode;
  final double windGust;
  final double lat;
  final double lon;

  CurrentWeather({
    required this.temperature,
    required this.humidity,
    required this.precipitation,
    required this.weatherCode,
    required this.windGust,
    required this.lat,
    required this.lon,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      humidity: (json['relative_humidity_2m'] as num).toInt(),
      precipitation: (json['precipitation'] as num).toDouble(),
      weatherCode: (json['weather_code'] as num).toInt(),
      windGust: (json['wind_gusts_10m'] as num).toDouble(),
      lat: (json['latitude'] as num).toDouble(),
      lon: (json['longitude'] as num).toDouble(),
    );
  }
}

class HourlyForecast {
  final List<DateTime> times;
  final List<double> temperatures;
  final List<int> weatherCodes;

  HourlyForecast({
    required this.times,
    required this.temperatures,
    required this.weatherCodes,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json, [int offsetSeconds = 0]) {
    return HourlyForecast(
      times: (json['time'] as List).map((t) => WeatherData.parseTime(t.toString(), offsetSeconds)).toList(),
      temperatures: (json['temperature_2m'] as List).map((t) => (t as num).toDouble()).toList(),
      weatherCodes: (json['weather_code'] as List).map((c) => (c as num).toInt()).toList(),
    );
  }
}

class MinutelyForecast {
  final List<DateTime> times;
  final List<double> precipitation;

  MinutelyForecast({
    required this.times,
    required this.precipitation,
  });

  factory MinutelyForecast.fromJson(Map<String, dynamic> json, [int offsetSeconds = 0]) {
    return MinutelyForecast(
      times: (json['time'] as List).map((t) => WeatherData.parseTime(t.toString(), offsetSeconds)).toList(),
      precipitation: (json['precipitation'] as List).map((p) => (p as num).toDouble()).toList(),
    );
  }

  /// Returns the entry of [times] closest to [epochMsUtc] (UTC milliseconds).
  ///
  /// Used by the precipitation chart scrubber to snap touch positions onto the
  /// Open-Meteo 15-minute grid instead of arbitrary axis pixels. Returns `null`
  /// when [times] is empty. On exact ties, the earlier timestamp wins so the
  /// behavior is deterministic.
  DateTime? nearestTimeUtcToMillis(int epochMsUtc) {
    if (times.isEmpty) return null;
    DateTime best = times.first;
    int bestDiff = (best.millisecondsSinceEpoch - epochMsUtc).abs();
    for (int i = 1; i < times.length; i++) {
      final t = times[i];
      final diff = (t.millisecondsSinceEpoch - epochMsUtc).abs();
      if (diff < bestDiff) {
        best = t;
        bestDiff = diff;
      }
    }
    return best;
  }
}

class DailyForecast {
  final List<DateTime> times;
  final List<double> maxTemps;
  final List<double> minTemps;
  final List<int> weatherCodes;

  DailyForecast({
    required this.times,
    required this.maxTemps,
    required this.minTemps,
    required this.weatherCodes,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json, [int offsetSeconds = 0]) {
    return DailyForecast(
      times: (json['time'] as List).map((t) => WeatherData.parseTime(t.toString(), offsetSeconds)).toList(),
      maxTemps: (json['temperature_2m_max'] as List).map((t) => (t as num).toDouble()).toList(),
      minTemps: (json['temperature_2m_min'] as List).map((t) => (t as num).toDouble()).toList(),
      weatherCodes: (json['weather_code'] as List).map((c) => (c as num).toInt()).toList(),
    );
  }
}

class WeatherAlert {
  final String title;
  final String message;
  final String type;

  WeatherAlert({
    required this.title,
    required this.message,
    required this.type,
  });
}

class AirQuality {
  final int aqi;
  final double pm2_5;
  final double ozone;

  AirQuality({
    required this.aqi,
    required this.pm2_5,
    required this.ozone,
  });

  factory AirQuality.fromJson(Map<String, dynamic> json) {
    return AirQuality(
      aqi: (json['european_aqi'] as num).toInt(),
      pm2_5: (json['pm2_5'] as num).toDouble(),
      ozone: (json['ozone'] as num).toDouble(),
    );
  }

  String get status {
    if (aqi <= 20) return 'Good';
    if (aqi <= 40) return 'Fair';
    if (aqi <= 60) return 'Moderate';
    if (aqi <= 80) return 'Poor';
    return 'Very Poor';
  }

  String get recommendation {
    if (aqi <= 20) return 'Perfect for outdoor activities.';
    if (aqi <= 40) return 'Enjoy your outdoor time.';
    if (aqi <= 60) return 'Sensitive groups should reduce exertion.';
    if (aqi <= 80) return 'Consider moving activities indoors.';
    return 'Stay indoors and keep windows closed.';
  }
}
