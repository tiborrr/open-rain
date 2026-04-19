import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'knmi_api_client.dart';
import 'knmi_raster_tile_cache.dart';

/// A TileProvider that routes all network requests through [KnmiApiClient].
///
/// When the circuit breaker is open (quota exceeded), tiles are silently
/// replaced with a transparent image — no exceptions, no log spam.
///
/// Successful tile bytes are kept in [KnmiRasterTileCache] so panning, animation
/// loops, and background dashboard reloads do not re-hit KNMI for the same URL.
/// Call [bumpImageCacheGeneration] on manual refresh so Flutter's [ImageCache]
/// does not keep decoding stale providers for the same URL.
class KnmiTileProvider extends TileProvider {
  final KnmiApiClient apiClient;

  static int _imageCacheGeneration = 0;

  /// Invalidate decoded image entries tied to the previous generation (manual refresh only).
  static void bumpImageCacheGeneration() => _imageCacheGeneration++;

  final int _cacheGeneration;

  KnmiTileProvider({required this.apiClient, Map<String, String>? headers})
      : _cacheGeneration = _imageCacheGeneration,
        super(headers: headers ?? {});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _KnmiTileImage(
      url,
      apiClient: apiClient,
      headers: headers,
      cacheGeneration: _cacheGeneration,
    );
  }
}

class _KnmiTileImage extends ImageProvider<_KnmiTileImage> {
  final String url;
  final KnmiApiClient apiClient;
  final Map<String, String>? headers;
  final int cacheGeneration;

  _KnmiTileImage(
    this.url, {
    required this.apiClient,
    this.headers,
    required this.cacheGeneration,
  });

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

  Future<ui.Codec> _decodeBytes(Uint8List bytes, ImageDecoderCallback decode) async =>
      decode(await ui.ImmutableBuffer.fromUint8List(bytes));

  Future<ui.Codec> _load(
    _KnmiTileImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      final cached = KnmiRasterTileCache.instance.get(key.url);
      if (cached != null && cached.isNotEmpty) {
        return _decodeBytes(cached, decode);
      }

      if (key.apiClient.isBlocked) {
        return _transparent();
      }

      final result = await key.apiClient.get(
        Uri.parse(key.url),
        headers: key.headers,
      );

      return switch (result) {
        KnmiSuccess s when s.response.bodyBytes.isNotEmpty => () {
            final body = s.response.bodyBytes;
            KnmiRasterTileCache.instance.put(key.url, body);
            return _decodeBytes(body, decode);
          }(),
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
      other is _KnmiTileImage &&
      other.url == url &&
      other.cacheGeneration == cacheGeneration;

  @override
  int get hashCode => Object.hash(url, cacheGeneration);
}
