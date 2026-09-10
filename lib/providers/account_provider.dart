import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/account_api_client.dart';
import '../services/account_storage.dart';
import '../services/legal_documents.dart';

/// État d'accès au compte rider, tel que vu par le reste de l'application.
///
/// [sessionARenouveler] est distinct de [deconnecte] : le jeton local a été
/// révoqué côté serveur (typiquement une réinitialisation de mot de passe,
/// qui ferme toutes les sessions), mais le rider ne s'est pas déconnecté
/// lui-même. `accountRedirect` ne ferme rien pour cet état — carte, GPS,
/// SOS et détection de chute restent accessibles — voir le chapitre 6.5 de
/// la spec et `AccountProvider.restore`. [deconnecte] reste réservé aux
/// gestes explicites du rider ([logout], [deleteAccount]) et au tout premier
/// lancement, sans jeton stocké.
enum AccountStatus { chargement, deconnecte, sessionARenouveler, nonVerifie, connecte }

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
  String? _charteVersion;
  AccountError? _lastError;

  AccountStatus get status => _status;
  String? get email => _email;
  String? get displayName => _displayName;
  AccountError? get lastError => _lastError;
  String? get token => _token;

  /// Version de la charte du pilote acceptée par ce compte, telle que
  /// confirmée par le serveur ou, à défaut d'une réponse (Tâche 23C, voir
  /// `_charteVersionLocale`), telle que vue lors d'un précédent succès sur
  /// cet appareil. `null` seulement si aucune acceptation n'a jamais été
  /// vue, ni par le serveur ni localement. `AccountGate` s'appuie dessus
  /// pour interposer `CharteScreen` entre la vérification et la carte.
  String? get charteVersion => _charteVersion;

  void _set(AccountStatus status) {
    _status = status;
    notifyListeners();
  }

  // ── Filet local de la charte (Tâche 23C) ────────────────────────────
  //
  // /me est la seule source de [_charteVersion] côté serveur — exactement
  // ce que corrige déjà [restore] pour la session elle-même (correctif I7,
  // voir la documentation de la classe) : sans ce filet, un simple creux
  // réseau au démarrage renverrait un rider ayant accepté la charte il y a
  // des mois vers CharteScreen, et donc lui fermerait la carte, le SOS et
  // la détection de chute. La version acceptée est donc aussi mémorisée en
  // clair dans les préférences locales (rien de sensible, contrairement au
  // jeton — voir [AccountStorage]) à chaque confirmation par le serveur, et
  // relue uniquement quand le serveur, lui, reste muet.
  static const String _kCharteVersionLocale = 'account_charte_version_acceptee';

  Future<String?> _charteVersionLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCharteVersionLocale);
  }

  Future<void> _memoriserCharteVersionLocale(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCharteVersionLocale, version);
  }

  /// Efface la version locale — à l'image de [AccountStorage.clear] pour le
  /// jeton : un téléphone remis à un autre rider ne doit hériter d'aucune
  /// acceptation précédente.
  Future<void> _effacerCharteVersionLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCharteVersionLocale);
  }

  /// Recharge la session au démarrage de l'application depuis le jeton
  /// éventuellement stocké.
  ///
  /// Renseigne systématiquement [_lastError] (à `null` s'il n'y a rien à
  /// signaler) : chaque branche doit être identifiable, pour que l'appelant
  /// sache laquelle a été prise et affiche le bon message.
  Future<void> restore() async {
    try {
      _token = await _storage.readToken();
    } on AccountStorageFailure {
      // Le stockage sécurisé lui-même est en panne (ex : BadPaddingException
      // Android après restauration d'une sauvegarde sans la clé Keystore
      // correspondante) : impossible de savoir si un jeton existait. Rester
      // en "chargement" pour toujours fermerait la carte, le GPS, le SOS et
      // la détection de chute aussi sûrement qu'un mur — et un premier
      // lancement neuf ("deconnecte") ne conviendrait pas non plus, un
      // compte existe peut-être. Même issue dégradée qu'un jeton révoqué.
      _token = null;
      _lastError = AccountError.inconnue;
      _set(AccountStatus.sessionARenouveler);
      return;
    }
    if (_token == null) {
      _lastError = null;
      _set(AccountStatus.deconnecte);
      return;
    }
    final profil = await _api.me(token: _token!);
    if (profil.ok) {
      _lastError = null;
      _email = profil.value!.email;
      _displayName = profil.value!.displayName;
      _charteVersion = profil.value!.charteVersion;
      if (_charteVersion != null) await _memoriserCharteVersionLocale(_charteVersion!);
      _set(profil.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
      return;
    }
    if (profil.error == AccountError.identifiants) {
      // Jeton réellement révoqué par le serveur (401), typiquement après
      // une réinitialisation de mot de passe qui ferme toutes les sessions.
      // Le rider doit se reconnecter, mais sans jamais perdre l'accès à la
      // carte, au GPS, au SOS ni à la détection de chute (chapitre 6.5 de
      // la spec) : sessionARenouveler, pas deconnecte, qui fermerait tout.
      _token = null;
      _lastError = AccountError.identifiants;
      _set(AccountStatus.sessionARenouveler);
      // Effacement au mieux : l'état ci-dessus ne dépend pas de sa réussite.
      await _storage.clear();
      return;
    }
    // Serveur injoignable ou en erreur (réseau coupé, 5xx, timeout...) :
    // on garde le jeton et on considère la session valide. Casser la
    // session ici verrouillerait l'application en pleine sortie, sans
    // réseau, au pire moment — voir la documentation de la classe.
    _lastError = profil.error;
    // Filet Tâche 23C : /me muet ne doit pas remurer un rider dont ce même
    // appareil a déjà vu l'acceptation (accepté ici ou confirmé par un
    // /me antérieur). `??=` ne touche à rien si un appel précédent dans
    // cette même instance a déjà résolu _charteVersion.
    _charteVersion ??= await _charteVersionLocale();
    _set(AccountStatus.connecte);
  }

  Future<bool> _apply(AccountResult<AccountSession> res, String email, {String? charteVersion}) async {
    _lastError = res.error;
    if (!res.ok) {
      notifyListeners();
      return false;
    }
    _token = res.value!.token;
    _email = email;
    _displayName = res.value!.displayName;
    // Priorité à la valeur que l'appelant vient d'envoyer (inscription,
    // voir [register]) : elle ne dépend pas de la réponse du serveur, qui
    // pourrait ne pas la renvoyer en écho. À défaut (connexion), on s'en
    // remet à ce que le serveur renvoie, `null` compris pour un compte
    // antérieur à cette fonctionnalité.
    _charteVersion = charteVersion ?? res.value!.charteVersion;
    if (_charteVersion != null) await _memoriserCharteVersionLocale(_charteVersion!);
    await _storage.writeToken(_token!);
    _set(res.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
    return true;
  }

  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
    String? charteVersion,
  }) async =>
      _apply(
        await _api.register(email: email, password: password, displayName: displayName, charteVersion: charteVersion),
        email,
        charteVersion: charteVersion,
      );

  /// Contrairement à l'inscription, la connexion ne connaît pas localement
  /// la charte du pilote déjà acceptée par ce compte — et le serveur ne la
  /// renvoie ni au login ni au register, seuls token/verified/displayName
  /// (fait confirmé après coup, voir le correctif ci-dessous). Sans
  /// l'appel à /me, `_apply` retombait sur `res.value!.charteVersion`, qui
  /// vaut toujours `null` à ce point : chaque connexion effaçait donc la
  /// charte pourtant déjà acceptée depuis longtemps, et renvoyait un rider
  /// fidèle sur `CharteScreen` (Finding 1 du premier tour de revue). /me
  /// est interrogé avant [_apply], donc avant la notification qui fait
  /// réagir le routeur — pas de flash intermédiaire vers la mauvaise
  /// valeur.
  Future<bool> login({required String email, required String password}) async {
    final res = await _api.login(email: email, password: password);
    final charteVersion = res.ok ? await _charteVersionDepuisLeServeur(res.value!.token) : null;
    return _apply(res, email, charteVersion: charteVersion);
  }

  /// Seul /me fait foi pour la charte du pilote une fois le jeton en main.
  /// Un échec (réseau, serveur) ne doit pas casser une connexion par
  /// ailleurs réussie — même règle de robustesse que le reste de cette
  /// classe. Depuis la Tâche 23C, un échec ne rend plus `null` : il retombe
  /// sur la dernière version vue localement (voir `_charteVersionLocale`),
  /// pour qu'un rider déjà accepté par le passé ne soit jamais remuré par
  /// une simple panne réseau à la connexion.
  Future<String?> _charteVersionDepuisLeServeur(String token) async {
    final profil = await _api.me(token: token);
    if (!profil.ok) {
      // Même filet qu'au démarrage (voir [restore]) : une panne de /me
      // pendant la connexion ne doit pas remurer un rider dont cet
      // appareil a déjà vu l'acceptation.
      return _charteVersionLocale();
    }
    final version = profil.value!.charteVersion;
    if (version != null) await _memoriserCharteVersionLocale(version);
    return version;
  }

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
    _charteVersion = profil.value!.charteVersion;
    if (_charteVersion != null) await _memoriserCharteVersionLocale(_charteVersion!);
    if (profil.value!.verified) {
      _set(AccountStatus.connecte);
      return true;
    }
    _set(AccountStatus.nonVerifie);
    return false;
  }

  /// Enregistre l'acceptation de la charte du pilote et met à jour l'état
  /// local. C'est ce qui fait disparaître `CharteScreen` : `accountRedirect`
  /// réévalue dès la notification déclenchée ici, sans navigation explicite
  /// à faire depuis l'écran.
  Future<bool> acceptCharte({String version = LegalDocuments.charteVersion}) async {
    if (_token == null) return false;
    final res = await _api.acceptCharte(token: _token!, version: version);
    _lastError = res.error;
    if (res.ok) {
      _charteVersion = version;
      await _memoriserCharteVersionLocale(version);
    }
    notifyListeners();
    return res.ok;
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
    // Même geste que pour le jeton : un téléphone remis à un autre rider
    // ne doit hériter d'aucune acceptation de charte précédente (Tâche 23C).
    await _effacerCharteVersionLocale();
    _token = null;
    _email = null;
    _displayName = null;
    _charteVersion = null;
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
    await _effacerCharteVersionLocale();
    _token = null;
    _email = null;
    _charteVersion = null;
    _set(AccountStatus.deconnecte);
    return true;
  }
}
