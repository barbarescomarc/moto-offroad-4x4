# Partage de traces — catalogue public dans l'application

Design validé le 9 septembre 2026.

## 1. Contexte

Le lot A a donné au serveur une identité de rider : un compte, une adresse
vérifiée, une session porteuse de jeton. Il n'en a encore rien fait. Aucune
donnée créée après l'inscription ne porte `account_id`, parce que
`TrackerApiClient` n'envoie jamais le jeton — `member.account_id` est une
colonne morte, et l'identité relie le passé sans relier l'avenir.

Le partage de traces est la première fonction qui a besoin de cette identité :
une trace publiée appartient à quelqu'un, et l'on doit pouvoir remonter à son
auteur le jour où elle pose problème.

Aujourd'hui le partage existe sous une forme dégradée :
`RideExportService.shareGpx()` écrit un fichier GPX temporaire et le confie au
menu de partage du téléphone. Le fichier part par messagerie, le serveur n'en
sait rien, et personne ne peut ni compter les téléchargements ni retirer une
trace qui s'avère problématique.

## 2. Périmètre

La feuille de route parlait d'un « partage par lien privé + compteur de
téléchargements ». Le besoin exprimé le 9 septembre est différent et le
remplace : **les riders publient leurs traces dans un catalogue public
consultable et téléchargeable depuis l'application**. Il n'y a ni lien à
envoyer, ni page web publique : tout se passe entre l'application et le
serveur.

Ce que le lot B livre :

- un rider publie une de ses sorties, après avoir rempli une fiche
  (description, auteur, engin, difficulté) et recadré la trace ;
- les autres riders parcourent le catalogue trié par distance et téléchargent
  une trace dans leurs sorties ;
- un compteur de téléchargements par trace ;
- un bouton de signalement ;
- deux actions de modération a posteriori — masquer (réversible) et supprimer
  (définitif) — accessibles en ligne de commande avec la clé d'administration
  existante, en attendant l'interface web du lot C ;
- la dette d'identité du lot A soldée.

## 3. Décisions structurantes

1. **La modération est a posteriori.** Une trace publiée est visible
   immédiatement. L'administrateur la retire ensuite si besoin. Aucune file
   d'attente de validation : elle appartiendra au lot C si elle s'avère
   nécessaire pour les POI.
2. **Un téléchargement est une copie définitive.** La trace téléchargée entre
   dans les sorties du rider comme une trace importée et lui appartient. Le
   masquage d'une trace la retire du catalogue et bloque les téléchargements
   futurs ; il ne touche à aucune copie déjà téléchargée. Le serveur n'a
   donc aucun mécanisme de révocation à distance, et l'application ne fait
   jamais disparaître une trace de la poche d'un rider.
3. **Le classement se fait par distance.** La liste est triée par distance
   entre le point de référence — ma position, ou un lieu que je choisis — et
   le point de départ de la trace, avec un filtre de rayon.
4. **Le recadrage est manuel et obligatoire à la première publication.** Une
   sortie enregistrée démarre presque toujours devant chez son auteur.
   L'écran de publication propose deux curseurs de début et de fin, et
   avertit explicitement à la première publication. La sortie d'origine
   n'est jamais modifiée : le recadrage ne s'applique qu'à la copie publiée.
5. **L'auteur affiché est un pseudo, le propriétaire réel est un compte.**
   `author_name` est libre (pré-rempli avec le nom du profil pilote) ;
   `account_id` reste attaché à la trace et n'est jamais renvoyé à un autre
   rider. C'est ce couple qui permet de modérer sans exposer les identités.
6. **Le catalogue s'installe dans l'onglet Sorties**, en deux volets
   « Mes sorties » / « Partagées », plutôt que dans un sixième onglet : la
   barre du bas est déjà chargée, et publier comme télécharger sont des
   opérations sur des sorties.

## 4. Modèle de données

Trois tables s'ajoutent au schéma de `src/db.js`.

