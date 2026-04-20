import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/utils/cache_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('CacheStore.getOrFetch', () {
    test('calls fetch on cold cache and stores result', () async {
      final store = CacheStore();
      var calls = 0;
      final value = await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        fetch: () async {
          calls++;
          return {'a': 1};
        },
      );
      expect(value, {'a': 1});
      expect(calls, 1);

      final value2 = await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        fetch: () async {
          calls++;
          return {'a': 2};
        },
      );
      expect(value2, {'a': 1}); // served from cache
      expect(calls, 1);
    });

    test('refetches once expired', () async {
      final store = CacheStore();
      await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        fetch: () async => 'first',
      );
      final value = await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        fetch: () async => 'second',
      );
      expect(value, 'second');
    });

    test('returns stale value on fetch error', () async {
      final store = CacheStore();
      await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        fetch: () async => 'ok',
      );

      // Force a re-fetch by writing an expired entry, then have fetch throw.
      await store.write(
        'k',
        'ok',
        DateTime.now().subtract(const Duration(seconds: 1)),
      );

      final value = await store.getOrFetch(
        key: 'k',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        fetch: () async => throw Exception('network down'),
      );
      expect(value, 'ok');
    });

    test('rethrows when there is no stale value', () async {
      final store = CacheStore();
      expect(
        () => store.getOrFetch(
          key: 'cold',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          fetch: () async => throw Exception('boom'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CacheExpiration.alignedNext', () {
    test('returns a strictly future moment', () {
      final exp = CacheExpiration.alignedNext(15, 2);
      expect(exp.isAfter(DateTime.now()), isTrue);
    });
  });
}
