import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_weather/main.dart';

void main() {
  setUpAll(() async {
    // Load a minimal dotenv so HomeScreen can read env vars without crashing.
    await dotenv.load(mergeWith: {'KNMI_WMS_API_KEY': ''});
  });

  testWidgets('App compiles and renders initial loading state', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // The app starts in loading/initial state — a progress indicator is shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
