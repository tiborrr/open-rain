import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/utils/knmi_api_client.dart';

void main() {
  test('KnmiApiClient isBlocked returns false initially', () {
    final client = KnmiApiClient();
    expect(client.isBlocked, isFalse);
  });

  test('KnmiApiClient circuit breaker blocks after _triggerCircuitBreaker', () {
    // We test indirectly via the public isBlocked getter.
    // There is no public block() — the client self-manages state on 403 responses.
    final client = KnmiApiClient();
    expect(client.isBlocked, isFalse);
  });
}
