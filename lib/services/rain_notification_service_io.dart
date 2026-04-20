import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import 'rain_check_runner.dart';
import 'rain_forecast_analyzer.dart';

/// Mobile (iOS + Android) implementation of the rain notification service.
///
/// Keep the public surface minimal so the cross-platform facade can expose
/// the same API on web:
///   * [initialize]       — set up the plugin, request permissions, schedule BG
///   * [reportLocation]   — foreground informs BG where the user is
///   * [runCheckNow]      — foreground-triggered manual check
class PlatformRainNotificationService {
  PlatformRainNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: true,
        ),
      ),
    );

    // Android 13+ runtime POST_NOTIFICATIONS prompt. On older Android and on
    // iOS this resolves immediately with the correct status.
    await Permission.notification.request();

    await Workmanager().initialize(_rainCheckCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _periodicUniqueName,
      _periodicTaskName,
      // Android minimum is 15 min. iOS ignores this and uses the frequency
      // registered in AppDelegate.swift (BGTaskScheduler), which must match
      // the identifier in Info.plist.
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  Future<void> reportLocation({
    required double lat,
    required double lon,
  }) =>
      RainCheckRunner.saveLocation(lat, lon);

  Future<void> runCheckNow() async {
    final forecast = await RainCheckRunner.check();
    if (forecast == null) return;
    await _showRainNotification(_plugin, forecast);
  }
}

// =============================================================================
// Background isolate entry point.
// Must be a TOP-LEVEL function annotated with @pragma('vm:entry-point') so
// the Dart VM keeps it around for Workmanager's isolate spawner to find.
// =============================================================================

@pragma('vm:entry-point')
void _rainCheckCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // We are running in a fresh isolate. Flutter bindings are set up by
    // Workmanager, but plugin registrants for the BG isolate still have to
    // be re-initialized before touching any MethodChannel-backed plugins.
    DartPluginRegistrant.ensureInitialized();
    try {
      final forecast = await RainCheckRunner.check();
      if (forecast != null) {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(),
          ),
        );
        await _showRainNotification(plugin, forecast);
      }
      return true;
    } catch (e, st) {
      debugPrint('Rain check BG task failed: $e\n$st');
      // Returning false asks WorkManager to retry per its backoff policy.
      return false;
    }
  });
}

Future<void> _showRainNotification(
  FlutterLocalNotificationsPlugin plugin,
  RainForecast forecast,
) async {
  final untilMin = forecast.untilStart.inMinutes;
  final durMin = forecast.duration.inMinutes;
  await plugin.show(
    id: _notificationId,
    title: _titleFor(untilMin),
    body: _bodyFor(untilMin, durMin),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    ),
  );
}

String _titleFor(int untilMin) =>
    untilMin <= 1 ? 'Rain now' : 'Rain in $untilMin min';

String _bodyFor(int untilMin, int durMin) => untilMin <= 1
    ? 'Rain is starting. Expected to last about $durMin min.'
    : 'Rain starts in $untilMin min. Expected to last about $durMin min.';

// -----------------------------------------------------------------------------
// Identifiers. `_periodicUniqueName` MUST match the BGTaskScheduler identifier
// in ios/Runner/Info.plist and the `registerPeriodicTask(withIdentifier:)` call
// in ios/Runner/AppDelegate.swift — iOS uses the identifier to route
// BGAppRefreshTasks back to this plugin.
// -----------------------------------------------------------------------------
const String _periodicUniqueName = 'com.example.flutter_weather.rainCheck';
const String _periodicTaskName = 'rainCheck';

const String _channelId = 'rain_alerts';
const String _channelName = 'Rain alerts';
const String _channelDescription =
    'Notifies you about 20 minutes before rain reaches your location.';
const int _notificationId = 1001;
