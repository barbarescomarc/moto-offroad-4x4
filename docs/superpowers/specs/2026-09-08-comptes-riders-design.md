# Comptes riders — socle d'identité

Design validé le 8 septembre 2026.

## 1. Contexte

Le besoin exprimé est le partage de traces GPX entre riders, leur conservation
sur le serveur, et une interface web protégée par mot de passe donnant accès
aux adresses e-mail et au nombre de téléchargements. Cette console servira
« par la suite à voir un peu tout », et notamment à valider les points
d'intérêt proposés par les riders avant leur diffusion à toutes les
installations de l'application.

Ces trois demandes butent toutes sur le même manque : **le serveur ne sait pas
qui est qui**. Aujourd'hui une même personne y laisse jusqu'à quatre traces
sans lien entre elles :

| Ce que fait le rider | Ce que le serveur retient |
|---|---|
| Lance un suivi solo | `session.pilot_email` et une clé de propriétaire |
| Rejoint une sortie de groupe | `member.device_key` et un prénom saisi |
| Désigne une personne de confiance | `alert_contact.email` |
| S'abonne à la lettre d'information | `subscriber.email` |

Quatre lignes, quatre tables, aucune passerelle. Une console d'administration
bâtie sur cet état afficherait des listes d'adresses sans jamais pouvoir dire
qu'il s'agit du même bonhomme, ni combien de traces il a publiées.

Ce document définit le socle qui manque : le compte rider.

## 2. Découpage du besoin

Le besoin exprimé recouvre trois sous-systèmes, plus une suite. Chacun aura sa
spécification et son plan d'implémentation.

| Lot | Contenu | Dépend de |
|---|---|---|
| **A — Comptes riders** | Le présent document | — |
| **B — Partage par lien privé** | Table `trace`, lien court, compteur de téléchargements, publication et import depuis l'application | A |
| **C — Back-office** | Administrateurs multiples, journal des actions, tableaux et export CSV, actions RGPD, file de modération générique | A + B |
| **D — Contributions de POI et diffusion** | Le rider pose un point d'intérêt, il part en file d'attente, et une fois validé il descend dans toutes les installations par synchronisation incrémentale | C |

La file de modération du lot C est conçue générique dès sa naissance : une
contribution y suit le cycle *soumis → validé ou refusé → publié*, qu'il
s'agisse d'une trace du catalogue public ou d'un point d'intérêt. Sans cela le
mécanisme serait écrit deux fois.

## 3. Décisions structurantes

1. **Le compte est obligatoire.** À la première ouverture, l'application exige
   une inscription ou une connexion. Ensuite elle garde le rider connecté et
   ne redemande plus rien.
2. **L'e-mail doit être vérifié pour entrer.** L'accès à la carte est
   subordonné au clic sur le lien de confirmation.
3. **Le compte est l'identité unique de l'application.** Sorties de groupe,
   suivi solo, abonnement à la lettre d'information et, plus tard, traces et
   points d'intérêt se rattachent au même rider.
4. **Le socle vit dans `moto-tracker-server`.** Même service Express, même base
   SQLite, même chaîne de déploiement, et surtout le même envoi d'e-mails
   Brevo — dont la vérification d'adresse dépend entièrement.
5. **Une seule dépendance nouvelle côté application :**
   `flutter_secure_storage`.
6. **Rien de tout cela ne s'applique aux photos ni aux contenus binaires**, qui
   restent hors périmètre de bout en bout.
7. **Les installations existantes bénéficient d'un délai de grâce de 30 jours**
   avant que le mur d'inscription ne s'applique à elles.

## 4. Modèle de données

Trois tables ajoutées au schéma de `src/db.js`. Le schéma existant n'est pas
modifié : les colonnes de rattachement du chapitre 8 sont ajoutées, aucune
colonne n'est renommée, aucune donnée déplacée. Le serveur actuel continuerait
de fonctionner tel quel sur la base migrée.

