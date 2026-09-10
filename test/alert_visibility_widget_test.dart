import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/models/weather_models.dart';
import 'package:flutter_weather/widgets/severe_alert_card.dart';

void main() {
  group('Alert Visibility & Anti-Hardcoding Automated Invariant Tests', () {
    testWidgets('SevereAlertCard dynamically displays title and message without hardcoding', (
      WidgetTester tester,
    ) async {
      final alert = WeatherAlert(
        title: 'High Wind Advisory',
        message: 'Wind gusts exceeding 85 km/h detected.',
        type: 'danger',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SevereAlertCard(alert: alert),
          ),
        ),
      );

      expect(find.text('High Wind Advisory'), findsOneWidget);
      expect(find.text('Wind gusts exceeding 85 km/h detected.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    test('Architecture: No hardcoded static alert titles exist in widget trees', () {
      final widgetsDir = Directory('lib/widgets');
      final screensDir = Directory('lib/screens');

      final files = [
        ...widgetsDir.listSync(recursive: true),
        ...screensDir.listSync(recursive: true),
      ].whereType<File>().where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];
      for (final file in files) {
        final content = file.readAsStringSync();
        // Disallow static text mocking alert titles in UI
        if (content.contains("'Severe Weather Alert'") ||
            content.contains('"Severe Weather Alert"')) {
          violations.add('${file.path}: Contains hardcoded "Severe Weather Alert" string');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Alert titles must come from WeatherAlert model or WeatherAlertAnalyzer, never hardcoded.',
      );
    });
  });
}