```sql
CREATE TABLE IF NOT EXISTS shared_trace (
  id               TEXT PRIMARY KEY,
  account_id       TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  author_name      TEXT NOT NULL,
  name             TEXT NOT NULL,
  description      TEXT NOT NULL,
  vehicle          TEXT NOT NULL CHECK (vehicle IN ('moto','4x4','mixte')),
  difficulty       TEXT NOT NULL CHECK (difficulty IN ('facile','moyen','difficile')),
  start_lat        REAL NOT NULL,
  start_lng        REAL NOT NULL,
  distance_m       REAL NOT NULL,
  elevation_gain_m REAL,
  duration_s       INTEGER,
  point_count      INTEGER NOT NULL,
  gpx_bytes        INTEGER NOT NULL,
  gpx_sha256       TEXT NOT NULL,
  recorded_at      INTEGER,
  published_at     INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  download_count   INTEGER NOT NULL DEFAULT 0,
  hidden_at        INTEGER,
  hidden_reason    TEXT
);

CREATE TABLE IF NOT EXISTS trace_report (
  id         INTEGER PRIMARY KEY,
  trace_id   TEXT NOT NULL REFERENCES shared_trace(id) ON DELETE CASCADE,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  reason     TEXT NOT NULL,
  detail     TEXT,
  created_at INTEGER NOT NULL,
  handled_at INTEGER,
  UNIQUE (trace_id, account_id)
);

CREATE TABLE IF NOT EXISTS trace_download (
  trace_id      TEXT NOT NULL REFERENCES shared_trace(id) ON DELETE CASCADE,
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  downloaded_at INTEGER NOT NULL,
  PRIMARY KEY (trace_id, account_id)
);

CREATE INDEX IF NOT EXISTS idx_shared_trace_box ON shared_trace(start_lat, start_lng);
CREATE INDEX IF NOT EXISTS idx_shared_trace_account ON shared_trace(account_id);
CREATE INDEX IF NOT EXISTS idx_trace_report_trace ON trace_report(trace_id);
```

Notes de conception :

- `ON DELETE CASCADE` sur `account_id` est ici volontaire, contrairement à
  `session.account_id` : une trace publiée n'appartient qu'à son auteur, et
  l'effacement RGPD d'un compte doit emporter ses publications. Le fichier
  GPX correspondant est supprimé du disque dans la même opération.
- Le chemin du fichier n'est pas stocké : il se déduit de l'identifiant
  (`<TRACES_DIR>/<id>.gpx`). Une colonne de chemin serait une source de
  divergence entre la base et le disque.
- `download_count` est dénormalisé pour que la liste n'ait pas à agréger
  `trace_download` à chaque requête ; `trace_download` reste la source de
  vérité et permet de le recalculer.
- Le fichier GPX est immuable une fois publié. Modifier la fiche ne le
  touche pas ; publier une trace recadrée différemment est une nouvelle
  publication.

## 5. Interface HTTP

Toutes les routes sont montées sur `/api/traces` par
`createTracesRouter(db, { tracesDir, now })`.

| Méthode | Chemin | Accès | Rôle |
|---|---|---|---|
| `POST` | `/api/traces` | compte vérifié | publie une trace |
| `GET` | `/api/traces` | compte | liste triée par distance |
| `GET` | `/api/traces/:id` | compte | fiche complète et tracé simplifié |
| `GET` | `/api/traces/:id/gpx` | compte | télécharge le GPX, compte le téléchargement |
| `GET` | `/api/traces/mine` | compte | les publications du rider connecté |
| `PATCH` | `/api/traces/:id` | auteur | modifie la fiche |
| `DELETE` | `/api/traces/:id` | auteur | dépublie définitivement |
| `POST` | `/api/traces/:id/report` | compte | signale la trace |

Et l'administration, sur `/api/admin/traces`, protégée par
`ADMIN_EXPORT_KEY` selon le mécanisme déjà en place pour l'export de la
lettre d'information (`?key=…`) :

