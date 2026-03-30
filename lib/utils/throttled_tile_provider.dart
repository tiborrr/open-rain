import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'knmi_api_client.dart';

/// A TileProvider that routes all network requests through [KnmiApiClient].
///
/// When the circuit breaker is open (quota exceeded), tiles are silently
/// replaced with a transparent image — no exceptions, no log spam.
class KnmiTileProvider extends TileProvider {
  final KnmiApiClient apiClient;

  KnmiTileProvider({required this.apiClient, Map<String, String>? headers})
      : super(headers: headers ?? {});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _KnmiTileImage(url, apiClient: apiClient, headers: headers);
  }
}

class _KnmiTileImage extends ImageProvider<_KnmiTileImage> {
  final String url;
  final KnmiApiClient apiClient;
  final Map<String, String>? headers;

  _KnmiTileImage(this.url, {required this.apiClient, this.headers});

  @override
  Future<_KnmiTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_KnmiTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(_KnmiTileImage key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, chunkEvents, decode),
      scale: 1.0,
      chunkEvents: chunkEvents.stream,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<_KnmiTileImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _load(
    _KnmiTileImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      // Fast path: if the circuit breaker is already open, skip the queue
      if (apiClient.isBlocked) {
        return _transparent();
      }

      final result = await apiClient.get(
        Uri.parse(key.url),
        headers: key.headers,
      );

      return switch (result) {
        KnmiSuccess s when s.response.bodyBytes.isNotEmpty =>
          decode(await ui.ImmutableBuffer.fromUint8List(s.response.bodyBytes)),
        KnmiQuotaExceeded _ => _transparent(),
        KnmiSuccess _ => _transparent(), // empty body
        KnmiError e => throw Exception(
            'Failed to load tile: ${key.url} (Status: ${e.statusCode})',
          ),
      };
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      chunkEvents.close();
    }
  }

  /// Returns a 1×1 fully-transparent codec using Flutter's rendering API.
  /// Avoids hardcoded PNG bytes — [0, 0, 0, 0] is one transparent RGBA pixel.
  Future<ui.Codec> _transparent() async {
    final pixels = Uint8List.fromList([0, 0, 0, 0]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    return ui.ImageDescriptor.raw(
      buffer,
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    ).instantiateCodec();
  }

  @override
  bool operator ==(Object other) =>
      other is _KnmiTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
