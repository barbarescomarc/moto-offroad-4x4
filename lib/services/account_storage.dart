import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Levée par [AccountStorage.readToken] quand le stockage sécurisé lui-même
/// est en panne — par exemple une entrée restaurée par une sauvegarde
/// Android sans la clé Keystore correspondante, qui fait lever
/// `flutter_secure_storage` (`BadPaddingException`) au lieu de rendre `null`.
///
/// Distinguer cette panne d'une absence de jeton légitime est nécessaire :
/// les deux ne doivent pas mener au même état (voir `AccountProvider.restore`,
/// qui traite l'une comme l'autre en dégradé, mais jamais comme un jeton
/// simplement absent).
class AccountStorageFailure implements Exception {
  const AccountStorageFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'AccountStorageFailure: $cause';
}

/// Conserve le jeton de session hors des préférences : un jeton d'identité
/// dans `shared_preferences` est lisible sur un appareil déverrouillé par la
/// racine, et part dans la sauvegarde automatique Android — il serait
/// restauré sur un autre téléphone.
class AccountStorage {
  AccountStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _kToken = 'account_session_token';

  final FlutterSecureStorage _storage;

  /// Lit le jeton stocké. Lève [AccountStorageFailure] si le stockage
  /// sécurisé lui-même est en panne — ne rend jamais silencieusement `null`
  /// dans ce cas, pour que l'appelant ne confonde pas une panne avec une
  /// absence de jeton légitime.
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _kToken);
    } catch (e) {
      throw AccountStorageFailure(e);
    }
  }

  /// Écrit le jeton, au mieux : un jeton déjà valide en mémoire pour la
  /// session en cours n'a pas de raison d'être perdu si seule sa persistance
  /// échoue — rien à décider différemment côté appelant, donc rien à lever.
  Future<void> writeToken(String token) async {
    try {
      await _storage.write(key: _kToken, value: token);
    } catch (e) {
      debugPrint('AccountStorage.writeToken en échec : $e');
    }
  }

  /// Efface le jeton, au mieux — même logique que [writeToken].
  Future<void> clear() async {
    try {
      await _storage.delete(key: _kToken);
    } catch (e) {
      debugPrint('AccountStorage.clear en échec : $e');
    }
  }
}
