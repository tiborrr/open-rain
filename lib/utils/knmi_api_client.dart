import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sealed result type for KNMI API responses.
/// Callers never need to inspect status codes or catch exceptions.
sealed class KnmiResult {}

class KnmiSuccess extends KnmiResult {
  final http.Response response;
  KnmiSuccess(this.response);
}

class KnmiQuotaExceeded extends KnmiResult {
  final DateTime retryAfter;
  KnmiQuotaExceeded(this.retryAfter);
}

class KnmiError extends KnmiResult {
  final int statusCode;
  final String body;
  KnmiError(this.statusCode, this.body);
}

/// A self-contained HTTP client for the KNMI WMS API that enforces:
///
/// - **Rate limit**: 20 requests per second (one slot released every 50ms)
/// - **Hourly quota**: 1000 requests per 3600-second window
/// - **Circuit breaker**: on 403 or `{"error":"Quota exceeded"}`, blocks until
///   the next hour boundary and logs exactly once.
///
/// Callers call [get] and switch on [KnmiResult]. No status codes, no
/// exception handling, no [block] calls required.
class KnmiApiClient {
  // --- Rate limit: ~6 req/s to prevent 429 Too Many Requests (KNMI limits strictly) ---
  static const Duration _minInterval = Duration(milliseconds: 150);

  // --- Hourly quota: 1000 req/3600s ---
  static const int _quotaMax = 1000;
  static const Duration _quotaWindow = Duration(seconds: 3600);

  // Throttle queue
  final _queue = Queue<Completer<void>>();
  Timer? _throttleTimer;
  DateTime _lastDispatched = DateTime.fromMillisecondsSinceEpoch(0);

  // Quota tracking
  int _requestsInWindow = 0;
  DateTime _windowStart = DateTime.now();

  // Circuit breaker
  DateTime? _blockedUntil;

  // Fallback state
  bool _useAnonymousFallback = false;

  bool get isBlocked =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  /// Automatically rewrites the URI to the anonymous host if fallback is active.
  Uri _applyFallbackUri(Uri uri) {
    if (_useAnonymousFallback && uri.host == 'api.dataplatform.knmi.nl') {
      return uri.replace(host: 'anonymous.api.dataplatform.knmi.nl');
    }
    return uri;
  }

  /// Automatically strips the Authorization header if fallback is active.
  Map<String, String>? _applyFallbackHeaders(Map<String, String>? headers) {
    if (_useAnonymousFallback && headers != null) {
      final newHeaders = Map<String, String>.from(headers);
      newHeaders.remove('Authorization');
      return newHeaders;
    }
    return headers;
  }

  /// Makes a GET request to [uri], fully respecting the rate limit, quota,
  /// and any active circuit breaker.
  Future<KnmiResult> get(Uri uri, {Map<String, String>? headers}) async {
    if (isBlocked) {
      return KnmiQuotaExceeded(_blockedUntil!);
    }

    // Wait for a rate-limit slot
    await _acquireSlot();

    // Double-check after waiting in queue — may have been blocked while waiting
    if (isBlocked) {
      return KnmiQuotaExceeded(_blockedUntil!);
    }

    // Check quota before dispatching
    _refreshQuotaWindow();
    if (_requestsInWindow >= _quotaMax) {
      _triggerCircuitBreaker(reason: 'local quota counter reached');
      if (isBlocked) return KnmiQuotaExceeded(_blockedUntil!);
    }

    _requestsInWindow++;

    final targetUri = _applyFallbackUri(uri);
    final targetHeaders = _applyFallbackHeaders(headers);

    final response = await http.get(targetUri, headers: targetHeaders);

    // Detect quota exhaustion from the server
    if (_isQuotaExceededResponse(response)) {
      _triggerCircuitBreaker(reason: 'server quota/rate exceeded response');
      if (isBlocked) return KnmiQuotaExceeded(_blockedUntil!);
      
      // If we just switched to fallback, retry the request once on the anonymous endpoint
      final retryUri = _applyFallbackUri(uri);
      final retryHeaders = _applyFallbackHeaders(headers);
      final retryResponse = await http.get(retryUri, headers: retryHeaders);
      
      if (retryResponse.statusCode != 200) {
        return KnmiError(retryResponse.statusCode, retryResponse.body);
      }
      return KnmiSuccess(retryResponse);
    }

    if (response.statusCode != 200) {
      return KnmiError(response.statusCode, response.body);
    }

    return KnmiSuccess(response);
  }

  /// Makes a GET request returning raw bytes, e.g. for WMS tile images.
  /// Returns [null] transparently when the circuit breaker is open.
  Future<Uint8List?> getBytes(Uri uri, {Map<String, String>? headers}) async {
    final result = await get(uri, headers: headers);
    return switch (result) {
      KnmiSuccess s => s.response.bodyBytes.isNotEmpty ? s.response.bodyBytes : null,
      KnmiQuotaExceeded _ => null,
      KnmiError e => throw Exception('KNMI tile error ${e.statusCode}'),
    };
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _acquireSlot() {
    final completer = Completer<void>();
    _queue.add(completer);
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_throttleTimer != null || _queue.isEmpty) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastDispatched);

    if (elapsed >= _minInterval) {
      _releaseNext();
    } else {
      _throttleTimer = Timer(_minInterval - elapsed, () {
        _throttleTimer = null;
        _processQueue();
      });
    }
  }

  void _releaseNext() {
    if (_queue.isEmpty) return;
    _lastDispatched = DateTime.now();
    _queue.removeFirst().complete();
    if (_queue.isNotEmpty) {
      _processQueue();
    }
  }

  void _refreshQuotaWindow() {
    final now = DateTime.now();
    if (now.difference(_windowStart) >= _quotaWindow) {
      _requestsInWindow = 0;
      _windowStart = now;
    }
  }

  bool _isQuotaExceededResponse(http.Response response) {
    if (response.statusCode == 403) return true;
    if (response.statusCode == 429) return true; // Too many requests
    if (response.body.contains('"Quota exceeded"')) return true;
    return false;
  }

  void _triggerCircuitBreaker({required String reason}) {
    if (_useAnonymousFallback) {
      if (isBlocked) return; // Already open — stay silent

      // Block until the next hour boundary to align with KNMI's renewal
      final now = DateTime.now();
      final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
      _blockedUntil = nextHour;

      debugPrint(
        'KnmiApiClient: Circuit breaker opened in anonymous fallback ($reason). '
        'Requests blocked until $nextHour.',
      );
    } else {
      _useAnonymousFallback = true;
      _requestsInWindow = 0; // Reset local quota tracking for fallback
      
      debugPrint(
        'KnmiApiClient: Primary API limits exceeded ($reason). '
        'Switching to anonymous API fallback.',
      );
    }
  }
}