| Méthode | Chemin | Rôle |
|---|---|---|
| `GET` | `/api/admin/traces` | liste tout, masquées comprises, avec signalements et e-mail de l'auteur |
| `GET` | `/api/admin/reports` | signalements non traités, les plus récents d'abord |
| `POST` | `/api/admin/traces/:id/hide` | masque, avec un motif |
| `POST` | `/api/admin/traces/:id/unhide` | démasque |
| `DELETE` | `/api/admin/traces/:id` | supprime définitivement, fichier compris |

### Publication

`POST /api/traces` reçoit du JSON : la fiche et le GPX en texte.

```json
{
  "name": "Boucle du Sidobre",
  "description": "Pistes forestières, deux gués…",
  "authorName": "Marco31",
  "vehicle": "moto",
  "difficulty": "moyen",
  "gpx": "<?xml version=\"1.0\"…"
}
```

Le serveur analyse lui-même le GPX plutôt que de faire confiance à des
statistiques envoyées par le client : il en tire le point de départ, la
longueur, le dénivelé, la durée, le nombre de points, et rejette un fichier
illisible. Un client modifié ne peut donc pas se déclarer à 3 km de tout le
monde.

La lecture du GPX se fait avec `fast-xml-parser`, seule dépendance
ajoutée par ce lot : elle est en JavaScript pur, donc elle ne réveille pas le
problème d'addons natifs de ce poste. Le lecteur ne retient que
`trk/trkseg/trkpt` (latitude, longitude, `ele`, `time`) et ignore le reste,
routes et points isolés compris — une trace publiée est une trace roulée.

Refus possibles : `400` (GPX illisible, moins de deux points, fiche
incomplète), `403` (adresse non vérifiée), `413` (au-delà de 5 Mo ou de
50 000 points), `429` (au-delà de 10 publications par compte et par jour).

### Liste

`GET /api/traces?lat=43.6&lng=1.44&rayon=50&engin=moto&difficulte=facile&q=sidobre&limite=50&depuis=0`

`lat` et `lng` sont obligatoires, `rayon` vaut 50 km par défaut et 300 km au
maximum. Le tri se fait en deux temps : un rectangle englobant filtre en SQL
sur l'index `idx_shared_trace_box`, puis la distance orthodromique réelle est
calculée en mémoire, filtrée sur le rayon, et triée. À l'échelle de plusieurs
milliers de traces, c'est immédiat ; le jour où cela ne suffirait plus, le
rectangle reste le point d'accroche pour un index spatial.

Les traces masquées ne figurent jamais dans cette liste, ni dans
`GET /api/traces/:id`, y compris pour leur auteur — qui les voit en revanche
dans `GET /api/traces/mine`, marquées comme retirées.

Chaque entrée renvoie : identifiant, nom, auteur affiché, engin, difficulté,
longueur, dénivelé, durée, date de la sortie, nombre de téléchargements,
distance au point de référence. Jamais `account_id` ni l'adresse de l'auteur.

### Téléchargement

`GET /api/traces/:id/gpx` renvoie le fichier et insère une ligne dans
`trace_download`. L'insertion étant `INSERT OR IGNORE` sur la clé primaire
`(trace_id, account_id)`, `download_count` n'est incrémenté qu'au premier
téléchargement d'un rider donné : le compteur compte des riders, pas des
reclics. Télécharger sa propre trace ne compte pas.

### Signalement

`POST /api/traces/:id/report` avec un motif parmi `terrain_prive`,
`dangereux`, `doublon`, `inapproprie`, `autre`, et un texte libre facultatif.
Un rider ne peut signaler qu'une fois la même trace (contrainte `UNIQUE`).
Le signalement ne masque rien tout seul : il alimente la file que
l'administrateur consulte.

## 6. Fichiers et sauvegarde

Les GPX vivent dans `TRACES_DIR` (`/app/data/traces` en production), sur le
même volume que la base. L'écriture suit la même règle que la sauvegarde :
écrire dans un `.tmp` puis renommer, pour qu'une publication interrompue ne
laisse pas de fichier tronqué référencé par une ligne valide.

