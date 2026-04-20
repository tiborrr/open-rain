import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/radar_controller.dart';
import '../models/radar_frame.dart';
import '../providers/radar_provider.dart';
import '../utils/throttled_tile_provider.dart';

/// A radar overlay that preloads every frame so animation advances never
/// flicker.
///
/// Problem solved:
///   The prior implementation rendered a single [TileLayer] keyed by the
///   current frame id. Every tick the TileLayer was unmounted, the next was
///   mounted, and its tiles had to be re-fetched + re-decoded. Combined with
///   flutter_map's default 100ms fade-in, this produced a visible flash per
///   tick.
///
/// Solution:
///   Mount one [TileLayer] per frame up-front, inside the map's child list.
///   Active frame is rendered at full opacity; all others at `opacity: 0`,
///   which [Opacity] short-circuits — no paint cost, but the TileLayer stays
///   laid out so flutter_map keeps requesting and caching its tiles. Moving
///   between frames becomes a zero-cost opacity swap.
///
///   Frames are emitted in priority order (current → current+1 → …) so the
///   tile requests for the currently-visible frame enter the rate-limited
///   [KnmiApiClient] queue ahead of lookahead frames. Layers are keyed by
///   `frameId`, letting Flutter match elements across reorderings so the
///   reorder does not trigger remounts.
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

  static const double _initialZoom = 7.0;

  /// Radar tint applied to every tile (desaturates red/green, saturates blue)
  /// so precipitation stands out against the basemap.
  static const ColorFilter _radarColorFilter = ColorFilter.matrix([
    0.2, 0, 0, 0, 0, // Red
    0, 0.5, 0, 0, 0, // Green
    0, 0, 1.2, 0, 0, // Blue (saturated)
    0, 0, 0, 1.0, 0, // Alpha
  ]);

  @override
  void didUpdateWidget(RadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lat != oldWidget.lat || widget.lon != oldWidget.lon) {
      // Reading [MapController.camera] before [FlutterMap] has rendered once
      // throws (see flutter_map MapControllerImpl). Location can update on the
      // first dashboard frame while the map is still attaching — defer the move.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final zoom = _mapController.camera.zoom;
        _mapController.move(LatLng(widget.lat, widget.lon), zoom);
      });
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
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _initialZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
              userAgentPackageName: 'com.atmosphere.weather',
            ),
            ..._buildRadarFrameLayers(),
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
      ),
    );
  }

  /// Builds one [TileLayer] per radar frame. The current frame is painted at
  /// 0.8 opacity, every other frame at 0 (paint short-circuits, state stays,
  /// tiles stay cached). Children are emitted in advancing-priority order so
  /// the active frame's tile fetches land at the head of the rate-limited
  /// queue ahead of lookahead frames.
  List<Widget> _buildRadarFrameLayers() {
    final frames = widget.controller.frames;
    final currentIndex = widget.controller.currentIndex;
    if (frames.isEmpty) return const [];

    final count = frames.length;
    return [
      for (var offset = 0; offset < count; offset++)
        () {
          final i = (currentIndex + offset) % count;
          final frame = frames[i];
          return Opacity(
            key: ValueKey(frame.frameId),
            opacity: i == currentIndex ? 0.8 : 0.0,
            child: _buildRadarTileLayer(frame),
          );
        }(),
    ];
  }

  Widget _buildRadarTileLayer(RadarFrame frame) {
    final config = widget.provider.getLayerConfig(frame);
    return TileLayer(
      urlTemplate: config.urlTemplate,
      wmsOptions: config.wmsOptions,
      // Only fetch tiles strictly inside the viewport. KNMI WMS has a tight
      // quota and each animation frame would otherwise also request the
      // surrounding panBuffer/keepBuffer rings.
      panBuffer: 0,
      keepBuffer: 0,
      tileProvider: config.apiClient != null
          ? KnmiTileProvider(
              apiClient: config.apiClient!,
              headers: config.headers,
            )
          : NetworkTileProvider(headers: config.headers ?? {}),
      // Disable the default 100ms fade-in so tiles show up the moment they
      // are decoded — no per-tile flicker on first paint of a frame.
      tileDisplay: const TileDisplay.instantaneous(),
      tileBuilder: (context, tileWidget, tile) => ColorFiltered(
        colorFilter: _radarColorFilter,
        child: tileWidget,
      ),
      userAgentPackageName: 'com.atmosphere.weather',
    );
  }
}
