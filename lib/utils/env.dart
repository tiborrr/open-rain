/// Utility for safely reading compile-time environment variables (`--dart-define`).
abstract final class Env {
  Env._();

  /// Reads a compile-time string environment variable.
  /// Returns `null` if the variable is not defined, empty, or whitespace-only.
  static String? getOptional(String key) {
    final val = String.fromEnvironment(key).trim();
    return val.isEmpty ? null : val;
  }

  /// The KNMI WMS API key configured at build/run time.
  static String? get knmiWmsApiKey => getOptional('KNMI_WMS_API_KEY');
}
