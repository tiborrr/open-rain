// This file is web-only and is selected by conditional imports in
// `rain_notification_service.dart`. `dart:html` is flagged as deprecated in
// favor of `package:web` but the Notification bindings we need are a tiny
// slice of the legacy API and work identically on current Flutter stable.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'rain_check_runner.dart';
import 'rain_forecast_analyzer.dart';

/// Web implementation of the rain notification service.
///
/// The browser has no reliable true-background scheduler for a Flutter web
/// app: Service Worker periodic sync is limited to installed PWAs on a few
/// browsers. Instead we run the same [RainCheckRunner] in the foreground on
/// a 15-minute [Timer] whenever the tab is open, and fire a browser
/// `Notification` if the analyzer finds imminent rain. This matches the
/// mobile cadence and shares 100% of the detection logic.
class PlatformRainNotificationService {
  PlatformRainNotificationService();

  static const Duration _checkInterval = Duration(minutes: 15);
  static const Duration _initialDelay = Duration(seconds: 5);

  Timer? _timer;
  bool _permissionGranted = false;

  Future<void> initialize() async {
    _permissionGranted = await _ensurePermission();
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => runCheckNow());
    unawaited(Future.delayed(_initialDelay, runCheckNow));
  }

  Future<void> reportLocation({
    required double lat,
    required double lon,
  }) =>
      RainCheckRunner.saveLocation(lat, lon);

  Future<void> runCheckNow() async {
    if (!_permissionGranted) return;
    try {
      final forecast = await RainCheckRunner.check();
      if (forecast != null) _show(forecast);
    } catch (e, st) {
      debugPrint('Web rain check failed: $e\n$st');
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<bool> _ensurePermission() async {
    if (!html.Notification.supported) return false;
    var perm = html.Notification.permission;
    if (perm == 'default') {
      perm = await html.Notification.requestPermission();
    }
    return perm == 'granted';
  }

  void _show(RainForecast forecast) {
    final untilMin = forecast.untilStart.inMinutes;
    final durMin = forecast.duration.inMinutes;
    html.Notification(
      untilMin <= 1 ? 'Rain now' : 'Rain in $untilMin min',
      body: untilMin <= 1
          ? 'Rain is starting. Expected to last about $durMin min.'
          : 'Rain starts in $untilMin min. Expected to last about $durMin min.',
      tag: 'rain_alerts',
    );
  }
}
