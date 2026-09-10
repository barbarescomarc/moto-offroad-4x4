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
  //
  // Round 1 de revue : ce filet était mémorisé par APPAREIL, pas par
  // compte. Sans liaison à une identité, une session révoquée (401) — la
  // seule façon d'atteindre l'écran de connexion sans être passé par
  // [logout], voir `accountRedirect` — pouvait laisser une acceptation
  // utilisable derrière elle, qu'un AUTRE rider se connectant ensuite sur
  // le même téléphone aurait pu récupérer si son propre /me échouait au
  // mauvais moment. La version est donc mémorisée avec l'email du compte
  // qui l'a acceptée, et le filet ne répond que si cette identité
  // correspond à celle du rider concerné — sinon c'est traité comme si rien
  // n'était mémorisé, et l'entrée périmée est effacée à ce moment-là.
  //
  // [restore] n'efface PAS ce filet à la révocation (401), contrairement au
  // jeton — voir le commentaire à cet endroit : l'effacer casserait le cas
  // légitime du même rider qui se reconnecte ensuite avec un /me toujours
  // en échec. La vérification d'identité à la lecture suffit à empêcher
  // qu'un AUTRE rider en profite, ce qui est la seule fuite réelle.
  static const String _kCharteVersionLocale = 'account_charte_version_acceptee';
  static const String _kCharteVersionLocaleCompte = 'account_charte_version_acceptee_compte';

  // ── Acceptation hors ligne de la charte (Critique 3a de la revue finale) ──
  //
  // Le mur de la charte est total (voir accountRedirect) : SOS et le compte
  // à rebours de chute inclus. Avant ce correctif, [acceptCharte] appelait
  // uniquement le serveur — un rider dont le premier lancement (ou un
  // redémarrage) tombe hors couverture, avec un compte déjà créé mais
  // jamais passé par cet écran, se retrouvait mur à mur SANS AUCUNE SORTIE :
  // accepter exigeait le réseau que la panne lui refusait justement. Le
  // texte de la charte est pourtant un asset embarqué, rien dans sa lecture
  // n'exige de réseau — seul l'enregistrement côté serveur en dépend.
  //
  // La version acceptée hors ligne est donc mémorisée ici, taguée avec
  // l'email de ce rider QUAND il est déjà connu à cet instant (il peut ne
  // pas l'être — voir la branche finale de [restore]) — au même titre que
  // le filet ci-dessus. C'est elle qui est relue par [restore] quand le
  // serveur reste muet ET qu'aucune entrée du filet ci-dessus n'existe. Elle
  // est rejouée vers le serveur au prochain contact réussi ([restore],
  // [refreshVerification], [login] — voir
  // [_rejouerAcceptationCharteEnAttente]), et effacée dès que ce rejeu
  // aboutit.
  //
  // Auto-revue avant la fin de ce lot : la première version de ce filet
  // rejouait TOUJOURS l'attente, sans jamais vérifier à qui elle
  // appartenait. Séquence qui en résultait — la même faille que le round 1
  // du filet ci-dessus, rouverte sous une forme neuve : le rider A accepte
  // hors ligne AVANT que son email ne soit jamais résolu par ce processus
  // (email inconnu, donc entrée non taguée) ; sa session est révoquée sans
  // jamais passer par [logout] (qui efface l'attente) ; le rider B se
  // connecte AVEC SUCCÈS sur ce même appareil — [login] rejouait alors
  // l'attente de A au nom de B, sans le moindre lien vérifié entre les
  // deux. D'où la distinction ci-dessous entre [restore]/
  // [refreshVerification] (continuité du MÊME jeton depuis le début : aucun
  // risque qu'un AUTRE rider en profite) et [login] (une identité FRAÎCHE,
  // affirmée par des identifiants tapés, potentiellement différente de
  // celle qui a posé l'attente) — seul ce dernier exige désormais une
  // entrée taguée et correspondante avant de rejouer quoi que ce soit.
  static const String _kCharteVersionEnAttente = 'account_charte_version_en_attente';
  static const String _kCharteVersionEnAttenteCompte = 'account_charte_version_en_attente_compte';

  /// Normalise une adresse pour comparaison — insensible à la casse et aux
  /// espaces superflus, pour qu'une même adresse saisie différemment (casse
  /// du clavier, copier-coller) ne se voie pas refuser le filet à tort.
  String _normaliserEmail(String email) => email.trim().toLowerCase();

  /// Lit la version mémorisée. [pourEmail] identifie le rider concerné
  /// quand elle est connue (voir [login]) : une entrée qui appartient à un
  /// autre compte est alors traitée comme absente, et effacée au passage —
  /// elle ne doit plus jamais répondre à personne. Quand [pourEmail] est
  /// `null` (voir [restore], appelée avant tout /me réussi dans cette
  /// instance, donc sans identité à vérifier), l'entrée est rendue telle
  /// quelle : aucune fuite inter-compte n'est possible à cet endroit
  /// puisque la seule bascule de compte sans [logout] explicite (une
  /// session révoquée) efface déjà ce filet à la source.
  ///
  /// Dégrade en `null` si le stockage local lui-même est en panne — une
  /// telle panne ne doit jamais faire planter [restore] ni [login], au
  /// même titre qu'une absence de réseau (voir leur documentation).
  Future<String?> _charteVersionLocale({String? pourEmail}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final version = prefs.getString(_kCharteVersionLocale);
      if (version == null) return null;
      if (pourEmail != null) {
        final compte = prefs.getString(_kCharteVersionLocaleCompte);
        if (compte == null || compte != _normaliserEmail(pourEmail)) {
          await _effacerCharteVersionLocale();
          return null;
        }
      }
      return version;
    } catch (e) {
      debugPrint('AccountProvider._charteVersionLocale en echec : $e');
      return null;
    }
  }

  Future<void> _memoriserCharteVersionLocale(String version, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCharteVersionLocale, version);
      await prefs.setString(_kCharteVersionLocaleCompte, _normaliserEmail(email));
    } catch (e) {
      debugPrint('AccountProvider._memoriserCharteVersionLocale en echec : $e');
    }
  }

  /// Synchronise le filet avec une réponse SERVEUR *définitive* pour ce
  /// compte — /me ayant réellement répondu, ou une inscription/connexion
  /// qui vient d'aboutir. `null` n'y est pas une absence d'information :
  /// c'est au contraire la réponse la plus sûre qui soit (« ce compte n'a
  /// jamais accepté »), et efface donc une éventuelle entrée périmée plutôt
  /// que de la laisser en place.
  ///
  /// Round 2 de revue (Tâche 23C) : sans ceci, une deuxième fuite en deux
  /// temps restait ouverte malgré la liaison à l'identité du round 1 — le
  /// rider A accepte (entrée stockée sous son email) ; sa session est
  /// révoquée ; le rider B se connecte AVEC SUCCÈS et /me confirme qu'il
  /// n'a jamais accepté (`version == null`) — comme chaque site d'écriture
  /// ne réagissait qu'à une version non nulle, l'entrée de A restait
  /// intacte, inutilisée mais présente ; puis un redémarrage à froid de B,
  /// avec /me en échec cette fois pour une simple panne réseau, faisait
  /// retomber le filet — désormais aveugle à l'identité par construction
  /// (voir [restore]) — sur cette entrée qui n'était jamais la sienne.
  /// L'invariant qui rend ce filet aveugle sûr redevient vrai une fois que
  /// CHAQUE site qui apprend la réponse du serveur synchronise avec elle,
  /// y compris son silence : la seule entrée qui peut exister appartient
  /// alors toujours au dernier compte qui a réellement parlé au serveur.
  Future<void> _synchroniserCharteVersionLocale(String? version, String email) async {
    if (version != null) {
      await _memoriserCharteVersionLocale(version, email);
    } else {
      await _effacerCharteVersionLocale();
    }
  }

  /// Efface la version locale — à l'image de [AccountStorage.clear] pour le
  /// jeton : un téléphone remis à un autre rider ne doit hériter d'aucune
  /// acceptation précédente.
  Future<void> _effacerCharteVersionLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCharteVersionLocale);
      await prefs.remove(_kCharteVersionLocaleCompte);
    } catch (e) {
      debugPrint('AccountProvider._effacerCharteVersionLocale en echec : $e');
    }
  }

  /// Re-clé le filet local sur une nouvelle adresse — Critique 3c de la
  /// revue finale : sans ce correctif, [changeEmail] laissait l'entrée
  /// gardée par l'ANCIENNE adresse. Un rider qui change d'email puis
  /// redémarre hors couverture avec la nouvelle adresse ne se reconnaissait
  /// plus lui-même (`_charteVersionLocale(pourEmail: ...)` refuse une
  /// entrée qui ne correspond pas), et se retrouvait remuré pour avoir
  /// simplement changé d'adresse. Ne re-clé que si l'entrée appartenait
  /// bien à [ancienEmail] : un compte qui n'avait jamais accepté localement
  /// n'a rien à re-clé, et une entrée laissée par un AUTRE rider sur ce
  /// même appareil (voir la note round 1 plus haut) ne doit jamais être
  /// récupérée par ce changement d'email.
  Future<void> _reCleCharteVersionLocale(String ancienEmail, String nouvelEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final compte = prefs.getString(_kCharteVersionLocaleCompte);
      if (compte == null || compte != _normaliserEmail(ancienEmail)) return;
      await prefs.setString(_kCharteVersionLocaleCompte, _normaliserEmail(nouvelEmail));
    } catch (e) {
      debugPrint('AccountProvider._reCleCharteVersionLocale en echec : $e');
    }
  }

  Future<String?> _charteEnAttente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCharteVersionEnAttente);
    } catch (e) {
      debugPrint('AccountProvider._charteEnAttente en echec : $e');
      return null;
    }
  }

  /// `null` si l'identité du rider n'était pas encore connue au moment de
  /// l'acceptation hors ligne — voir [_rejouerAcceptationCharteEnAttente]
  /// pour ce que cette absence de tag change à la manière dont l'entrée est
  /// (ou non) rejouée.
  Future<String?> _charteEnAttenteCompte() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCharteVersionEnAttenteCompte);
    } catch (e) {
      debugPrint('AccountProvider._charteEnAttenteCompte en echec : $e');
      return null;
    }
  }

  Future<void> _memoriserCharteEnAttente(String version, {String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCharteVersionEnAttente, version);
      if (email != null) {
        await prefs.setString(_kCharteVersionEnAttenteCompte, _normaliserEmail(email));
      } else {
        await prefs.remove(_kCharteVersionEnAttenteCompte);
      }
    } catch (e) {
      debugPrint('AccountProvider._memoriserCharteEnAttente en echec : $e');
    }
  }

  Future<void> _effacerCharteEnAttente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCharteVersionEnAttente);
      await prefs.remove(_kCharteVersionEnAttenteCompte);
    } catch (e) {
      debugPrint('AccountProvider._effacerCharteEnAttente en echec : $e');
    }
  }

  /// Pousse vers le serveur une acceptation faite hors ligne (voir
  /// [acceptCharte]), au premier contact réussi qui suit — [restore],
  /// [refreshVerification] et [login] appellent tous ceci juste après un
  /// `/me` qui aboutit. Ne fait rien si rien n'est en attente, ou sans
  /// jeton. Un échec (le serveur répond de nouveau muet entre-temps) laisse
  /// l'entrée en place pour une prochaine tentative — [_charteVersion]
  /// reste alors sur la valeur déjà acceptée localement, jamais régressée
  /// vers une réponse serveur plus ancienne (voir les appelants).
  ///
  /// [exigerIdentiteConnue] : voir la note d'auto-revue sur
  /// [_kCharteVersionEnAttente]. `true` depuis [login] uniquement — une
  /// entrée non taguée (identité inconnue au moment de l'acceptation) y est
  /// alors effacée plutôt que rejouée à l'aveugle, faute de pouvoir
  /// vérifier qu'elle appartient au rider qui vient de se connecter.
  Future<void> _rejouerAcceptationCharteEnAttente({bool exigerIdentiteConnue = false}) async {
    if (_token == null) return;
    final enAttente = await _charteEnAttente();
    if (enAttente == null) return;
    final compte = await _charteEnAttenteCompte();
    if (compte != null) {
      if (_email == null || _normaliserEmail(_email!) != compte) {
        // Taguée pour un AUTRE rider (ou une identité pas encore confirmée
        // ici) : jamais rejouée, et effacée — elle ne deviendra jamais
        // utilisable, la garder ne ferait que traîner un risque de fuite.
        await _effacerCharteEnAttente();
        return;
      }
    } else if (exigerIdentiteConnue) {
      await _effacerCharteEnAttente();
      return;
    }
    final res = await _api.acceptCharte(token: _token!, version: enAttente);
    if (!res.ok) return;
    await _effacerCharteEnAttente();
    _charteVersion = enAttente;
    if (_email != null) await _memoriserCharteVersionLocale(enAttente, _email!);
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
      await _synchroniserCharteVersionLocale(_charteVersion, profil.value!.email);
      // Critique 3a : un contact serveur réussi est un point de rejeu pour
      // une acceptation faite hors ligne — voir
      // _rejouerAcceptationCharteEnAttente. Appelé APRÈS avoir posé la
      // valeur du serveur ci-dessus : s'il y a quelque chose en attente, il
      // la fait prévaloir ; sinon il ne touche à rien.
      await _rejouerAcceptationCharteEnAttente();
      // Critique 2 de la revue finale : ce rejeu est au mieux — le POST peut
      // échouer alors même que le /me ci-dessus vient de réussir (serveur
      // partiellement en panne, creux réseau entre les deux appels).
      // _charteVersion restait alors sur le `null` du serveur, et remurait
      // au lancement suivant un rider qui avait pourtant déjà accepté hors
      // ligne sur cet appareil — exactement la régression que la
      // documentation de [_rejouerAcceptationCharteEnAttente] promet à ses
      // appelants de ne jamais laisser passer. `??=` : une réponse du
      // serveur qui dit quelque chose garde la priorité.
      _charteVersion ??= await _charteEnAttente();
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
      // Round 1 de revue (Tâche 23C) : le filet local n'est délibérément
      // PAS effacé ici, contrairement au jeton. sessionARenouveler reste,
      // avec deconnecte, le seul statut qui laisse /connexion atteignable
      // sans [logout] explicite — donc le seul moyen pour un AUTRE rider de
      // s'authentifier sur cet appareil après une révocation. Mais cette
      // acceptation locale est maintenant liée à l'email du rider qui l'a
      // acceptée (voir `_charteVersionLocale`) : un autre rider qui se
      // connecte ensuite avec un email différent ne peut jamais la
      // récupérer, même si son propre /me échoue au mauvais moment — la
      // vérification d'identité au moment de la lecture suffit à fermer la
      // faille. L'effacer ici casserait au contraire le cas légitime : LE
      // MÊME rider qui se reconnecte après cette même révocation, avec /me
      // qui échoue encore, doit retrouver sa propre acceptation plutôt que
      // de retomber sur CharteScreen pour rien.
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
    // Critique 3a : une acceptation faite hors ligne (voir [acceptCharte])
    // doit survivre à un redémarrage qui reste hors couverture — y compris
    // quand cette instance n'a encore jamais résolu l'email du rider,
    // auquel cas le filet ci-dessus (gardé par identité) ne répond rien.
    // Sans ce second repli, un rider qui aurait déjà accepté hors ligne se
    // retrouverait remuré de nouveau au moindre redémarrage tant que le
    // réseau ne revient pas — exactement le défaut que 3a corrige.
    _charteVersion ??= await _charteEnAttente();
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
    await _synchroniserCharteVersionLocale(_charteVersion, email);
    await _storage.writeToken(_token!);
    _set(res.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
    return true;
  }

  /// Critique 1 de la revue finale : [_apply] pose un jeton et un email
  /// NEUFS sans toucher à une acceptation hors ligne éventuellement en
  /// attente sur cet appareil (voir _kCharteVersionEnAttente). L'entrée
  /// laissée par un rider A survivait donc à l'inscription d'un rider B sur
  /// ce même téléphone — la révocation du jeton de A y mène sans jamais
  /// passer par [logout], qui l'effacerait : `sessionARenouveler` laisse
  /// /connexion atteignable, et l'écran de connexion propose /inscription.
  /// Le premier sondage de [refreshVerification] depuis l'écran de
  /// vérification de B (toutes les 5 s) rejouait alors l'attente de A sous
  /// le jeton de B, avec le rejeu aveugle par défaut. Aujourd'hui B a coché
  /// la même version, transmise ci-dessous, et le dégât se limite à un POST
  /// en double ; le jour où deux versions coexistent, le 1.0 de A écraserait
  /// le 1.1 que B vient de cocher — B remuré, et son acceptation falsifiée
  /// dans le registre du serveur.
  ///
  /// Une inscription qui aboutit crée un compte NEUF : une acceptation en
  /// attente ne peut donc venir que d'un autre compte, jamais du sien. Elle
  /// est effacée, jamais rejouée. Effacée ici plutôt que dans [_apply], que
  /// [login] partage : là, la même attente doit au contraire rester
  /// rejouable pour LE MÊME rider qui se reconnecte (voir [login] et
  /// [_rejouerAcceptationCharteEnAttente]).
  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
    String? charteVersion,
  }) async {
    final ok = await _apply(
      await _api.register(email: email, password: password, displayName: displayName, charteVersion: charteVersion),
      email,
      charteVersion: charteVersion,
    );
    if (ok) await _effacerCharteEnAttente();
    return ok;
  }

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
    final charteVersion = res.ok ? await _charteVersionDepuisLeServeur(res.value!.token, email) : null;
    final ok = await _apply(res, email, charteVersion: charteVersion);
    // Critique 3a : la connexion est elle aussi un contact serveur réussi,
    // donc un point de rejeu pour une acceptation faite hors ligne sur cet
    // appareil avant que ce rider ne se reconnecte — voir
    // _rejouerAcceptationCharteEnAttente. `exigerIdentiteConnue: true` :
    // [email] est une identité fraîchement affirmée par des identifiants
    // tapés, potentiellement un AUTRE rider que celui qui a posé l'attente
    // (voir la note d'auto-revue sur _kCharteVersionEnAttente).
    if (ok) await _rejouerAcceptationCharteEnAttente(exigerIdentiteConnue: true);
    return ok;
  }

  /// Seul /me fait foi pour la charte du pilote une fois le jeton en main.
  /// Un échec (réseau, serveur) ne doit pas casser une connexion par
  /// ailleurs réussie — même règle de robustesse que le reste de cette
  /// classe. Depuis la Tâche 23C, un échec ne rend plus `null` : il retombe
  /// sur la dernière version vue localement pour CE compte (voir
  /// `_charteVersionLocale`), pour qu'un rider déjà accepté par le passé ne
  /// soit jamais remuré par une simple panne réseau à la connexion — et
  /// qu'un AUTRE rider se connectant sur le même appareil n'hérite jamais
  /// de l'acceptation d'un compte qui n'est pas le sien (round 1 de revue).
  /// Un succès, lui, synchronise toujours le filet — `null` compris (round
  /// 2, voir `_synchroniserCharteVersionLocale`) : sinon une connexion
  /// réussie qui confirme qu'un rider n'a jamais accepté laisserait
  /// l'entrée d'un compte précédent en place sur cet appareil.
  Future<String?> _charteVersionDepuisLeServeur(String token, String email) async {
    final profil = await _api.me(token: token);
    if (!profil.ok) {
      // Même filet qu'au démarrage (voir [restore]), mais identifié cette
      // fois : [email] est celle du rider qui se connecte réellement, pas
      // une identité supposée.
      return _charteVersionLocale(pourEmail: email);
    }
    final version = profil.value!.charteVersion;
    await _synchroniserCharteVersionLocale(version, profil.value!.email);
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
    await _synchroniserCharteVersionLocale(_charteVersion, profil.value!.email);
    // Critique 3a : voir la même remarque dans restore().
    await _rejouerAcceptationCharteEnAttente();
    // Même repli, à la même place et pour la même raison que dans
    // [restore] (Critique 2) : le rejeu ci-dessus est au mieux — le POST
    // peut échouer alors que le /me juste avant vient de réussir. Sans ce
    // `??=`, _charteVersion restait sur le `null` du serveur et le _set()
    // ci-dessous remurait, pour rien, un rider qui avait pourtant déjà
    // accepté hors ligne. Une réponse du serveur qui dit quelque chose
    // garde la priorité.
    _charteVersion ??= await _charteEnAttente();
    if (profil.value!.verified) {
      _set(AccountStatus.connecte);
      return true;
    }
    _set(AccountStatus.nonVerifie);
    return false;
  }

  /// Le refus DE FOND est le seul échec qui laisse le mur de la charte en
  /// place : le serveur a réellement lu la version envoyée et la rejette
  /// — un 400, que
  /// `AccountApiClient._errorFor` nomme `adresseInvalide` ou
  /// `motDePasseTropCourt` selon le corps de la réponse, faute d'un code
  /// propre à cette route. Là, et là seulement, réessayer a un sens : c'est
  /// la version elle-même qu'il faut corriger, la retenir localement ne
  /// ferait qu'enregistrer une acceptation que le serveur a explicitement
  /// refusée.
  ///
  /// Critique 2 de la revue finale : [acceptCharte] ne traitait comme repli
  /// local que [AccountError.reseau], alors que `_errorFor` traduit TOUT 5xx
  /// en [AccountError.inconnue] et un 429 en [AccountError.tropDeTentatives].
  /// Un serveur qui répondait 500 (ou saturé) murait donc, sans SOS ni
  /// détection de chute, chaque rider n'ayant pas encore accepté : « réessaie
  /// » à l'écran, et un redémarrage qui rejouait la même impasse à
  /// l'identique aussi longtemps que durait la panne. [restore] range
  /// pourtant déjà, elle, « 5xx, timeout » avec « réseau coupé ».
  ///
  /// Suivi de cette même revue : ces deux erreurs ne naissent plus d'un 400
  /// quelconque, mais d'un 400 que `AccountApiClient` sait attribuer à notre
  /// API (voir `_vientDeNotreApi`). Un 400 de portail captif, de proxy ou de
  /// WAF devient `inconnue` et retombe donc, comme il se doit, sur le repli
  /// local ci-dessous. L'attribution se fait là-bas, où le corps de la
  /// réponse existe encore : ici, l'énumération l'a déjà oublié.
  static bool _estUnRefusDeLaCharte(AccountError? error) =>
      error == AccountError.adresseInvalide || error == AccountError.motDePasseTropCourt;

  /// Enregistre l'acceptation de la charte du pilote et met à jour l'état
  /// local. C'est ce qui fait disparaître `CharteScreen` : `accountRedirect`
  /// réévalue dès la notification déclenchée ici, sans navigation explicite
  /// à faire depuis l'écran.
  ///
  /// Critique 3a de la revue finale : le texte de la charte est un asset
  /// embarqué, rien dans sa lecture n'exige de réseau — seul l'appel
  /// serveur ci-dessous en dépend. Un échec réseau (par opposition à un
  /// refus explicite du serveur) ne bloque donc plus le rider : l'accepta-
  /// tion est retenue localement et rendue au reste de l'application tout
  /// de suite (le mur retombe dès la notification), puis rejouée vers le
  /// serveur au prochain contact réussi — voir
  /// _rejouerAcceptationCharteEnAttente, appelée depuis [restore],
  /// [refreshVerification] et [login].
  ///
  /// Critique 2 de la revue finale : ce repli local ne se limite plus au
  /// seul serveur INJOIGNABLE — voir [_estUnRefusDeLaCharte].
  Future<bool> acceptCharte({String version = LegalDocuments.charteVersion}) async {
    if (_token == null) return false;
    final res = await _api.acceptCharte(token: _token!, version: version);
    _lastError = res.error;
    if (res.ok) {
      _charteVersion = version;
      await _effacerCharteEnAttente();
      // Critique 3b : _email peut être encore `null` ici — typiquement une
      // instance dont le seul restore() a échoué réseau sans jamais avoir
      // vu /me réussir (voir la branche finale de restore()), puis dont le
      // réseau est revenu juste à temps pour cet appel. C'est justement le
      // cas le plus courant, pas marginal : sans résoudre l'identité ici,
      // rien n'était mémorisé, et le prochain démarrage hors ligne
      // remurrait ce même rider. Un seul appel à /me suffit à la résoudre.
      if (_email == null) await _resoudreEmailPourFiletCharte();
      if (_email != null) await _memoriserCharteVersionLocale(version, _email!);
      notifyListeners();
      return true;
    }
    if (!_estUnRefusDeLaCharte(res.error)) {
      // Cette branche EST le succès (Critique 3a, élargie par la Critique 2
      // au serveur debout mais en panne — voir _estUnRefusDeLaCharte) : rien
      // à laisser en erreur pour un appelant qui recevra `true` juste en
      // dessous.
      _lastError = null;
      _charteVersion = version;
      // Taguée avec l'identité déjà connue de cette instance, s'il y en a
      // une — voir la note d'auto-revue sur _kCharteVersionEnAttente pour
      // ce que ce tag change à la manière dont [login] rejoue (ou non)
      // cette entrée ensuite.
      await _memoriserCharteEnAttente(version, email: _email);
      if (_email != null) await _memoriserCharteVersionLocale(version, _email!);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Résout l'identité du rider après une acceptation réussie quand elle
  /// n'était pas encore connue de cette instance (Critique 3b). Best-effort
  /// : un nouvel échec ici (réseau redevenu indisponible entre les deux
  /// appels) laisse simplement _email à `null`, sans rien casser d'autre —
  /// l'acceptation elle-même est déjà actée plus haut.
  Future<void> _resoudreEmailPourFiletCharte() async {
    if (_token == null) return;
    final profil = await _api.me(token: _token!);
    if (profil.ok) _email = profil.value!.email;
  }

  Future<bool> resendVerification() async {
    if (_token == null) return false;
    final res = await _api.resendVerification(token: _token!);
    _lastError = res.error;
    notifyListeners();
    return res.ok;
  }

  /// Critique 3c de la revue finale : le filet local de la charte est gardé
  /// par email (voir `_charteVersionLocale`). Sans re-clé ici, une
  /// acceptation déjà mémorisée restait attachée à l'ANCIENNE adresse — une
  /// prochaine connexion hors ligne avec la nouvelle ne la reconnaissait
  /// plus, et remurrait un rider dont la seule faute était d'avoir changé
  /// d'email.
  Future<bool> changeEmail(String email) async {
    if (_token == null) return false;
    final ancienEmail = _email;
    final res = await _api.changeEmail(token: _token!, email: email);
    _lastError = res.error;
    if (res.ok) {
      _email = email;
      if (ancienEmail != null) await _reCleCharteVersionLocale(ancienEmail, email);
    }
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
    // ne doit hériter d'aucune acceptation de charte précédente (Tâche 23C),
    // ni d'une acceptation faite hors ligne encore en attente de rejeu
    // (Critique 3a) — elle appartient au compte qui vient de se déconnecter.
    await _effacerCharteVersionLocale();
    await _effacerCharteEnAttente();
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
    await _effacerCharteEnAttente();
    _token = null;
    _email = null;
    // Symétrique de logout() (Trouvaille mineure de la revue finale) :
    // sans ceci, un rider qui supprime son compte puis en crée un autre sur
    // le même appareil voyait encore l'ancien prénom, le temps qu'un /me
    // le corrige.
    _displayName = null;
    _charteVersion = null;
    _set(AccountStatus.deconnecte);
    return true;
  }
}
