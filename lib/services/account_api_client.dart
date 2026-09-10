import 'dart:convert';
import 'package:http/http.dart' as http;

/// Jeton de session renvoyé par le serveur à l'inscription ou à la connexion.
///
/// [charteVersion] est la version de la charte du pilote enregistrée côté
/// serveur pour ce compte (`null` pour un compte qui ne l'a jamais acceptée
/// — voir `AccountGate`). Le serveur la renvoie ici comme dans [AccountProfile] :
/// à l'inscription, elle reflète ce que `RegisterScreen` vient d'envoyer ;
/// à la connexion, elle reflète ce qui était déjà enregistré, `null` compris
/// pour un compte créé avant cette fonctionnalité.
class AccountSession {
  final String token;
  final bool verified;
  final String? displayName;
  final String? charteVersion;
  const AccountSession({
    required this.token,
    required this.verified,
    this.displayName,
    this.charteVersion,
  });
}

/// Profil du compte tel que renvoyé par /api/account/me.
class AccountProfile {
  final String email;
  final bool verified;
  final String? displayName;
  final String? charteVersion;
  const AccountProfile({
    required this.email,
    required this.verified,
    this.displayName,
    this.charteVersion,
  });
}

/// Une panne de réseau et un refus du serveur n'appellent pas la même
/// conduite : l'une se réessaie, l'autre se corrige. L'écran doit pouvoir
/// les distinguer.
enum AccountError {
  reseau,
  identifiants,
  adresseDejaPrise,
  motDePasseTropCourt,
  adresseInvalide,
  tropDeTentatives,
  inconnue,
}

/// Résultat générique d'un appel au compte : soit une valeur, soit une
/// cause d'échec identifiée — jamais les deux, jamais ni l'un ni l'autre.
class AccountResult<T> {
  final T? value;
  final AccountError? error;
  const AccountResult.success(this.value) : error = null;
  const AccountResult.failure(this.error) : value = null;
  bool get ok => error == null;
}

/// Client HTTP des routes de compte du serveur moto-tracker.
///
/// Contrairement à `TrackerApiClient`, qui renvoie `null` en cas d'échec,
/// ce client distingue la cause de l'échec (panne réseau, identifiants
/// invalides, adresse déjà prise, etc.) via [AccountResult.error] : c'est
/// ce qui permet à l'écran d'inscription de choisir entre réessayer et
/// corriger la saisie.
class AccountApiClient {
  AccountApiClient({http.Client? client, String? baseUrl, Duration? timeout})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org',
        _timeout = timeout ?? const Duration(seconds: 5);

  final http.Client _client;
  final String _baseUrl;

  /// Borne de [me] et de [_voidCall] — les deux appels qui conditionnent
  /// l'accès à la carte, donc au SOS. Injectable pour les tests uniquement
  /// — l'application ne passe jamais autre chose que la valeur par défaut.
  final Duration _timeout;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers([String? token]) => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  AccountError _errorFor(int status, String body) {
    switch (status) {
      case 401:
        return AccountError.identifiants;
      case 409:
        return AccountError.adresseDejaPrise;
      case 429:
        return AccountError.tropDeTentatives;
      case 400:
        return body.contains('mot de passe')
            ? AccountError.motDePasseTropCourt
            : AccountError.adresseInvalide;
      default:
        return AccountError.inconnue;
    }
  }

