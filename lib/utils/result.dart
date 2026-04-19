/// Sealed [Result] type used across services, repositories and view models.
///
/// Mirrors the Flutter architecture guide pattern:
/// https://docs.flutter.dev/app-architecture/design-patterns/result
///
/// Either [Ok] (value) or [Err] (exception). Forces callers to unwrap, so
/// uncaught exceptions cannot escape an async data path silently.
sealed class Result<T> {
  const Result();

  /// Successful result wrapping [value].
  const factory Result.ok(T value) = Ok<T>._;

  /// Failed result wrapping [error] (must be an [Exception]).
  const factory Result.err(Exception error) = Err<T>._;
}

/// Successful [Result] carrying [value].
final class Ok<T> extends Result<T> {
  const Ok._(this.value);
  final T value;

  @override
  String toString() => 'Result<$T>.ok($value)';
}

/// Failed [Result] carrying [error].
final class Err<T> extends Result<T> {
  const Err._(this.error);
  final Exception error;

  @override
  String toString() => 'Result<$T>.err($error)';
}

/// Convenience helpers for [Result].
extension ResultExt<T> on Result<T> {
  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// Returns the value when [Ok], or null when [Err].
  T? get valueOrNull => switch (this) {
        Ok<T>(value: final v) => v,
        Err<T>() => null,
      };

  /// Returns the error when [Err], or null when [Ok].
  Exception? get errorOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(error: final e) => e,
      };
}
