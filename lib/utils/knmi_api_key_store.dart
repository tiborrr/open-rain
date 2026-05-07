import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user-provided KNMI WMS API key.
abstract final class KnmiApiKeyStore {
  KnmiApiKeyStore._();

  static const String _prefsKey = 'knmi_wms_api_key';

  static Future<String?> load() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_prefsKey);
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static Future<void> save(String? key) async {
    final prefs = SharedPreferencesAsync();
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    await prefs.setString(_prefsKey, trimmed);
  }
}
