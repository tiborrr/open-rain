import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/radar_controller.dart';
import '../providers/radar_provider.dart';
import '../utils/throttled_tile_provider.dart';

class RadarMap extends StatefulWidget {
  final double lat;
  final double lon;
  final RadarController controller;
  final RadarProvider provider;

  const RadarMap({
    super.key,
    required this.lat,
    required this.lon,
    required this.controller,
    required this.provider,
  });

  @override
  State<RadarMap> createState() => _RadarMapState();
}

class _RadarMapState extends State<RadarMap> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(RadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lat != oldWidget.lat || widget.lon != oldWidget.lon) {
      _mapController.move(LatLng(widget.lat, widget.lon), _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.lat, widget.lon);

    return Container(
      height: 300,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 7.0,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
            userAgentPackageName: 'com.atmosphere.weather',
          ),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) {
              final frame = widget.controller.currentFrame;
              if (frame == null) return const SizedBox.shrink();
              final config = widget.provider.getLayerConfig(frame);
              return Opacity(
                opacity: 0.8,
                child: TileLayer(
                  key: ValueKey(frame.path),
                  urlTemplate: config.urlTemplate,
                  wmsOptions: config.wmsOptions,
                  tileProvider: config.apiClient != null
                      ? KnmiTileProvider(
                          apiClient: config.apiClient!,
                          headers: config.headers,
                        )
                      : NetworkTileProvider(headers: config.headers ?? {}),
                  tileBuilder: (context, tileWidget, tile) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2, 0, 0, 0, 0, // Red
                        0, 0.5, 0, 0, 0, // Green
                        0, 0, 1.2, 0, 0, // Blue (saturated)
                        0, 0, 0, 1.0, 0, // Alpha
                      ]),
                      child: tileWidget,
                    );
                  },
                  userAgentPackageName: 'com.atmosphere.weather',
                ),
              );
            },
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