`src/backup.js` ne sauvegarde aujourd'hui que la base. Restaurer une
sauvegarde laisserait donc toutes les fiches sans fichier. Le lot B ajoute
`backupTraces(tracesDir, backupDir)` : les fichiers étant immuables, la copie
se limite à ceux qui manquent dans `<backupDir>/traces/`, et les fichiers
dont la trace a disparu sont retirés. Cette fonction s'exécute dans le même
cycle quotidien que `backupDatabase`, et son échec n'empêche ni la sauvegarde
de la base ni le démarrage du serveur.

## 7. Parcours dans l'application

### 7.1 Publier

Depuis la fiche d'une sortie (`ride_detail_screen.dart`), à côté du bouton
d'export GPX existant, un bouton **Publier**. Il ouvre un écran de
publication en deux parties :

- **Le recadrage** : l'aperçu de la trace sur la carte, deux curseurs de
  début et de fin, la longueur publiée recalculée en direct. À la première
  publication seulement, un encart explique que la trace commence
  probablement devant chez soi.
- **La fiche** : nom (pré-rempli avec celui de la sortie), description
  (obligatoire), auteur (pré-rempli avec le nom du profil pilote), engin,
  difficulté.

Une sortie téléchargée depuis le catalogue n'affiche pas ce bouton.

### 7.2 Découvrir

L'onglet Sorties reçoit un sélecteur en haut : **Mes sorties** /
**Partagées**. Le volet Partagées affiche :

- le point de référence — ma position par défaut, ou un lieu choisi via la
  recherche de lieux déjà utilisée par le guidage ;
- un filtre de rayon (10, 25, 50, 100, 200 km) ;
- des filtres engin et difficulté, et une recherche par nom ;
- la liste triée par distance : nom, auteur, distance depuis le point de
  référence, longueur, difficulté, engin, nombre de téléchargements.

Ouvrir une entrée affiche la fiche : aperçu du tracé sur la carte, statistiques,
description, et deux boutons — **Télécharger** et **Signaler**.

### 7.3 Télécharger

Le téléchargement écrit la trace dans `RideDatabase` comme une sortie
importée (`RideSource.imported`), avec le nom et la description de la fiche.
Un champ `sharedTraceId` sur `Ride` mémorise son origine : il empêche la
republication et permet d'afficher « téléchargée depuis le partage » sur la
fiche locale. La trace reste ensuite une sortie comme les autres — elle
survit à tout retrait du catalogue.

Un rider peut retrouver ses propres publications, modifier leur fiche ou les
dépublier depuis un écran accessible depuis le volet Partagées.

## 8. Dette du lot A

`TrackerApiClient` gagne l'en-tête `Authorization: Bearer <jeton>` fourni par
`AccountStorage`, comme le fait déjà `AccountApiClient`. En conséquence :

- `POST /api/sessions` et `POST /api/sessions/join/:code` renseignent
  `session.account_id` et `member.account_id` quand le jeton est présent ;
- l'absence de jeton reste tolérée côté serveur — une alerte de chute ne doit
  jamais échouer parce qu'une session de compte a expiré. C'est un
  rattachement, pas une authentification.

Le partage de traces, lui, exige le jeton : publier, lister, télécharger et
signaler renvoient `401` sans lui.

## 9. Sécurité et garde-fous

- Publier exige un compte **vérifié** (`requireVerified`, déjà écrit au lot A).
- `authenticate` et `requireVerified` sont extraits de
  `src/routes/account.js` vers `src/accounts/auth.js` et importés par les
  deux routeurs. Aucun changement de comportement.
- Limitation de débit par IP sur la publication et le signalement, via
  `createRateLimiter` existant, en plus du quota de 10 publications par compte
  et par jour.
- Taille maximale du corps JSON relevée pour cette route seulement (6 Mo),
  pas globalement.
- Les identifiants de trace sont des jetons aléatoires, pas des entiers :
  l'identifiant d'une trace masquée ne doit pas être devinable.
- La description et le nom d'auteur sont renvoyés tels quels à l'application,
  qui les affiche comme du texte — aucune page web ne les rend, donc aucun
  risque d'injection HTML dans ce lot.

