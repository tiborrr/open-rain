import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/utils/result.dart';

void main() {
  group('Result', () {
    test('Ok carries the value and reports isOk', () {
      const result = Result<int>.ok(42);
      expect(result, isA<Ok<int>>());
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.errorOrNull, isNull);
    });

    test('Err carries the exception and reports isErr', () {
      final e = Exception('boom');
      final result = Result<int>.err(e);
      expect(result, isA<Err<int>>());
      expect(result.isErr, isTrue);
      expect(result.isOk, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, e);
    });

    test('switch on sealed cases compiles exhaustively', () {
      Result<String> result = const Result.ok('hi');
      final upper = switch (result) {
        Ok<String>(value: final v) => v.toUpperCase(),
        Err<String>() => '!',
      };
      expect(upper, 'HI');

      result = Result<String>.err(Exception('x'));
      final fallback = switch (result) {
        Ok<String>(value: final v) => v,
        Err<String>() => 'fallback',
      };
      expect(fallback, 'fallback');
    });
  });
}