```sql
CREATE TABLE IF NOT EXISTS account (
  id            TEXT PRIMARY KEY,     -- uuid
  email         TEXT NOT NULL UNIQUE, -- normalisé : découpé, en minuscules
  password_hash TEXT NOT NULL,        -- scrypt, sel et paramètres inclus
  display_name  TEXT,
  created_at    INTEGER NOT NULL,
  verified_at   INTEGER,              -- NULL tant que l'e-mail n'est pas confirmé
  deleted_at    INTEGER               -- effacement RGPD
);

CREATE TABLE IF NOT EXISTS account_token (
  token_hash TEXT PRIMARY KEY,        -- empreinte de 32 octets aléatoires
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  purpose    TEXT NOT NULL CHECK (purpose IN ('verify','reset')),
  expires_at INTEGER NOT NULL,
  used_at    INTEGER
);

CREATE TABLE IF NOT EXISTS account_session (
  token_hash   TEXT PRIMARY KEY,
  account_id   TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  expires_at   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_account_token_account ON account_token(account_id);
CREATE INDEX IF NOT EXISTS idx_account_session_account ON account_session(account_id);
```

**Aucun jeton n'est stocké en clair.** Le serveur ne conserve que son
empreinte, comme il le fait déjà pour le jeton de désabonnement de la lettre
d'information. Un jeton volé en base est donc inexploitable.

Le hachage des mots de passe utilise `scrypt` de `node:crypto` : aucune
dépendance nouvelle, dans un `package.json` qui n'en compte que trois.

Durées retenues : jeton de vérification 24 heures, jeton de réinitialisation
1 heure, session de l'application 180 jours prolongés à chaque échange réussi
avec le serveur.

## 5. Interface HTTP

Un routeur `src/routes/account.js`, monté sur `/api/account`, sur le modèle de
`src/routes/newsletter.js`.

| Route | Rôle |
|---|---|
| `POST /register` | Crée le compte non vérifié, envoie l'e-mail de confirmation, renvoie un jeton de session |
| `POST /login` | Renvoie un jeton de session et sa date d'expiration |
| `POST /logout` | Révoque le jeton présenté |
| `POST /verify/resend` | Renvoie l'e-mail de confirmation |
| `POST /email` | Corrige l'adresse d'un compte non vérifié et renvoie la confirmation |
| `POST /password/forgot` | Envoie le lien de réinitialisation |
| `POST /password/reset` | Consomme le jeton, remplace le mot de passe, révoque **toutes** les sessions du compte |
| `GET /me` | Profil du rider et état de vérification |
| `DELETE /me` | Effacement RGPD |

Une page HTML `GET /a/verify/:token` confirme la vérification dans le
navigateur, sur le modèle de la page de désabonnement existante.

`GET /me` est la route que l'écran d'attente interroge pour détecter la
confirmation sans que le rider ait à revenir dans l'application.

Le jeton de session délivré par `POST /register` existe avant la vérification,
mais **il n'ouvre que les routes de compte**. Toute route ajoutée par les lots
suivants exige un compte vérifié : le jeton non vérifié ne doit jamais devenir
un contournement du chapitre 3.2.

## 6. Sécurité

1. **Pas d'oracle d'inscription.** `POST /login` et `POST /password/forgot`
   répondent de façon identique, en contenu comme en délai, que le compte
   existe ou non. Sans cela le serveur dit publiquement qui est inscrit.
2. **Limitation de débit** sur `register`, `login`, `password/forgot` et
   `verify/resend`. Sans elle, le formulaire de connexion invite au bourrinage
   et le renvoi d'e-mail devient un canon à messages gratuit sur le quota
   Brevo, expédiés sous le nom du produit.
3. **Aucune adresse e-mail dans les journaux du serveur.**
4. **Mot de passe : 10 caractères minimum**, sans règle de composition
   arbitraire.
