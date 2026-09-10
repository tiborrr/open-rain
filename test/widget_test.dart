import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/main.dart';
import 'package:flutter_weather/services/rain_notification_service.dart';

void main() {

  testWidgets('App compiles and renders initial loading state', (WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(
        rainNotifications: RainNotificationService(),
        persistedKnmiApiKey: null,
      ),
    );
    // The app starts in loading/initial state — a progress indicator is shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('HomeScreen respects system insets via SafeArea', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: 48, bottom: 34),
        ),
        child: MyApp(
          rainNotifications: RainNotificationService(),
          persistedKnmiApiKey: null,
        ),
      ),
    );

    expect(find.byType(SafeArea), findsWidgets);
  });
}
