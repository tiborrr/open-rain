import 'dart:async';

import 'package:flutter/foundation.dart';

import 'result.dart';

/// Action signature for [Command0] (no arguments).
typedef CommandAction0<T> = Future<Result<T>> Function();

/// Action signature for [Command1] (single argument).
typedef CommandAction1<T, A> = Future<Result<T>> Function(A);

/// Encapsulates an async view-model action plus its running and result state.
///
/// Mirrors the Flutter architecture command pattern:
/// https://docs.flutter.dev/app-architecture/design-patterns/command
///
/// - Listeners (e.g. `ListenableBuilder`) react to running/error/completed.
/// - Re-entrant execution is blocked while [running] is true (prevents
///   double-tap firing the same action twice).
/// - The most recent [Result] is exposed via [result] until cleared.
abstract class Command<T> extends ChangeNotifier {
  bool _running = false;

  /// Whether the wrapped action is currently in flight.
  bool get running => _running;

  Result<T>? _result;

  /// The most recent [Result], or `null` while running / never executed /
  /// after [clearResult] is called.
  Result<T>? get result => _result;

  /// Whether the most recent run failed.
  bool get error => _result is Err<T>;

  /// Whether the most recent run succeeded.
  bool get completed => _result is Ok<T>;

  /// The successful value of the most recent run, or `null` otherwise.
  T? get value => switch (_result) {
        Ok<T>(value: final v) => v,
        _ => null,
      };

  /// The exception of the most recent failure, or `null` otherwise.
  Exception? get errorObject => switch (_result) {
        Err<T>(error: final e) => e,
        _ => null,
      };

  /// Clears the stored [Result] so listeners can react once and forget.
  void clearResult() {
    _result = null;
    notifyListeners();
  }

  Future<void> _execute(CommandAction0<T> action) async {
    if (_running) return;

    _running = true;
    _result = null;
    notifyListeners();

    try {
      _result = await action();
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// [Command] with no arguments.
final class Command0<T> extends Command<T> {
  Command0(this._action);

  final CommandAction0<T> _action;

  /// Run the action.
  Future<void> execute() => _execute(_action);
}

/// [Command] taking a single argument [A].
final class Command1<T, A> extends Command<T> {
  Command1(this._action);

  final CommandAction1<T, A> _action;

  /// Run the action with [argument].
  Future<void> execute(A argument) => _execute(() => _action(argument));
}
