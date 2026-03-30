import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_weather/main.dart';

void main() {
  testWidgets('App compiles and runs', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // By default, the app starts in a loading state.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
