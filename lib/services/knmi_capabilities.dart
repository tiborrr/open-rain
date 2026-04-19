import 'package:xml/xml.dart';

import '../constants/knmi_radar_constants.dart';

/// Pure parser for the KNMI WMS `GetCapabilities` document.
///
/// Extracted from the previous monolithic `KNMIService` so the windowing
/// logic can be unit-tested without spinning up an HTTP client. The test
/// file (`test/knmi_metadata_test.dart`) used to ship its own near-identical
/// copy of this code; it now calls [computeFrameTimes] directly so the test
/// and runtime cannot drift.
abstract final class KnmiCapabilities {
  KnmiCapabilities._();

  /// Returns the radar frame times that should be shown for the
  /// `precipitation_nowcast` layer described by [xmlString].
  ///
  /// Window:
  ///   [nowUtc - historyLookback, capabilities.endTime]
  /// Frames are aligned to the dimension's `PERIOD` (defaults to PT5M),
  /// clamped to the dimension's `START`/`END`.
  static List<DateTime> computeFrameTimes(
    String xmlString, {
    required DateTime nowUtc,
  }) {
    final document = XmlDocument.parse(xmlString);
    final layers = document.findAllElements('Layer');
    final nowcastLayer = layers.firstWhere(
      (l) => l
          .findElements('Name')
          .any((n) => n.innerText == 'precipitation_nowcast'),
      orElse: () =>
          throw const FormatException('Layer precipitation_nowcast not found'),
    );

    final timeDim = nowcastLayer.findElements('Dimension').firstWhere(
          (d) => d.getAttribute('name') == 'time',
          orElse: () =>
              throw const FormatException('Time dimension not found for nowcast'),
        );

    final timeText = timeDim.innerText.trim();
    final parts = timeText.split('/');
    if (parts.length != 3) {
      throw FormatException('Unexpected time dimension format: $timeText');
    }

    final fullStart = DateTime.parse(parts[0]);
    final fullEnd = DateTime.parse(parts[1]);
    final periodStr = parts[2];

    var intervalMinutes = KnmiRadarConstants.defaultFrameIntervalMinutes;
    if (periodStr.contains('PT')) {
      final m = RegExp(r'(\d+)M').firstMatch(periodStr);
      if (m != null) intervalMinutes = int.parse(m.group(1)!);
    }

    final alignedNow = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
      nowUtc.hour,
      (nowUtc.minute ~/ intervalMinutes) * intervalMinutes,
    );

    var windowStart = alignedNow.subtract(KnmiRadarConstants.historyLookback);
    final windowEnd = fullEnd;

    if (windowStart.isBefore(fullStart)) windowStart = fullStart;

    var current = fullStart;
    while (current.isBefore(windowStart)) {
      current = current.add(Duration(minutes: intervalMinutes));
    }

    final times = <DateTime>[];
    while (!current.isAfter(windowEnd)) {
      times.add(current);
      current = current.add(Duration(minutes: intervalMinutes));
    }
    return times;
  }
}