## 10. Exploitation avant le lot C

Tant que l'interface d'administration n'existe pas, les quatre gestes se font
en une ligne :

```sh
curl -s "https://motooffroad.duckdns.org/api/admin/reports?key=$ADMIN_EXPORT_KEY"
curl -s -X POST "https://motooffroad.duckdns.org/api/admin/traces/<id>/hide?key=$ADMIN_EXPORT_KEY" \
     -H 'content-type: application/json' -d '{"reason":"terrain privé signalé par le propriétaire"}'
```

Le lot C remplacera la clé unique par des comptes administrateurs et posera
une interface sur ces mêmes routes.

## 11. Tests

Serveur (`node:test`, comme l'existant) :

- publication : fiche valide acceptée, GPX illisible rejeté, adresse non
  vérifiée rejetée, quota journalier atteint rejeté, statistiques calculées
  par le serveur et non reprises du client ;
- liste : tri par distance croissante, filtre de rayon excluant une trace
  au-delà, filtres engin et difficulté, trace masquée absente ;
- téléchargement : compteur incrémenté une fois pour deux téléchargements du
  même rider, deux fois pour deux riders différents, sa propre trace non
  comptée ;
- masquage : invisible dans la liste publique, visible en admin, démasquage
  qui la fait réapparaître ; suppression qui efface aussi le fichier ;
- signalement : doublon refusé, remontée dans la file admin ;
- effacement RGPD d'un compte : ses traces et ses fichiers disparaissent ;
- sauvegarde : les fichiers manquants sont copiés, ceux des traces supprimées
  sont retirés, un échec de copie n'empêche pas la sauvegarde de la base.

Application :

- recadrage : les points hors curseurs sont absents du GPX publié, la sortie
  d'origine est intacte ;
- provider du catalogue : tri, filtres, pagination, état d'erreur réseau ;
- téléchargement : la sortie créée porte `sharedTraceId` et ne propose plus
  le bouton Publier ;
- `TrackerApiClient` : le jeton est envoyé quand il existe, la requête part
  quand même sans lui.

Les tests serveur tournent dans Docker : `better-sqlite3` est un addon natif
et les outils de compilation de ce Mac sont hors service.

**Vérification sur appareil réel obligatoire avant de déclarer le lot
terminé** — publication, liste triée par distance, téléchargement, réimport,
signalement. La leçon du 9 septembre sur Overpass vaut pour tout ce lot :
un `MockClient` ne révèle ni un rejet d'en-tête, ni une lenteur, ni un
résultat qui reste invisible à l'écran.

## 12. Hors périmètre

- L'interface web d'administration et les comptes administrateurs (lot C).
- Les POI contribués par les riders (lot D).
- Les commentaires, notes et favoris sur les traces.
- Toute page web publique présentant une trace, et tout partage par lien.
- La révocation à distance d'une trace déjà téléchargée (décision 2).

## 13. Critères d'acceptation

1. Un rider vérifié publie une sortie recadrée ; elle apparaît dans le
   catalogue d'un second rider situé à 20 km, et pas dans celui d'un rider
   situé à 400 km avec un rayon de 50 km.
2. Les statistiques affichées sont celles calculées par le serveur à partir
   du GPX reçu.
3. Le second rider télécharge la trace ; elle apparaît dans ses sorties,
   utilisable en guidage, et le compteur affiche 1.
4. Il la télécharge une seconde fois : le compteur affiche toujours 1.
5. Un administrateur masque la trace : elle disparaît du catalogue des deux
   riders, reste dans les sorties de celui qui l'avait téléchargée, et son
   auteur la voit marquée comme retirée.
6. L'administrateur la démasque : elle réapparaît, compteur intact.
7. Un rider signale une trace ; le signalement remonte dans la file
   d'administration, et un second signalement du même rider est refusé.
8. Un rider supprime son compte : ses publications et leurs fichiers
   disparaissent, les sorties de ceux qui les avaient téléchargées ne bougent
   pas.
9. Une sortie de groupe créée après connexion porte `account_id` en base.
