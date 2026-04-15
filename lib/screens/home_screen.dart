import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../controllers/radar_controller.dart';
import '../providers/radar_provider.dart';
import '../services/open_meteo_service.dart';
import '../services/knmi_service.dart';
import '../repositories/weather_repository.dart';
import '../repositories/radar_repository.dart';
import '../view_models/home_view_model.dart';
import 'package:provider/provider.dart';
import '../widgets/radar_map.dart';
import '../widgets/precipitation_chart.dart';
import '../widgets/current_conditions_card.dart';
import '../widgets/forecast_widgets.dart';
import '../widgets/severe_alert_card.dart';
import '../widgets/location_search_overlay.dart';
import '../widgets/air_quality_card.dart';
import '../widgets/attribution_footer.dart';
import '../services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeViewModel _viewModel;
  final RadarController _radarController = RadarController();
  final RadarProvider _radarProvider = KNMIService(
    wmsApiKey: dotenv.env['KNMI_WMS_API_KEY'],
  );
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Dependency Injection (Simplified)
    final weatherProvider = OpenMeteoService();
    final weatherRepository = WeatherRepository(weatherProvider);
    final radarRepository = RadarRepository(_radarProvider);
    final locationService = LocationService();

    _viewModel = HomeViewModel(
      weatherRepository: weatherRepository,
      radarRepository: radarRepository,
      locationService: locationService,
    );

    _loadData();
    _pollingTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadData());

    _viewModel.addListener(() {
       if (_viewModel.status == HomeStatus.success) {
         _radarController.setFrames(
           _viewModel.radarFrames, 
           initialTime: DateTime.now().toUtc(),
         );

         if (!_radarController.isPlaying) {
           _radarController.play();
         }
       }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _radarController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  void _loadData() {
    _viewModel.loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          switch (_viewModel.status) {
            case HomeStatus.initial:
              return const Center(child: CircularProgressIndicator());
            case HomeStatus.loading:
              if (_viewModel.weatherData != null) return _buildDashboard(context);
              return const Center(child: CircularProgressIndicator());
            case HomeStatus.error:
              if (_viewModel.weatherData != null) return _buildDashboard(context);
              return Center(child: Text('Error: ${_viewModel.errorMessage}'));
            case HomeStatus.success:
              return _buildDashboard(context);
          }
        },
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final weather = _viewModel.weatherData!;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                children: [
                  Image.asset('assets/images/logo.png', height: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _viewModel.currentLocationName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 28,
                            ),
                          ),
                        ),
                        if (_viewModel.status == HomeStatus.loading) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh, size: 20),
                    ),
                    onPressed: _loadData,
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search, size: 20),
                    ),
                    onPressed: () => _showSearchOverlay(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            RadarMap(
              lat: _viewModel.weatherData?.current.lat ?? 52.3676,
              lon: _viewModel.weatherData?.current.lon ?? 4.9041,
              controller: _radarController,
              provider: _radarProvider,
            ),
            PrecipitationChart(
              forecast: weather.minutely,
              controller: _radarController,
              localNow: weather.localNow,
              utcOffset: weather.utcOffset,
            ),
            const SizedBox(height: 32),
            if (weather.alert != null) ...[
              SevereAlertCard(alert: weather.alert!),
              const SizedBox(height: 32),
            ],
            CurrentConditionsCard(
              current: weather.current,
              localNow: weather.localNow,
              timezone: weather.timezone,
            ),
            if (weather.airQuality != null) ...[
              const SizedBox(height: 32),
              AirQualityCard(airQuality: weather.airQuality!),
            ],
            const SizedBox(height: 32),
            HourlyForecastList(
              forecast: weather.hourly,
              utcOffset: weather.utcOffset,
              localNow: weather.localNow,
            ),
            const SizedBox(height: 32),
            DailyForecastList(
              forecast: weather.daily,
              utcOffset: weather.utcOffset,
            ),
            const AttributionFooter(),
          ],
        ),
      ),
    );
  }

  void _showSearchOverlay(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12,
      barrierDismissible: true,
      barrierLabel: 'Search',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ChangeNotifierProvider.value(
          value: _viewModel,
          child: const LocationSearchOverlay(),
        );
      },
    );
  }
}
