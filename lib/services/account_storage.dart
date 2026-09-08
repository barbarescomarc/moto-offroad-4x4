import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Conserve le jeton de session hors des préférences : un jeton d'identité
/// dans `shared_preferences` est lisible sur un appareil déverrouillé par la
/// racine, et part dans la sauvegarde automatique Android — il serait
/// restauré sur un autre téléphone.
class AccountStorage {
  AccountStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _kToken = 'account_session_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<void> writeToken(String token) => _storage.write(key: _kToken, value: token);

  Future<void> clear() => _storage.delete(key: _kToken);
}
