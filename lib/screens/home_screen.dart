import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/knmi_radar_constants.dart';
import '../controllers/radar_controller.dart';
import '../providers/radar_provider.dart';
import '../services/knmi_service.dart';
import '../utils/knmi_api_key_store.dart';
import '../utils/knmi_raster_tile_cache.dart';
import '../utils/throttled_tile_provider.dart';
import '../view_models/home_view_model.dart';
import '../widgets/air_quality_card.dart';
import '../widgets/attribution_footer.dart';
import '../widgets/current_conditions_card.dart';
import '../widgets/forecast_widgets.dart';
import '../widgets/location_search_overlay.dart';
import '../widgets/precipitation_chart.dart';
import '../widgets/radar_map.dart';
import '../widgets/severe_alert_card.dart';

/// Dashboard screen.
///
/// All dependencies are read from the surrounding `Provider` (composed in
/// `main.dart`). The screen owns short-lived UI state only:
///   * a [RadarController] driving the radar animation
///   * a polling [Timer] for background reloads
///   * a listener that prints command errors as a `SnackBar`
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final RadarController _radarController = RadarController();
  Timer? _pollingTimer;
  HomeViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final vm = context.read<HomeViewModel>();
    _viewModel = vm;
    vm.loadDashboard.addListener(_onLoadDashboardChanged);
    vm.loadDashboard.execute(null);
    _pollingTimer = Timer.periodic(
      KnmiRadarConstants.dashboardBackgroundPollInterval,
      (_) => vm.loadDashboard.execute(null),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _viewModel?.loadDashboard.removeListener(_onLoadDashboardChanged);
    _radarController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _viewModel?.loadDashboard.execute(null);
    }
  }

  /// Hook the dashboard load completion so the radar animation latches onto
  /// freshly discovered frames and so transient errors surface as a snackbar.
  void _onLoadDashboardChanged() {
    final vm = _viewModel;
    if (vm == null) return;

    if (vm.loadDashboard.completed && vm.radarFrames.isNotEmpty) {
      _radarController.setFrames(
        vm.radarFrames,
        initialTime: DateTime.now().toUtc(),
      );
      if (!_radarController.isPlaying) _radarController.play();
    }

    if (vm.loadDashboard.error) {
      final err = vm.loadDashboard.errorObject;
      vm.loadDashboard.clearResult();
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to load: $err')),
      );
    }
  }

  /// User-initiated refresh: also bust the KNMI tile bytes cache so the next
  /// frame mount re-decodes fresh imagery instead of serving cached tiles.
  void _refreshFromUser() {
    KnmiRasterTileCache.instance.clear();
    KnmiTileProvider.bumpImageCacheGeneration();
    context.read<HomeViewModel>().loadDashboard.execute(null);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final radarProvider = context.read<RadarProvider>();

    return Scaffold(
      body: ListenableBuilder(
        listenable: vm.loadDashboard,
        builder: (context, _) {
          if (vm.isInitialLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = vm.weatherData;
          if (data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Failed to load weather data: '
                  '${vm.loadDashboard.errorObject ?? "unknown error"}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _buildDashboard(context, vm, radarProvider);
        },
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    HomeViewModel vm,
    RadarProvider radarProvider,
  ) {
    final weather = vm.weatherData!;
    final loading = vm.loadDashboard.running;

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
                            vm.currentLocationName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 28,
                                ),
                          ),
                        ),
                        if (loading) ...[
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search, size: 20),
                    ),
                    onPressed: () => _showSearchOverlay(context),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings, size: 20),
                    ),
                    onPressed: _showKnmiSettingsDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Stack(
              children: [
                RadarMap(
                  lat: weather.current.lat,
                  lon: weather.current.lon,
                  controller: _radarController,
                  provider: radarProvider,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _refreshFromUser,
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
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
    final vm = context.read<HomeViewModel>();
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12,
      barrierDismissible: true,
      barrierLabel: 'Search',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ChangeNotifierProvider.value(
          value: vm,
          child: const LocationSearchOverlay(),
        );
      },
    );
  }

  Future<void> _showKnmiSettingsDialog() async {
    final radarProvider = context.read<RadarProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentKey = radarProvider is KNMIService
        ? (radarProvider.wmsApiKey ?? '')
        : '';
    final controller = TextEditingController(text: currentKey);
    var saveError = '';
    const requestKeyUrl = 'https://developer.dataplatform.knmi.nl/apis/';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('KNMI API key'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Provide your KNMI WMS API key here for higher request '
                      'limits. Leave empty to use anonymous access.',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'How to request one: create/sign in to your KNMI '
                      'Developer account and request an API key for the '
                      'Web Map Service (WMS) API.',
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(requestKeyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open KNMI APIs page'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'KNMI API key',
                        hintText: 'Paste your WMS API key',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (saveError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        saveError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final key = controller.text.trim();
                    try {
                      await KnmiApiKeyStore.save(key.isEmpty ? null : key);
                      if (radarProvider is KNMIService) {
                        radarProvider.setWmsApiKey(
                          key.isEmpty ? null : key,
                        );
                      }
                      if (!mounted) return;
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      _refreshFromUser();
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            key.isEmpty
                                ? 'Switched to anonymous KNMI access.'
                                : 'KNMI API key saved.',
                          ),
                        ),
                      );
                    } catch (e) {
                      setState(() {
                        saveError = 'Could not save key: $e';
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }
}