5. **Réinitialisation = révocation.** Changer son mot de passe déconnecte tous
   les appareils, c'est le geste de quelqu'un dont le compte a fuité. La
   révocation prend effet à la prochaine opération en ligne de l'appareil
   concerné : celui-ci demande alors une reconnexion, sans jamais fermer
   l'accès à la carte, au GPS, au SOS ni à la détection de chute — voir la
   première règle de robustesse du chapitre 7.
6. **L'effacement RGPD est effectif** : les lignes du compte, ses jetons et ses
   sessions sont supprimés, et les données rattachées voient leur `account_id`
   remis à NULL plutôt que d'être détruites — une sortie de groupe appartient
   aussi aux autres participants.

## 7. Parcours dans l'application

Trois briques nouvelles, calquées sur l'existant :
`lib/services/account_api_client.dart` (même forme que `TrackerApiClient`,
`http.Client` injectable), `lib/providers/account_provider.dart`
(`ChangeNotifier`, comme les douze autres providers), et `lib/screens/account/`.
Les routes sont déclarées dans `lib/app/router.dart`, l'accès au compte est
ajouté à `lib/screens/settings/settings_screen.dart`.

Première ouverture :

1. **Accueil** — créer un compte, ou se connecter.
2. **Inscription** — e-mail, mot de passe, prénom.
3. **Attente de confirmation** — trois issues, toutes nécessaires :
   *J'ai confirmé* (revérifie auprès du serveur), *Renvoyer l'e-mail*
   (fréquence limitée), *Corriger mon adresse*. Sans cette dernière, une faute
   de frappe enferme le rider dehors définitivement. L'écran interroge aussi
   `GET /me` toutes les cinq secondes, pour que la confirmation faite sur un
   ordinateur ouvre l'application sans geste supplémentaire.
4. **La carte** — et plus jamais de demande de connexion.

### 7.1 Délai de grâce des installations existantes

Un rider qui utilise l'application depuis des semaines ne doit pas trouver un
mur d'inscription au départ d'une sortie, sans avertissement. La nouvelle
version reconnaît donc les installations antérieures et leur laisse 30 jours.

**Reconnaître une installation antérieure.** Au premier lancement de la version
qui introduit les comptes, l'application cherche des données produites par les
versions précédentes : la base locale des sorties (`sqflite`) ou une préférence
existante. Si elle en trouve et qu'aucun compte n'est enregistré, elle inscrit
une échéance à 30 jours dans ses préférences. Une installation neuve n'a rien
de tout cela et va directement au mur.

**Pendant le délai**, l'application s'ouvre normalement sur la carte. Un bandeau
non bloquant, refermable et réaffiché à chaque lancement, annonce la date à
partir de laquelle le compte sera exigé et propose de le créer tout de suite.
Les fonctions du lot B et suivants restent, elles, réservées aux comptes : le
délai reporte le mur, il n'ouvre pas de porte dérobée.

**À l'échéance**, le mur s'applique comme pour une installation neuve.

L'échéance est locale, donc manipulable par qui recule l'horloge de son
téléphone. C'est sans importance : ce délai est une politesse envers les riders
fidèles, pas un contrôle d'accès.

**Ce chemin est temporaire et doit être écrit comme tel** : isolé dans un seul
endroit, signalé par un commentaire indiquant sa condition de retrait, et
supprimé une fois que les installations d'avant les comptes auront disparu du
parc.

Le jeton est conservé par `flutter_secure_storage` (Trousseau iOS, Keystore
Android). `shared_preferences` conviendrait techniquement, mais un jeton
d'identité y est lisible sur un appareil déverrouillé par la racine et part
dans la sauvegarde automatique Android : il serait restauré sur un autre
téléphone.

**Deux règles de robustesse, non négociables :**

- **L'application ne se re-verrouille jamais en cours de sortie.** Le jeton
  local vaut identité tant que le rider ne se déconnecte pas lui-même. Le
  serveur n'est interrogé que pour les opérations en ligne ; si un appel
  échoue, cet appel échoue, et l'application reste ouverte avec la carte, le
  GPS, le SOS et la détection de chute. Aucun écran de connexion ne surgit au
  milieu de nulle part.
