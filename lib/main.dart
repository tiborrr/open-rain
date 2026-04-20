import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'providers/radar_provider.dart';
import 'providers/weather_provider.dart';
import 'repositories/radar_repository.dart';
import 'repositories/weather_repository.dart';
import 'screens/home_screen.dart';
import 'services/knmi_service.dart';
import 'services/location_service.dart';
import 'services/open_meteo_service.dart';
import 'services/rain_notification_service.dart';
import 'theme.dart';
import 'view_models/home_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  // Rain alerts: initialize eagerly so the background task is scheduled on
  // first launch and notification permissions are requested as part of the
  // cold start. Any failure is logged but must not block the UI.
  final rainNotifications = RainNotificationService();
  try {
    await rainNotifications.initialize();
  } catch (e, st) {
    debugPrint('Failed to initialize rain notifications: $e\n$st');
  }

  runApp(MyApp(rainNotifications: rainNotifications));
}

/// App composition root.
///
/// Following the Flutter architecture guide, dependency wiring lives at the
/// app root rather than inside individual screens. Services are constructed
/// once, repositories close over them, and the view-model is provided to the
/// widget tree. `Provider.value` is used for already-constructed instances;
/// the view-model uses `ChangeNotifierProvider` so its `dispose` runs when
/// the tree is torn down.
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.rainNotifications});

  final RainNotificationService rainNotifications;

  @override
  Widget build(BuildContext context) {
    final weatherProvider = OpenMeteoService();
    final radarProvider = KNMIService(
      wmsApiKey: dotenv.env['KNMI_WMS_API_KEY'],
    );
    final weatherRepository = WeatherRepository(weatherProvider);
    final radarRepository = RadarRepository(radarProvider);
    final locationService = LocationService();

    return MultiProvider(
      providers: [
        Provider<WeatherProvider>.value(value: weatherProvider),
        Provider<RadarProvider>.value(value: radarProvider),
        Provider<WeatherRepository>.value(value: weatherRepository),
        Provider<RadarRepository>.value(value: radarRepository),
        Provider<LocationService>.value(value: locationService),
        Provider<RainNotificationService>.value(value: rainNotifications),
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(
            weatherRepository: weatherRepository,
            radarRepository: radarRepository,
            locationService: locationService,
            onLocationResolved: (lat, lon) => rainNotifications.reportLocation(
              lat: lat,
              lon: lon,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Atmosphere Weather',
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
