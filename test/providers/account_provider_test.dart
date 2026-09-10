import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/account_storage.dart';
import 'package:moto_offroad/services/legal_documents.dart';

AccountProvider provider(http.Client client) => AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: client),
      storage: AccountStorage(),
    );

/// Simule la panne d'`AccountStorage.readToken` (voir account_storage_test.dart
/// pour la même classe, côté stockage).
class _StockageEnPanneALaLecture extends FlutterSecureStorage {
  const _StockageEnPanneALaLecture();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw Exception('BadPaddingException (jeu de test)');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('sans jeton stocke le rider est deconnecte', () async {
    final p = provider(MockClient((_) async => http.Response('{}', 200)));
    await p.restore();
    expect(p.status, AccountStatus.deconnecte);
    expect(p.lastError, isNull);
  });

  test('serveur injoignable au demarrage, le rider avec jeton reste connecte', () async {
    // Jeton déjà présent, comme au retour d'une sortie précédente.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p.restore();
    expect(p.status, AccountStatus.connecte);
    expect(await AccountStorage().readToken(), 'jeton',
        reason: 'garder le statut sans garder le jeton ne servirait a rien');
  });

  test('jeton revoque au demarrage, une session est a renouveler, pas deconnecte', () async {
    // Le scénario du C1 de la revue finale : réinitialisation de mot de
    // passe côté serveur (donc révocation de toutes les sessions), le rider
    // ne doit PAS se retrouver mur-à-mur comme un premier lancement — voir
    // accountRedirect et le chapitre 6.5 de la spec.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => http.Response('{}', 401)));
    await p.restore();
    expect(p.status, AccountStatus.sessionARenouveler);
    expect(p.status, isNot(AccountStatus.deconnecte));
    expect(await AccountStorage().readToken(), isNull);
    expect(p.lastError, AccountError.identifiants);
  });

