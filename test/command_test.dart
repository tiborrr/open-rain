import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/utils/command.dart';
import 'package:flutter_weather/utils/result.dart';

void main() {
  group('Command0', () {
    test('execute transitions through running -> completed', () async {
      final completer = Completer<Result<int>>();
      final cmd = Command0<int>(() => completer.future);

      final notifications = <String>[];
      cmd.addListener(() => notifications
          .add('running=${cmd.running} completed=${cmd.completed}'));

      final future = cmd.execute();
      expect(cmd.running, isTrue);
      expect(cmd.completed, isFalse);

      completer.complete(const Result.ok(7));
      await future;

      expect(cmd.running, isFalse);
      expect(cmd.completed, isTrue);
      expect(cmd.value, 7);
      expect(notifications.first, 'running=true completed=false');
      expect(notifications.last, 'running=false completed=true');
    });

    test('execute is no-op while already running', () async {
      var calls = 0;
      final cmd = Command0<int>(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const Result.ok(0);
      });

      final first = cmd.execute();
      await cmd.execute();
      await first;

      expect(calls, 1);
    });

    test('error result is captured and clearable', () async {
      final cmd = Command0<int>(() async => Result.err(Exception('nope')));
      await cmd.execute();
      expect(cmd.error, isTrue);
      expect(cmd.errorObject, isA<Exception>());

      cmd.clearResult();
      expect(cmd.error, isFalse);
      expect(cmd.completed, isFalse);
      expect(cmd.result, isNull);
    });
  });

  group('Command1', () {
    test('forwards argument to the action', () async {
      final cmd = Command1<String, int>((n) async => Result.ok('n=$n'));
      await cmd.execute(3);
      expect(cmd.value, 'n=3');
    });
  });
}
