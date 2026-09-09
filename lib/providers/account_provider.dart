import 'package:flutter/foundation.dart';
import '../services/account_api_client.dart';
import '../services/account_storage.dart';

/// État d'accès au compte rider, tel que vu par le reste de l'application.
enum AccountStatus { chargement, deconnecte, nonVerifie, connecte }

/// Porte l'état de session du rider pour toute l'application : relie le
/// client HTTP du compte ([AccountApiClient]) et le stockage sécurisé du
/// jeton ([AccountStorage]).
///
/// Règle de robustesse : une panne de réseau ne doit jamais déconnecter un
/// rider déjà authentifié. L'application sert en montagne, en forêt, dans
/// des zones sans réseau, et porte le SOS et la détection de chute — un
/// verrouillage intempestif au milieu de nulle part serait la pire panne
/// possible. Voir [restore] et [refreshVerification] pour où cette règle
/// s'applique concrètement.
class AccountProvider extends ChangeNotifier {
  AccountProvider({AccountApiClient? api, AccountStorage? storage})
      : _api = api ?? AccountApiClient(),
        _storage = storage ?? AccountStorage();

  final AccountApiClient _api;
  final AccountStorage _storage;

  AccountStatus _status = AccountStatus.chargement;
  String? _token;
  String? _email;
  String? _displayName;
  AccountError? _lastError;

  AccountStatus get status => _status;
  String? get email => _email;
  String? get displayName => _displayName;
  AccountError? get lastError => _lastError;
  String? get token => _token;

  void _set(AccountStatus status) {
    _status = status;
    notifyListeners();
  }

  /// Recharge la session au démarrage de l'application depuis le jeton
  /// éventuellement stocké.
  Future<void> restore() async {
    _token = await _storage.readToken();
    if (_token == null) {
      _set(AccountStatus.deconnecte);
      return;
    }
    final profil = await _api.me(token: _token!);
    if (profil.ok) {
      _email = profil.value!.email;
      _displayName = profil.value!.displayName;
      _set(profil.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
      return;
    }
    if (profil.error == AccountError.identifiants) {
      // Jeton réellement révoqué par le serveur (401) : le rider doit se
      // reconnecter, c'est la seule cause qui efface le jeton ici.
      await _storage.clear();
      _token = null;
      _set(AccountStatus.deconnecte);
      return;
    }
    // Serveur injoignable ou en erreur (réseau coupé, 5xx, timeout...) :
    // on garde le jeton et on considère la session valide. Casser la
    // session ici verrouillerait l'application en pleine sortie, sans
    // réseau, au pire moment — voir la documentation de la classe.
    _set(AccountStatus.connecte);
  }

  Future<bool> _apply(AccountResult<AccountSession> res, String email) async {
    _lastError = res.error;
    if (!res.ok) {
      notifyListeners();
      return false;
    }
    _token = res.value!.token;
    _email = email;
    _displayName = res.value!.displayName;
    await _storage.writeToken(_token!);
    _set(res.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
    return true;
  }

  Future<bool> register({required String email, required String password, String? displayName}) async =>
      _apply(await _api.register(email: email, password: password, displayName: displayName), email);

  Future<bool> login({required String email, required String password}) async =>
      _apply(await _api.login(email: email, password: password), email);

  /// Interroge le serveur pour savoir si l'adresse a été vérifiée entre
  /// temps. Si l'appel échoue (réseau absent ou erreur serveur), le statut
  /// ne bouge pas : on note l'erreur et on notifie, un point c'est tout —
  /// c'est la règle de robustesse de cette classe qui l'exige, sans quoi
  /// une simple absence de réseau reverrouillerait un rider déjà connecté.
  Future<bool> refreshVerification() async {
    if (_token == null) return false;
    final profil = await _api.me(token: _token!);
    if (!profil.ok) {
      _lastError = profil.error;
      // Statut inchangé : ni le réseau absent ni une erreur serveur ne
      // doivent dégrader l'état d'un rider déjà connecté.
      notifyListeners();
      return false;
    }
    // Un succès efface une erreur laissée par un appel précédent : sinon un
    // seul creux réseau passager continuerait d'afficher « connexion
    // nécessaire » indéfiniment, alors que le serveur répond normalement.
    _lastError = null;
    _email = profil.value!.email;
    if (profil.value!.verified) {
      _set(AccountStatus.connecte);
      return true;
    }
    _set(AccountStatus.nonVerifie);
    return false;
  }

  Future<bool> resendVerification() async {
    if (_token == null) return false;
    final res = await _api.resendVerification(token: _token!);
    _lastError = res.error;
    notifyListeners();
    return res.ok;
  }

  Future<bool> changeEmail(String email) async {
    if (_token == null) return false;
    final res = await _api.changeEmail(token: _token!, email: email);
    _lastError = res.error;
    if (res.ok) _email = email;
    notifyListeners();
    return res.ok;
  }

  Future<bool> forgotPassword(String email) async {
    final res = await _api.forgotPassword(email: email);
    _lastError = res.error;
    notifyListeners();
    return res.ok;
  }

  Future<void> logout() async {
    if (_token != null) await _api.logout(token: _token!);
    await _storage.clear();
    _token = null;
    _email = null;
    _displayName = null;
    _set(AccountStatus.deconnecte);
  }

  Future<bool> deleteAccount() async {
    if (_token == null) return false;
    final res = await _api.deleteAccount(token: _token!);
    if (!res.ok) {
      _lastError = res.error;
      notifyListeners();
      return false;
    }
    await _storage.clear();
    _token = null;
    _email = null;
    _set(AccountStatus.deconnecte);
    return true;
  }
}