  test('une panne du stockage securise a la lecture mene aussi a une session a renouveler', () async {
    // flutter_secure_storage peut lever (BadPaddingException) au lieu de
    // rendre null, par exemple quand une sauvegarde restaure une entrée
    // chiffrée sans la clé Keystore correspondante. restore() ne doit ni
    // rester bloqué en "chargement" pour toujours, ni traiter ça comme un
    // tout premier lancement.
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async => http.Response('{}', 200))),
      storage: AccountStorage(storage: const _StockageEnPanneALaLecture()),
    );
    await p.restore();
    expect(p.status, AccountStatus.sessionARenouveler);
  });

  test('une inscription laisse le rider non verifie', () async {
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201)));
    final ok = await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(ok, isTrue);
    expect(p.status, AccountStatus.nonVerifie);
    expect(await AccountStorage().readToken(), 'jeton');
  });

  test('la verification confirmee fait passer a connecte', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(await p.refreshVerification(), isTrue);
    expect(p.status, AccountStatus.connecte);
  });

  test('une panne reseau ne deconnecte jamais un rider connecte', () async {
    var enPanne = false;
    final p = provider(MockClient((req) async {
      if (enPanne) throw Exception('reseau coupe');
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.status, AccountStatus.connecte);

    enPanne = true;
    await p.refreshVerification();
    expect(p.status, AccountStatus.connecte, reason: 'le reseau absent ne verrouille pas l application');
  });

  test('refreshVerification efface une erreur precedente des qu il reussit', () async {
    var enPanne = false;
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      if (enPanne) throw Exception('reseau coupe');
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': false}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    enPanne = true;
    await p.refreshVerification();
    expect(p.lastError, AccountError.reseau);

    enPanne = false;
    await p.refreshVerification();
    expect(p.lastError, isNull,
        reason: 'un succes doit effacer une erreur precedente, sinon une simple panne '
            'passagere continuerait d etre affichee indefiniment');
  });

  test('resendVerification memorise la cause d un echec (ex: trop de tentatives)', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      return http.Response('{}', 429);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.resendVerification();
    expect(ok, isFalse);
    expect(p.lastError, AccountError.tropDeTentatives);
  });

  test('forgotPassword memorise la cause d un echec reseau', () async {
    final p = provider(MockClient((_) async => throw Exception('reseau coupe')));
    final ok = await p.forgotPassword('rider@example.test');
    expect(ok, isFalse);
    expect(p.lastError, AccountError.reseau);
  });

  // ── Charte du pilote (Tâche 23B) ──────────────────────────────

  test('un compte cree avant la charte a une version nulle apres restore', () async {
    // Le serveur ne renvoie aucun champ charteVersion pour ce compte —
    // exactement le cas d'un rider inscrit avant cette fonctionnalité.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200)));
    await p.restore();
    expect(p.charteVersion, isNull);
  });

  test('une inscription envoyant la charte la memorise localement, meme sans echo du serveur', () async {
    // Le serveur ne renvoie pas charteVersion dans sa reponse : la version
    // locale doit tout de meme etre celle que le rider vient d'envoyer,
    // sans dependre d'un contrat d'echo qu'on ne maitrise pas.
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201)));
    await p.register(email: 'rider@example.test', password: 'dix caracteres', charteVersion: '1.0');
    expect(p.charteVersion, '1.0');
  });

  // Fix round 1, Finding 1 (Critical) : le serveur reel ne renvoie
  // charteVersion ni au login ni au register (fait verifie par le
  // controleur) — seul GET /me le porte. Avant ce correctif, login()
  // passait par _apply sans jamais interroger /me, et _charteVersion
  // retombait donc systematiquement a null apres CHAQUE connexion, meme
  // pour un rider ayant deja accepte la charte depuis longtemps : nouveau
  // telephone, reinstallation, deconnexion/reconnexion, session renouvelee.
  // Ce test est celui qui aurait attrape le defaut : la reponse de login
  // ne porte pas charteVersion (comme le vrai serveur), seul /me le fait.
  test('une connexion sans charteVersion dans sa reponse va chercher la verite sur me, pas de mur pour un rider deja accepte',
      () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        // Reponse conforme au serveur reel : token/verified/displayName
        // seulement, jamais charteVersion.
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 200);
      }
      return http.Response(
          jsonEncode({'email': 'rider@example.test', 'verified': true, 'charteVersion': '1.0'}), 200);
    }));

    final ok = await p.login(email: 'rider@example.test', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(p.charteVersion, '1.0',
        reason: 'sans l appel a /me, une connexion efface toujours la charte deja acceptee (Finding 1)');
  });

  test('une connexion reste connectee meme si l appel a me pour la charte echoue', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 200);
      }
      return http.Response('{}', 500);
    }));

    final ok = await p.login(email: 'rider@example.test', password: 'dix caracteres');

    expect(ok, isTrue, reason: 'un echec du complement /me ne doit pas casser une connexion par ailleurs reussie');
    expect(p.status, AccountStatus.connecte);
    expect(p.charteVersion, isNull);
  });

  test('accepter la charte l enregistre cote serveur et memorise la version', () async {
    final requetes = <Map<String, dynamic>>[];
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      requetes.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.charteVersion, isNull, reason: 'compte enregistre sans charte envoyee par ce test');

    final ok = await p.acceptCharte(version: '1.0');
    expect(ok, isTrue);
    expect(p.charteVersion, '1.0');
    expect(requetes.single['version'], '1.0');
  });

  test('sans jeton, accepter la charte ne fait rien et rend faux', () async {
    final p = provider(MockClient((_) async => http.Response('{}', 200)));
    final ok = await p.acceptCharte(version: '1.0');
    expect(ok, isFalse);
    expect(p.charteVersion, isNull);
  });

  // Critique 2 de la revue finale : un 400 est le SEUL echec qui doive
  // laisser le mur en place — le serveur a lu la version envoyee et la
  // rejette sur le fond. La retenir localement enregistrerait une
  // acceptation qu il a explicitement refusee. Voir plus bas, en fin de
  // fichier, les echecs qui ne murent plus (500, 429).
  test('un refus de fond (400) en acceptant la charte ne modifie pas la version locale', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response(jsonEncode({'error': 'version de charte inconnue'}), 400);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.acceptCharte(version: '1.0');
    expect(ok, isFalse);
    expect(p.charteVersion, isNull);
    expect(p.lastError, AccountError.adresseInvalide);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), isNull,
        reason: 'un refus explicite ne doit rien laisser en attente de rejeu');
  });

  test('la deconnexion efface le jeton et mene a deconnecte, pas a sessionARenouveler', () async {
    // deconnecte reste réservé aux gestes explicites du rider (logout,
    // deleteAccount) — jamais à une révocation côté serveur, voir le test
    // "jeton révoqué au démarrage" ci-dessus qui prouve l'autre branche.
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201)));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.logout();
    expect(p.status, AccountStatus.deconnecte);
    expect(p.status, isNot(AccountStatus.sessionARenouveler));
    expect(await AccountStorage().readToken(), isNull);
  });

  // Trouvaille mineure de la revue finale : deleteAccount() effaçait le
  // jeton, l'email et la charte, mais pas le prénom affiché — contrairement
  // à logout(), qui efface les quatre. Sans ce correctif, un rider qui
  // supprime son compte puis en crée un autre sur le même appareil voyait
  // encore l'ancien prénom, le temps qu'un /me le corrige.
  test('la suppression de compte efface aussi le prenom affiche, comme la deconnexion', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true, 'displayName': 'Marc'}), 201);
      }
      return http.Response('{}', 200); // DELETE /api/account/me
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.displayName, 'Marc');

    final ok = await p.deleteAccount();

    expect(ok, isTrue);
    expect(p.displayName, isNull);
  });

  // ── Filet local de la charte (Tâche 23C) ──────────────────────
  //
  // Correction I7 avait déjà borné l'appel à /me pour que la robustesse du
  // compte ne referme jamais SOS ni la détection de chute. La Tâche 23B a
  // rouvert la même faille sous une forme nouvelle : /me est aussi la seule
  // source de charteVersion, et un échec réseau au démarrage laissait
  // _charteVersion à `null`, remurant un rider ayant pourtant déjà accepté
  // la charte par le passé. Le filet ci-dessous mémorise localement la
  // dernière version confirmée (acceptation ou /me), et ne sert de réponse
  // que quand le serveur, lui, reste muet.

  test('un rider ayant deja accepte la charte reste connecte meme si /me echoue au demarrage', () async {
    // Premier lancement (reseau present) : la charte est acceptee, donc
    // memorisee localement.
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200); // acceptCharte
    }));
    await p1.register(email: 'rider@example.test', password: 'dix caracteres');
    await p1.acceptCharte(version: LegalDocuments.charteVersion);
    expect(p1.charteVersion, LegalDocuments.charteVersion);

    // Redemarrage a froid (nouvelle instance, comme au lancement de
    // l'application) avec un reseau coupe : /me echoue, mais le rider a
    // deja accepte par le passe sur cet appareil — il doit atteindre la
    // carte (et donc SOS/detection de chute), pas le mur de la charte.
    final p2 = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p2.restore();

    expect(p2.status, AccountStatus.connecte);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'une panne reseau au demarrage ne doit pas remurer un rider ayant deja accepte la charte');
  });

  test('un rider qui n a jamais accepte la charte reste mure meme si /me echoue au demarrage', () async {
    // Aucune acceptation, ni cote serveur ni localement : le filet ne doit
    // rien inventer — sinon il deviendrait un moyen de contourner le mur.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p.restore();

    expect(p.status, AccountStatus.connecte,
        reason: 'une panne reseau ne doit pas deconnecter un rider deja muni d un jeton');
    expect(p.charteVersion, isNull,
        reason: 'sans acceptation jamais vue, meme localement, le filet ne doit pas ouvrir un mur qui n existe pas');
  });

  test('une reponse de me plus recente que la version memorisee localement l emporte', () async {
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p1.register(email: 'rider@example.test', password: 'dix caracteres');
    await p1.acceptCharte(version: '1.0');

    // Le serveur repond desormais avec une nouvelle version de charte : le
    // filet local ('1.0') ne doit jamais l emporter sur une reponse reelle
    // du serveur — seul son silence justifie de s en remettre a lui.
    final p2 = provider(MockClient((_) async =>
        http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true, 'charteVersion': '2.0'}), 200)));
    await p2.restore();

    expect(p2.charteVersion, '2.0',
        reason: 'le serveur fait toujours foi quand il repond, meme contre une valeur locale plus ancienne');
  });

  test('accepter la charte la memorise dans les preferences locales, pas seulement en memoire', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.acceptCharte(version: LegalDocuments.charteVersion);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_acceptee'), LegalDocuments.charteVersion,
        reason: 'la version acceptee doit survivre en dehors de la seule instance en memoire');
  });

  test('la deconnexion efface aussi la version de charte memorisee localement', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.acceptCharte(version: LegalDocuments.charteVersion);

    await p.logout();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_acceptee'), isNull,
        reason: 'un telephone remis a un autre rider ne doit pas heriter de l acceptation precedente');
  });

  // ── Filet local lie au compte (Tache 23C, correctif round 1) ───
  //
  // Le filet ci-dessus est memorise par appareil, pas par compte : une
  // session revoquee (401) ne l effacait pas, et le mur pouvait donc
  // s ouvrir pour un AUTRE rider se connectant ensuite sur le meme
  // telephone si son propre /me echouait au mauvais moment — exactement
  // la panne reseau que toute cette fonctionnalite est censee tolerer,
  // donc pas un scenario tire par les cheveux. La version memorisee est
  // desormais liee a l email du compte qui l a accepte, et la revocation
  // de session efface le filet au meme titre que le jeton.

  // Choix delibere, documente ici explicitement : une session revoquee
  // (401) n'efface PAS le filet local, contrairement au jeton. L'effacer
  // casserait le cas legitime (voir le test suivant : le meme rider qui se
  // reconnecte avec /me toujours en echec doit retrouver sa propre
  // acceptation). La verification d'identite a la LECTURE (voir
  // `_charteVersionLocale`) suffit a empecher qu'un autre rider en
  // profite — c'est elle qui ferme la faille, pas un effacement au moment
  // de la revocation.
  test('une session revoquee n efface pas le filet local, seule l identite au moment de la lecture protege',
      () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.acceptCharte(version: LegalDocuments.charteVersion);

    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await AccountStorage().writeToken('jeton');
    await pRevoque.restore();
    expect(pRevoque.status, AccountStatus.sessionARenouveler);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_acceptee'), LegalDocuments.charteVersion,
        reason: 'l entree survit a la revocation : c est le test suivant, pas celui-ci, qui prouve '
            'qu elle reste malgre tout inutilisable par un autre rider');
  });

  test(
      'apres une session revoquee, un autre rider qui se connecte alors que me echoue voit le mur de la charte',
      () async {
    // Rider A accepte la charte sur cet appareil, puis sa session est
    // revoquee (ex. reinitialisation de mot de passe).
    final pA = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton-a', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await pA.register(email: 'rider-a@example.test', password: 'dix caracteres');
    await pA.acceptCharte(version: LegalDocuments.charteVersion);

    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await AccountStorage().writeToken('jeton-a');
    await pRevoque.restore();
    expect(pRevoque.status, AccountStatus.sessionARenouveler);

    // Rider B se connecte avec ses PROPRES identifiants sur ce meme
    // telephone. /me (l appel qui confirmerait la charte de B) echoue —
    // sans liaison au compte, B heriterait de l acceptation de A.
    final pB = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton-b', 'verified': true}), 200);
      }
      throw Exception('reseau coupe'); // /me
    }));
    final ok = await pB.login(email: 'rider-b@example.test', password: 'dix caracteres');

    expect(ok, isTrue, reason: 'la connexion elle-meme reussit, seul le complement /me pour la charte echoue');
    expect(pB.charteVersion, isNull,
        reason: 'l acceptation de A ne doit jamais etre attribuee a B, meme si me echoue pendant la connexion de B');
  });

  test('apres une session revoquee, le meme rider qui se reconnecte alors que me echoue retrouve son acceptation',
      () async {
    final pA = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton-a', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await pA.register(email: 'rider-a@example.test', password: 'dix caracteres');
    await pA.acceptCharte(version: LegalDocuments.charteVersion);

    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await AccountStorage().writeToken('jeton-a');
    await pRevoque.restore();
    expect(pRevoque.status, AccountStatus.sessionARenouveler);

    // Cette fois, c est A lui-meme qui se reconnecte — meme email —
    // pendant que /me echoue encore.
    final pReco = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton-a-bis', 'verified': true}), 200);
      }
      throw Exception('reseau coupe');
    }));
    final ok = await pReco.login(email: 'rider-a@example.test', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(pReco.charteVersion, LegalDocuments.charteVersion,
        reason: 'A retrouve sa propre acceptation malgre l echec de me : ce n est pas un autre rider');
  });

  test('login retombe aussi sur le filet local quand me echoue, pas seulement restore', () async {
    // Couvre le chemin de secours de login() lui-meme, independamment de
    // toute revocation de session : une simple deconnexion/reconnexion
    // classique du meme rider, avec /me qui echoue juste au mauvais
    // moment pendant la connexion.
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p1.register(email: 'rider@example.test', password: 'dix caracteres');
    await p1.acceptCharte(version: LegalDocuments.charteVersion);

    final p2 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton2', 'verified': true}), 200);
      }
      throw Exception('reseau coupe'); // /me
    }));
    final ok = await p2.login(email: 'rider@example.test', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'le filet doit repondre depuis login() lui-meme, pas seulement via restore()');
  });

  // ── Une reponse serveur NULLE doit aussi synchroniser le filet (Tache 23C, correctif round 2) ──
  //
  // Le round 1 liait le filet a une identite, mais seulement a l ecriture
  // d une version NON NULLE : chaque site d ecriture restait muet quand
  // /me confirmait qu un rider n avait jamais accepte. Fuite en deux temps
  // qui en resultait : A accepte (entree stockee sous son email) ; sa
  // session est revoquee ; B se connecte AVEC SUCCES et /me confirme qu il
  // n a jamais accepte (version null) -- rien ne touche a l entree de A,
  // laissee intacte quoique inutilisee ; puis un redemarrage a froid de B,
  // avec /me en echec cette fois pour une simple panne reseau, fait
  // retomber le filet -- aveugle a l identite par construction (restore()
  // n a pas d identite a verifier a ce point) -- sur l entree de A. Un
  // `null` confirme par le serveur est donc desormais traite comme
  // l information la plus sure qui soit : il efface une entree perimee au
  // lieu de la laisser en place.

  test(
      'B se connecte avec succes (me confirme aucune acceptation), puis un redemarrage a froid avec me en echec ne doit pas heriter de l entree de A',
      () async {
    // A accepte la charte : l entree locale est stockee sous son email.
    final pA = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton-a', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await pA.register(email: 'rider-a@example.test', password: 'dix caracteres');
    await pA.acceptCharte(version: LegalDocuments.charteVersion);

    // B se connecte AVEC SUCCES sur ce meme appareil. /me repond
    // reellement, et confirme que B n a jamais accepte (pas de champ
    // charteVersion dans sa reponse).
    final pB = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton-b', 'verified': true}), 200);
      }
      return http.Response(jsonEncode({'email': 'rider-b@example.test', 'verified': true}), 200); // /me
    }));
    final ok = await pB.login(email: 'rider-b@example.test', password: 'dix caracteres');
    expect(ok, isTrue);
    expect(pB.charteVersion, isNull,
        reason: 'B ne doit pas heriter de l acceptation de A juste apres sa propre connexion');

    // Redemarrage a froid pour B : nouvelle instance, meme jeton (deja
    // ecrit par le login precedent), /me echoue cette fois pour une simple
    // panne reseau -- pas une revocation, juste le reseau qui coupe.
    final pBFroid = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await pBFroid.restore();

    expect(pBFroid.status, AccountStatus.connecte);
    expect(pBFroid.charteVersion, isNull,
        reason: 'B n a jamais accepte : le filet aveugle a l identite de restore() ne doit jamais '
            'heriter d une entree laissee par un AUTRE compte (A)');
  });

  test('un email different uniquement par la casse ou des espaces reste le meme rider pour le filet', () async {
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p1.register(email: 'Rider@Example.Test', password: 'dix caracteres');
    await p1.acceptCharte(version: LegalDocuments.charteVersion);

    // Reconnexion avec la meme adresse, mais ecrite differemment (casse,
    // espaces de copier-coller) : /me echoue, le filet doit tout de meme
    // reconnaitre qu il s agit du meme rider.
    final p2 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton2', 'verified': true}), 200);
      }
      throw Exception('reseau coupe'); // /me
    }));
    final ok = await p2.login(email: ' rider@example.test ', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'la casse et les espaces superflus ne doivent pas faire perdre le filet a un rider fidele');
  });

  // ── Acceptation hors ligne de la charte (Critique 3a de la revue finale) ──
  //
  // Le mur de la charte est total, SOS et compte a rebours de chute inclus
  // (voir accountRedirect). Avant ce correctif, acceptCharte() exigeait le
  // reseau : un rider dont le compte existe deja mais qui n a jamais vu cet
  // ecran, et dont le premier lancement (ou un redemarrage) tombe hors
  // couverture, n avait alors aucune sortie — accepter exigeait justement
  // ce que la panne lui refusait.

  test('accepter la charte hors ligne debloque immediatement l acces (Critique 3a)', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      throw Exception('reseau coupe'); // /charte
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.charteVersion, isNull);

    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue, reason: 'une panne reseau ne doit plus empecher d accepter la charte');
    expect(p.charteVersion, LegalDocuments.charteVersion);
  });

  test(
      'une acceptation hors ligne survit a un redemarrage qui reste hors ligne, meme sans email jamais resolu',
      () async {
    // Jeton deja present (compte cree une fois, precedemment, avec reseau),
    // mais CETTE instance n a jamais vu /me reussir : email inconnu d elle.
    await AccountStorage().writeToken('jeton');
    final p1 = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p1.restore();
    expect(p1.status, AccountStatus.connecte);
    expect(p1.charteVersion, isNull);

    final ok = await p1.acceptCharte(version: LegalDocuments.charteVersion);
    expect(ok, isTrue);
    expect(p1.charteVersion, LegalDocuments.charteVersion);

    // Redemarrage : nouvelle instance, toujours hors ligne, email toujours
    // inconnu de ce nouveau processus non plus — le filet garde par
    // identite (_charteVersionLocale) ne peut rien rendre ici, seule
    // l acceptation en attente (sans condition d identite) le peut.
    final p2 = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p2.restore();

    expect(p2.status, AccountStatus.connecte);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'une acceptation faite hors ligne doit survivre a un redemarrage qui reste hors ligne');
  });

  test('une acceptation hors ligne est rejouee au prochain contact reussi, puis l attente est effacee', () async {
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      throw Exception('reseau coupe'); // /charte
    }));
    await p1.register(email: 'rider@example.test', password: 'dix caracteres');
    final ok = await p1.acceptCharte(version: LegalDocuments.charteVersion);
    expect(ok, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion);

    var accepteRejoue = false;
    final p2 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/charte')) {
        accepteRejoue = true;
        return http.Response('{}', 200);
      }
      // /me : le serveur ne connait pas encore l acceptation faite hors
      // ligne par la premiere instance.
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p2.restore();

    expect(accepteRejoue, isTrue,
        reason: 'un contact serveur reussi (ici /me dans restore()) doit rejouer l acceptation en attente');
    expect(p2.charteVersion, LegalDocuments.charteVersion);
    expect(prefs.getString('account_charte_version_en_attente'), isNull,
        reason: 'un rejeu reussi doit effacer l attente, sinon elle serait rejouee indefiniment');
  });

  // ── Résolution de l'email a l'acceptation (Critique 3b) ──────────────
  //
  // account_provider.dart qualifiait ce cas de "marginal" : _email nul au
  // moment d'une acceptation reussie. C'est au contraire le chemin courant
  // : /me echoue au demarrage (email inconnu), le mur de la charte
  // s'affiche, le reseau revient, le rider accepte — c'est CET appel qui
  // reussit alors que _email n'a jamais ete resolu par cette instance.

  test('une acceptation reussie sans email connu le resout via me et memorise sous cette adresse (Critique 3b)',
      () async {
    var enPanne = true; // restore() echoue reseau, /me jamais vu reussir
    final p = provider(MockClient((req) async {
      if (enPanne) throw Exception('reseau coupe');
      if (req.url.path.endsWith('/me')) {
        return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
      }
      return http.Response('{}', 200); // /charte
    }));
    await AccountStorage().writeToken('jeton');
    await p.restore();
    expect(p.status, AccountStatus.connecte);
    expect(p.charteVersion, isNull);

    enPanne = false; // le reseau revient au moment ou le rider accepte
    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue);
    expect(p.charteVersion, LegalDocuments.charteVersion);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_acceptee'), LegalDocuments.charteVersion,
        reason: 'sans resoudre l email au moment de l acceptation, rien n etait memorise localement');
    expect(prefs.getString('account_charte_version_acceptee_compte'), 'rider@example.test');
  });

  // ── Changement d'email et filet local (Critique 3c) ──────────────────

  test('changer d email re-cle le filet local de la charte, au lieu de le laisser attache a l ancienne adresse',
      () async {
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 200);
    }));
    await p1.register(email: 'ancien@example.test', password: 'dix caracteres');
    await p1.acceptCharte(version: LegalDocuments.charteVersion);

    final ok = await p1.changeEmail('nouveau@example.test');
    expect(ok, isTrue);

    // Reconnexion hors ligne avec la NOUVELLE adresse : le filet doit
    // reconnaitre ce rider, pas le remurer pour avoir change d email.
    final p2 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton2', 'verified': true}), 200);
      }
      throw Exception('reseau coupe'); // /me
    }));
    final ok2 = await p2.login(email: 'nouveau@example.test', password: 'dix caracteres');

    expect(ok2, isTrue);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'sans re-cle, changer d email remurrerait ce rider au prochain demarrage hors ligne');
  });

  // ── Auto-revue : identite du rejeu d une acceptation hors ligne ──────
  //
  // La toute premiere version de ce correctif (3a) rejouait l attente sans
  // jamais verifier a qui elle appartenait. Sequence qui en resultait,
  // symetrique du round 1 du filet ci-dessus : A accepte hors ligne AVANT
  // que son email ne soit jamais resolu par ce processus (donc une entree
  // NON tagguee) ; sa session est revoquee sans jamais passer par logout()
  // (qui efface l attente) ; B se connecte AVEC SUCCES sur ce meme appareil
  // -- login() rejouait alors l attente de A au nom de B.

  test(
      'apres une session revoquee, un rider B qui se connecte n herite pas d une acceptation hors ligne non tagguee laissee par A',
      () async {
    // A a deja un jeton stocke mais n a jamais vu /me reussir dans ce
    // processus : exactement le cas fondateur de 3a, email inconnu au
    // moment de l acceptation -- l entree posee ne peut donc pas etre
    // tagguee.
    await AccountStorage().writeToken('jeton-a');
    final pA = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await pA.restore();
    await pA.acceptCharte(version: LegalDocuments.charteVersion);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion);
    expect(prefs.getString('account_charte_version_en_attente_compte'), isNull,
        reason: 'email de A jamais resolu par ce processus : l entree ne peut pas etre tagguee');

    // Revocation (A n a jamais appele logout(), donc l attente survit).
    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await pRevoque.restore();
    expect(pRevoque.status, AccountStatus.sessionARenouveler);

    // B se connecte AVEC SUCCES, avec reseau, sur ce meme appareil.
    var accepteAppele = false;
    final pB = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton-b', 'verified': true}), 200);
      }
      if (req.url.path.endsWith('/charte')) {
        accepteAppele = true;
        return http.Response('{}', 200);
      }
      return http.Response(jsonEncode({'email': 'rider-b@example.test', 'verified': true}), 200); // /me
    }));
    final ok = await pB.login(email: 'rider-b@example.test', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(accepteAppele, isFalse,
        reason: 'une entree non tagguee ne doit jamais etre rejouee au nom d un rider different (B)');
    expect(pB.charteVersion, isNull, reason: 'B ne doit jamais heriter de l acceptation de A');
    expect(prefs.getString('account_charte_version_en_attente'), isNull,
        reason: 'inutilisable desormais, l entree doit etre effacee plutot que laissee trainer');
  });

  test(
      'apres une session revoquee, le meme rider A qui se reconnecte rejoue son acceptation hors ligne tagguee via login',
      () async {
    // Contrôle positif du test ci-dessus : quand l email EST deja connu au
    // moment de l acceptation (cas le plus courant, voir Critique 3b),
    // l entree est tagguee et le rejeu via login() doit continuer de
    // fonctionner pour le MEME rider.
    final pA = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton-a', 'verified': true}), 201);
      }
      throw Exception('reseau coupe'); // /charte
    }));
    await pA.register(email: 'rider-a@example.test', password: 'dix caracteres');
    await pA.acceptCharte(version: LegalDocuments.charteVersion);

    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await AccountStorage().writeToken('jeton-a');
    await pRevoque.restore();

    var accepteAppele = false;
    final pReco = provider(MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        return http.Response(jsonEncode({'token': 'jeton-a-bis', 'verified': true}), 200);
      }
      if (req.url.path.endsWith('/charte')) {
        accepteAppele = true;
        return http.Response('{}', 200);
      }
      return http.Response(jsonEncode({'email': 'rider-a@example.test', 'verified': true}), 200); // /me
    }));
    final ok = await pReco.login(email: 'rider-a@example.test', password: 'dix caracteres');

    expect(ok, isTrue);
    expect(accepteAppele, isTrue, reason: 'une entree tagguee au bon rider doit etre rejouee via login()');
    expect(pReco.charteVersion, LegalDocuments.charteVersion);
  });

  // ── Critique 1 de la revue finale : inscription et attente d autrui ──
  //
  // La fuite fermee pour login() restait ouverte pour son jumeau. _apply()
  // pose un jeton et un email NEUFS sans toucher aux cles de l attente : une
  // acceptation hors ligne non tagguee, laissee par A, survivait donc a
  // l inscription de B, que le premier sondage de refreshVerification()
  // depuis l ecran de verification (toutes les 5 s) rejouait alors sous le
  // jeton de B, avec le rejeu aveugle par defaut. Miroir exact du test
  // login() ci-dessus.

  test(
      'apres une session revoquee, un rider B qui s inscrit n herite pas d une acceptation hors ligne non tagguee laissee par A',
      () async {
    // A a un jeton stocke mais n a jamais vu /me reussir dans ce processus :
    // son email est inconnu, l entree posee ne peut donc pas etre tagguee.
    await AccountStorage().writeToken('jeton-a');
    final pA = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await pA.restore();
    await pA.acceptCharte(version: '0.9'); // version anterieure a la courante

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), '0.9');
    expect(prefs.getString('account_charte_version_en_attente_compte'), isNull,
        reason: 'email de A jamais resolu par ce processus : l entree ne peut pas etre tagguee');

    // Revocation (A n a jamais appele logout(), donc l attente survit), puis
    // /connexion, puis /inscription : le chemin reel jusqu au compte de B.
    final pRevoque = provider(MockClient((_) async => http.Response('{}', 401)));
    await pRevoque.restore();
    expect(pRevoque.status, AccountStatus.sessionARenouveler);

    // B s inscrit AVEC SUCCES, avec reseau, sur ce meme appareil, en cochant
    // la version courante de la charte (case obligatoire de RegisterScreen).
    String? versionRejouee;
    final pB = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton-b', 'verified': false}), 201);
      }
      if (req.url.path.endsWith('/charte')) {
        versionRejouee = (jsonDecode(req.body) as Map<String, dynamic>)['version'];
        return http.Response('{}', 200);
      }
      // /me : le serveur a bien enregistre la version que B vient de cocher,
      // transmise par /register.
      return http.Response(
          jsonEncode({
            'email': 'rider-b@example.test',
            'verified': false,
            'charteVersion': LegalDocuments.charteVersion,
          }),
          200);
    }));
    final ok = await pB.register(
      email: 'rider-b@example.test',
      password: 'dix caracteres',
      charteVersion: LegalDocuments.charteVersion,
    );
    expect(ok, isTrue);
    // L ecran de verification de B sonde le serveur toutes les 5 s : c est
    // CE sondage qui rejouait l attente de A sous le jeton de B.
    await pB.refreshVerification();

    expect(versionRejouee, isNull,
        reason: 'une entree non tagguee ne doit jamais etre rejouee au nom d un rider different (B)');
    expect(pB.charteVersion, LegalDocuments.charteVersion,
        reason: 'B garde la version qu il vient de cocher, jamais celle de A');
    expect(prefs.getString('account_charte_version_en_attente'), isNull,
        reason: 'inutilisable desormais, l entree doit etre effacee plutot que laissee trainer');
  });

  // ── Critique 2 de la revue finale : un serveur DEBOUT mais en panne ──
  //
  // acceptCharte() ne traitait comme repli local que AccountError.reseau,
  // or _errorFor traduit tout 5xx en `inconnue` et un 429 en
  // `tropDeTentatives` : aucun des deux n atteignait cette branche. Un
  // serveur qui repondait 500 murait donc, sans SOS ni detection de chute,
  // chaque rider n ayant pas encore accepte — « reessaie » a l ecran, et un
  // redemarrage qui rejouait la meme impasse a l identique.

  test('un serveur en panne (500) en acceptant la charte ne mure plus le rider', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('{}', 500); // /charte
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue, reason: 'un serveur debout mais en panne n est pas un refus : le mur doit retomber');
    expect(p.charteVersion, LegalDocuments.charteVersion);
    expect(p.lastError, isNull, reason: 'cette branche EST le succes, rien a laisser en erreur');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion,
        reason: 'l acceptation doit etre rejouee des que le serveur se remet');
  });

  test('un serveur sature (429) en acceptant la charte ne mure plus le rider non plus', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response(jsonEncode({'error': 'trop de tentatives'}), 429); // /charte
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue);
    expect(p.charteVersion, LegalDocuments.charteVersion);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion);
  });

  // ── Suivi 1 : un 400 qui ne vient pas de NOTRE API ──────────────────
  //
  // Un 400 etait pris pour un refus de fond sur le seul code de statut. Or
  // un proxy transparent, un filtrage d entreprise ou un portail captif
  // repondent eux aussi 400 a un POST qu ils ne comprennent pas — et le
  // rider hors-piste sur un reseau douteux est justement la population des
  // portails captifs. Il se retrouvait mure, sans SOS ni detection de
  // chute, pour une cause qui n est meme pas la notre. Un 400 ne vaut
  // desormais refus que si le corps est celui de notre API (objet JSON
  // portant `error`) ; voir AccountApiClient._vientDeNotreApi.

  test('un 400 de portail captif (page HTML) en acceptant la charte ne mure pas le rider', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      // La page de connexion du portail, servie a la place de notre reponse.
      return http.Response('<html><body>Connectez-vous au reseau Wi-Fi</body></html>', 400,
          headers: {'content-type': 'text/html'});
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue, reason: 'un 400 qui ne vient pas de notre API n est pas un refus de la charte');
    expect(p.charteVersion, LegalDocuments.charteVersion);
    expect(p.lastError, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion,
        reason: 'l acceptation doit etre rejouee des que le chemin reseau redevient propre');
  });

  test('un 400 a corps vide en acceptant la charte ne mure pas le rider non plus', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response('', 400); // intermediaire muet
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.acceptCharte(version: LegalDocuments.charteVersion);

    expect(ok, isTrue);
    expect(p.charteVersion, LegalDocuments.charteVersion);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion);
  });

  // ── Suivi 2 : refreshVerification() et le rejeu en echec ─────────────

  test('un rejeu en echec pendant refreshVerification ne remure pas un rider ayant accepte hors ligne', () async {
    // Meme forme que restore() (test ci-dessous), meme correctif : /me
    // repond et ne connait pas encore l acceptation, mais le POST de rejeu
    // echoue. Sans repli sur l attente, _charteVersion retombait sur le
    // `null` du serveur et _set(connecte) remurait un rider qui avait
    // pourtant deja accepte hors ligne — mur pour rien, SOS ferme.
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      if (req.url.path.endsWith('/charte')) return http.Response('{}', 500);
      // /me : le compte est verifie, sans acceptation connue du serveur.
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(await p.acceptCharte(version: LegalDocuments.charteVersion), isTrue);

    await p.refreshVerification();

    expect(p.status, AccountStatus.connecte);
    expect(p.charteVersion, LegalDocuments.charteVersion,
        reason: 'un rejeu qui echoue ne doit jamais faire regresser la version deja acceptee localement');
  });

  test('un rejeu en echec apres un /me reussi ne remure pas un rider ayant accepte hors ligne', () async {
    // Le rejeu est au mieux : /me peut reussir alors que le POST /charte,
    // lui, echoue encore (serveur partiellement en panne). Sans repli sur
    // l attente, _charteVersion retombait sur le `null` du serveur — le
    // rider etait remure au lancement suivant, apres avoir pourtant accepte.
    final p1 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      throw Exception('reseau coupe'); // /charte
    }));
    await p1.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(await p1.acceptCharte(version: LegalDocuments.charteVersion), isTrue);

    final p2 = provider(MockClient((req) async {
      if (req.url.path.endsWith('/charte')) return http.Response('{}', 500);
      // /me repond, et ne connait toujours pas d acceptation pour ce compte.
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p2.restore();

    expect(p2.status, AccountStatus.connecte);
    expect(p2.charteVersion, LegalDocuments.charteVersion,
        reason: 'un rejeu qui echoue ne doit jamais faire regresser la version deja acceptee localement');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_charte_version_en_attente'), LegalDocuments.charteVersion,
        reason: 'l attente reste en place tant que le rejeu n a pas abouti');
  });
}
