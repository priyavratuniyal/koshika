import 'package:shared_preferences/shared_preferences.dart';

/// Manages the optional Hugging Face API token for downloading gated models.
///
/// The token is persisted via [SharedPreferences] and injected into HTTP
/// requests as a Bearer token by [ModelDownloader].
abstract final class HfTokenService {
  static const _key = 'koshika_hf_token';

  /// Read the stored token. Returns null if not set.
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_key);
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }

  /// Save a new token. Pass null or empty to clear.
  static Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, token.trim());
    }
  }

  /// Whether a token is currently stored.
  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null;
  }
}
