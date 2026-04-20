import '../models/weather_models.dart';

/// Result of [RainForecastAnalyzer.analyze] when rain is expected soon.
///
/// All times are UTC. [untilStart] is the gap between `now` and [startUtc];
/// [duration] is the contiguous wet stretch starting at [startUtc], measured
/// in whole [RainForecastAnalyzer.bucketSize] buckets.
class RainForecast {
  const RainForecast({
    required this.startUtc,
    required this.untilStart,
    required this.duration,
  });

  final DateTime startUtc;
  final Duration untilStart;
  final Duration duration;

  @override
  String toString() =>
      'RainForecast(startUtc: $startUtc, untilStart: $untilStart, duration: $duration)';
}

/// Classifies [MinutelyForecast] into a single "imminent rain" alert.
///
/// Open-Meteo's `minutely_15` endpoint publishes precipitation on a 15-minute
/// grid. We alert when:
///   * it's currently dry, AND
///   * a future bucket within the next [lookahead] crosses
///     [precipitationThresholdMm].
///
/// The duration is the count of contiguous wet buckets starting from the
/// first wet future bucket, converted back to minutes.
abstract final class RainForecastAnalyzer {
  RainForecastAnalyzer._();

  /// Minimum precipitation (mm per 15-min bucket) that counts as "rain".
  static const double precipitationThresholdMm = 0.1;

  /// How far ahead we look when deciding to fire an alert.
  static const Duration lookahead = Duration(minutes: 20);

  /// Width of a single Open-Meteo minutely_15 bucket.
  static const Duration bucketSize = Duration(minutes: 15);

  /// Returns a [RainForecast] when an alert should fire, or `null` otherwise.
  ///
  /// [nowUtc] must be in UTC; [MinutelyForecast.times] are also stored in UTC
  /// (see `WeatherData.parseTime`), so the comparisons below are consistent.
  static RainForecast? analyze({
    required MinutelyForecast minutely,
    required DateTime nowUtc,
  }) {
    if (minutely.times.isEmpty) return null;

    // Don't re-alert when the user is already getting wet.
    final currentIdx = _indexOfContaining(minutely.times, nowUtc);
    if (currentIdx != null &&
        minutely.precipitation[currentIdx] >= precipitationThresholdMm) {
      return null;
    }

    final horizon = nowUtc.add(lookahead);
    final startIdx = _firstWetFutureIndex(minutely, nowUtc, horizon);
    if (startIdx == null) return null;

    final endIdx = _lastContiguousWetIndex(minutely, startIdx);
    final start = minutely.times[startIdx];
    final bucketCount = endIdx - startIdx + 1;

    return RainForecast(
      startUtc: start,
      untilStart: _nonNegative(start.difference(nowUtc)),
      duration: bucketSize * bucketCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static int? _firstWetFutureIndex(
    MinutelyForecast minutely,
    DateTime nowUtc,
    DateTime horizon,
  ) {
    for (var i = 0; i < minutely.times.length; i++) {
      final t = minutely.times[i];
      if (!t.isAfter(nowUtc)) continue;
      if (t.isAfter(horizon)) break;
      if (minutely.precipitation[i] >= precipitationThresholdMm) return i;
    }
    return null;
  }

  static int _lastContiguousWetIndex(MinutelyForecast minutely, int startIdx) {
    var endIdx = startIdx;
    while (endIdx + 1 < minutely.times.length &&
        minutely.precipitation[endIdx + 1] >= precipitationThresholdMm) {
      endIdx++;
    }
    return endIdx;
  }

  static int? _indexOfContaining(List<DateTime> times, DateTime t) {
    for (var i = 0; i < times.length; i++) {
      final bucketStart = times[i];
      final bucketEnd = bucketStart.add(bucketSize);
      if (!t.isBefore(bucketStart) && t.isBefore(bucketEnd)) return i;
    }
    return null;
  }

  static Duration _nonNegative(Duration d) =>
      d.isNegative ? Duration.zero : d;
}
