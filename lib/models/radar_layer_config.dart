import 'package:flutter_map/flutter_map.dart';
import '../utils/knmi_api_client.dart';

class RadarLayerConfig {
  final String? urlTemplate;
  final WMSTileLayerOptions? wmsOptions;
  final Map<String, String>? headers;
  /// The shared API client to use for fetching tiles. When provided, the tile
  /// provider will route all requests through it (rate limiting + circuit breaker).
  final KnmiApiClient? apiClient;

  RadarLayerConfig({
    this.urlTemplate,
    this.wmsOptions,
    this.headers,
    this.apiClient,
  }) : assert(urlTemplate != null || wmsOptions != null,
            'Either urlTemplate or wmsOptions must be provided');

  bool get isWms => wmsOptions != null;
}