  Future<AccountResult<AccountSession>> _sessionCall(String path, Map<String, dynamic> body) async {
    try {
      final res = await _client.post(_uri(path), headers: _headers(), body: jsonEncode(body));
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return AccountResult.success(AccountSession(
        token: j['token'] as String,
        verified: j['verified'] as bool? ?? false,
        displayName: j['displayName'] as String?,
        charteVersion: j['charteVersion'] as String?,
      ));
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  /// Crée un compte. `displayName` est optionnel côté serveur.
  ///
  /// [charteVersion] : `RegisterScreen` envoie systématiquement la version
  /// courante de la charte du pilote (voir `LegalDocuments.charteVersion`)
  /// — un compte créé avec ce paramètre n'a donc jamais à repasser par
  /// `CharteScreen`.
  Future<AccountResult<AccountSession>> register({
    required String email,
    required String password,
    String? displayName,
    String? charteVersion,
  }) =>
      _sessionCall('/api/account/register', {
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (charteVersion != null) 'charteVersion': charteVersion,
      });

  /// Connecte un compte existant.
  Future<AccountResult<AccountSession>> login({required String email, required String password}) =>
      _sessionCall('/api/account/login', {'email': email, 'password': password});

  /// Récupère le profil du compte connecté.
  ///
  /// Borné à 5 secondes : cet appel gouverne l'écran de chargement affiché
  /// devant la carte le temps que `AccountProvider.restore()` résolve (voir
  /// `_MapGate` dans `lib/app/router.dart`) — sans limite, un réseau dégradé
  /// (portail captif, TCP qui traîne) bloquerait le rider sur cet écran,
  /// donc son accès au SOS, aussi longtemps que la connexion resterait
  /// ouverte. Plus court que les autres appels du dépôt (10-15 s pour la
  /// météo, le guidage, les mises à jour) précisément parce que celui-ci est
  /// seul à conditionner l'accès aux fonctions critiques.
  Future<AccountResult<AccountProfile>> me({required String token}) async {
    try {
      final res = await _client
          .get(_uri('/api/account/me'), headers: _headers(token))
          .timeout(_timeout);
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return AccountResult.success(AccountProfile(
        email: j['email'] as String,
        verified: j['verified'] as bool? ?? false,
        displayName: j['displayName'] as String?,
        charteVersion: j['charteVersion'] as String?,
      ));
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  /// Borné comme [me], et pour exactement la même raison : [acceptCharte]
  /// passe par ici, et c'est désormais la seule sortie du mur de la charte
  /// (voir `AccountProvider.acceptCharte`). Sans borne, le portail captif
  /// décrit au-dessus de [me] — une connexion qui ne répond jamais plutôt
  /// qu'une panne franche — laisserait le rider à attendre indéfiniment
  /// devant ce mur, donc sans SOS ni détection de chute. Un dépassement de
  /// délai retombe dans le `catch` ci-dessous, donc sur
  /// [AccountError.reseau] : la panne de transport qu'il est réellement.
  Future<AccountResult<void>> _voidCall(
    String path, {
    String? token,
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    try {
      final uri = _uri(path);
      final res = method == 'DELETE'
          ? await _client.delete(uri, headers: _headers(token)).timeout(_timeout)
          : await _client.post(uri, headers: _headers(token), body: jsonEncode(body ?? {})).timeout(_timeout);
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      return const AccountResult.success(null);
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  /// Termine la session courante côté serveur.
  Future<AccountResult<void>> logout({required String token}) =>
      _voidCall('/api/account/logout', token: token);

  /// Redemande l'envoi de l'e-mail de vérification.
  Future<AccountResult<void>> resendVerification({required String token}) =>
      _voidCall('/api/account/verify/resend', token: token);

  /// Change l'adresse e-mail du compte connecté.
  Future<AccountResult<void>> changeEmail({required String token, required String email}) =>
      _voidCall('/api/account/email', token: token, body: {'email': email});

  /// Demande un e-mail de réinitialisation de mot de passe. Le serveur
  /// répond 202 systématiquement, que l'adresse soit connue ou non — il ne
  /// faut pas en déduire d'information sur l'existence du compte.
  Future<AccountResult<void>> forgotPassword({required String email}) =>
      _voidCall('/api/account/password/forgot', body: {'email': email});

  /// Supprime le compte connecté.
  Future<AccountResult<void>> deleteAccount({required String token}) =>
      _voidCall('/api/account/me', token: token, method: 'DELETE');

  /// Enregistre l'acceptation de la charte du pilote par le compte connecté
  /// — voir `CharteScreen` et `AccountGate`.
  Future<AccountResult<void>> acceptCharte({required String token, required String version}) =>
      _voidCall('/api/account/charte', token: token, body: {'version': version});
}
