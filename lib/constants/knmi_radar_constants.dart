/// Tunables for KNMI WMS radar frame discovery and GetFeatureInfo batching.
abstract final class KnmiRadarConstants {
  KnmiRadarConstants._();

  /// How far before wall-clock (UTC) “now” to start the radar frame window.
  static const Duration historyLookback = Duration(minutes: 30);

  /// Used when GetCapabilities does not specify an interval (typical nowcast is PT5M).
  static const int defaultFrameIntervalMinutes = 5;

  /// Fallback timeline when capabilities fail: step between synthetic frames.
  static const Duration fallbackFrameStep = Duration(minutes: defaultFrameIntervalMinutes);

  /// Fallback: number of frames at [fallbackFrameStep] (~3h of animation from first frame).
  static const int fallbackFrameCount = 36;

  /// SharedPreferences TTL alignment for capabilities / GFI cache.
  static const int cacheExpirationIntervalMinutes = defaultFrameIntervalMinutes;
  static const int cacheExpirationDelayMinutes = 1;

  /// GFI allows a limited number of `TIME` values per request (12 steps at 5 min is one hour).
  static const int gfiTimestampsPerRequest = 12;

  /// Half-width of the WMS GetFeatureInfo bbox in degrees (point query around the pin).
  static const double gfiBoundingBoxHalfDeltaDegrees = 0.01;

  /// Background dashboard poll: metadata, frame list, and weather. Kept near KNMI radar
  /// product refresh cadence (~15 min) so we do not re-query capabilities every few minutes
  /// when new tiles are not expected yet. Pull-to-refresh / toolbar refresh still forces reload.
  static const Duration dashboardBackgroundPollInterval = Duration(minutes: 15);
}
