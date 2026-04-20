import 'rain_notification_service_io.dart'
    if (dart.library.html) 'rain_notification_service_web.dart';

/// Cross-platform rain notification service.
///
/// A thin facade that points at the correct platform implementation:
///   * iOS + Android: `rain_notification_service_io.dart` — local
///     notifications plugin + WorkManager/BGTaskScheduler.
///   * Web: `rain_notification_service_web.dart` — browser Notification API
///     + a foreground `Timer` (web has no reliable BG scheduler for Flutter).
///
/// All three implementations share [RainCheckRunner] for the weather fetch,
/// analysis, and dedup logic, so the "is it going to rain?" behavior is
/// identical across platforms.
typedef RainNotificationService = PlatformRainNotificationService;
