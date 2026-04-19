import '../models/weather_models.dart';

/// Pure rules that turn parsed weather signals into a [WeatherAlert].
///
/// Lifted out of `WeatherRepository` so it can be unit-tested independently
/// and reused by other repositories (e.g. a future combined NL/EU source).
abstract final class WeatherAlertAnalyzer {
  WeatherAlertAnalyzer._();

  /// Heavy-rain threshold (mm per 15-minute slot) considered "danger".
  static const double _heavyRainMmPer15min = 5.0;

  /// Number of leading 15-min slots scanned for incoming heavy rain.
  static const int _lookaheadSlots = 8;

  /// Heat-advisory threshold in degrees Celsius.
  static const double _heatAdvisoryC = 35.0;

  /// Returns the highest-severity alert applicable, or `null` if none fires.
  static WeatherAlert? analyze({
    required CurrentWeather current,
    required MinutelyForecast minutely,
  }) {
    final upcoming = minutely.precipitation.take(_lookaheadSlots);
    final hasHeavyRain = upcoming.any((p) => p > _heavyRainMmPer15min);
    if (hasHeavyRain) {
      return WeatherAlert(
        title: 'Heavy Rain Warning',
        message: 'Extreme precipitation expected in the next 2 hours.',
        type: 'danger',
      );
    }

    if (current.temperature > _heatAdvisoryC) {
      return WeatherAlert(
        title: 'Heat Advisory',
        message: 'Extreme heat detected. Stay hydrated.',
        type: 'warning',
      );
    }

    return null;
  }
}