- **L'absence de réseau se dit.** Créer un compte exige le serveur : un rider
  qui installe l'application dans un fond de vallée ne pourra pas entrer. Le
  message doit l'énoncer franchement et proposer de réessayer, jamais rester
  figé.

## 8. Migration de l'existant

Trois colonnes `account_id` facultatives sont ajoutées, sur `session`, sur
`member` et sur `subscriber`. Le rattachement se fait par adresse e-mail
lorsqu'elle existe :

- `subscriber` et `session.pilot_email` sont rattachés à l'inscription :
  même adresse, même personne.
- `alert_contact` n'est **jamais** rattaché. Ce sont les proches du rider, pas
  des utilisateurs ; leur adresse n'a rien à faire dans une fiche de compte.
- `member` ne peut pas l'être rétroactivement : la table ne contient qu'une
  clé d'appareil et un prénom. Seules les sorties futures d'un rider connecté
  porteront son `account_id`. Les anciennes restent orphelines, et aucune
  correspondance n'est devinée.

## 9. Exploitation

Jusqu'ici `moto-tracker-server` n'hébergeait que du jetable : `src/sweep.js`
balaie les positions périmées et rien n'y est irremplaçable. À partir de ce lot
il détient des comptes.

- **Sauvegarde quotidienne** de la base par `VACUUM INTO` vers un fichier daté,
  avec rotation.
- **Garde dans `src/sweep.js`** : le balayage ne touche jamais aux tables de
  comptes. Seuls les jetons expirés ou consommés sont purgés.

## 10. Tests

Côté serveur, `test/account.test.js` dans le style `node:test` déjà en place :

- inscription puis vérification, ouverture d'une session valide ;
- refus d'une inscription en double ;
- réponses identiques sur un identifiant valide et invalide, vérifié
  explicitement — c'est la protection du chapitre 6.1 ;
- jetons à usage unique et expirés, refusés ;
- réinitialisation qui révoque toutes les sessions du compte ;
- effacement RGPD réellement effectif, avec `account_id` remis à NULL sur les
  lignes rattachées ;
- limitation de débit atteinte puis relâchée.

Côté application, tests du client HTTP avec un `http.Client` simulé et tests du
provider, comme pour `TrackerApiClient`.

## 11. Hors périmètre

Ne relèvent pas de ce lot, et ne doivent pas être anticipés dans son code :
le partage de traces (lot B), la console web (lot C), les points d'intérêt
contribués (lot D), la connexion par fournisseur tiers, les photos, et tout
cloisonnement entre plusieurs applications — la diffusion visée ne concerne que
les installations de MOTO OFFROAD.

## 12. Critères d'acceptation

1. Une installation neuve ne donne accès à la carte qu'après création d'un
   compte et clic sur le lien de confirmation.
2. Une réouverture de l'application, même des semaines plus tard, n'affiche
   aucun écran de connexion.
3. Une sortie en cours ne fait jamais surgir d'écran de connexion, y compris
   serveur injoignable ou jeton expiré.
4. Le SOS, la détection de chute et le suivi solo fonctionnent hors ligne pour
   un rider déjà connecté.
5. Une adresse mal saisie peut être corrigée depuis l'écran d'attente, sans
   désinstaller l'application.
6. `POST /login` et `POST /password/forgot` ne permettent pas de distinguer un
   compte existant d'un compte inconnu.
7. La suppression du compte depuis l'application efface effectivement les
   données personnelles et déconnecte tous les appareils.
8. La sauvegarde quotidienne produit un fichier restaurable, et `sweep.js` ne
   supprime aucun compte.
9. Une installation qui contient des données d'une version antérieure s'ouvre
   sur la carte après la mise à jour, avec le bandeau d'avertissement et sa
   date d'échéance.
10. La même installation, passé 30 jours, exige le compte comme une
    installation neuve.
11. Une installation neuve ne bénéficie d'aucun délai, même si l'appareil a
    déjà hébergé l'application par le passé.
