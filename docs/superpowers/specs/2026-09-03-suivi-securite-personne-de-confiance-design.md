# Suivi de sécurité et personne de confiance

Design validé le 3 septembre 2026.

## 1. Contexte

L'application affiche un mode Solo et un mode Groupe. Ni l'un ni l'autre ne
fonctionne. L'audit du code révèle quatre manques :

- **L'écran Mode Solo est inatteignable.** Le seul lien vers `AppRoutes.solo`
  est le badge de `map_screen.dart:676`, qui ne s'affiche que si
  `soloActive == true`. Or le mode ne peut être activé que depuis cet écran.
  Aucun numéro de personne de confiance ne peut donc être saisi aujourd'hui.
- **Le lien de suivi est décoratif.** `SoloProvider.trackingUrl` fabrique
  `https://motooffroad.app/s/<token>`. Ce domaine n'existe pas et aucune
  position n'est transmise nulle part.
- **Le SOS ne parle jamais aux contacts.** `SosService` sait appeler le 112,
  lui envoyer un SMS et partager la position, mais rien dans le code ne
  contacte les `TrustedContact` enregistrés.
- **Le mode Groupe est une maquette.** `FirebaseGroupService` est entièrement
  écrit — Realtime Database, authentification anonyme, diffusion toutes les
  3 secondes, point de ralliement — mais **il n'est appelé nulle part**.
  `GroupProvider` gère une liste en mémoire. Les trois dépendances Firebase de
  `pubspec.yaml` et l'initialisation de `main.dart` ne servent à rien.

Le besoin exprimé est simple : qu'une personne de confiance puisse suivre le
trajet sur un fond de carte et soit prévenue en cas de chute ou de SOS.

## 2. Relation avec la feuille de route existante

Ce document **remplace les lots 4 et 5** de la feuille de route du 2 septembre
(« Sécurité SOS » et « Groupes temps réel : Firebase »). Le changement de fond
est l'abandon de Firebase au profit d'un service auto-hébergé sur le serveur
Hetzner existant, décidé pour garder la maîtrise des données de
géolocalisation.

Deux briques du lot 1 sont réutilisées telles quelles : le service
d'arrière-plan (`flutter_foreground_task`) et l'accéléromètre
(`sensors_plus`), qui avaient été dimensionnés pour cet usage.

## 3. Découpage

| Lot | Contenu | Dépend de |
|-----|---------|-----------|
| **A** | Hub de positions — service isolé sur le Hetzner | — |
| **B** | Suivi solo — écran accessible, envoi des positions, page web du contact | A |
| **C** | Chute et chaîne d'alerte — triple critère, double canal, verrou d'abonnement | A, B |
| **D** | Communauté — 20 pilotes, migration Firebase → hub | A |
| **E** | Auto-réponse et partage de position | **aucune** |

Le lot E ne dépend d'aucun serveur : il n'utilise que du code local et des
briques déjà présentes. Il est livré **en premier**, ce qui met une fonction
utile entre les mains de l'utilisateur sans attendre l'infrastructure.

## 4. Décisions de cadrage

| Sujet | Décision |
|-------|----------|
| Hébergement | Serveur Hetzner existant, **stack entièrement dissociée** du streaming |
| Unification | Suivi solo et Communauté partagent un seul service : ce sont deux modes de lecture du même flux de positions |
| Base de données | SQLite dans un volume dédié — un Postgres serait un conteneur de plus pour 20 pilotes |
| Transport montant | HTTP POST par lots, tolérant aux coupures réseau |
| Transport descendant | SSE pour la page web du contact, interrogation toutes les 3 s pour l'application |
| Comptes utilisateurs | Aucun. Secrets opaques uniquement |
| Canaux d'alerte | Deux canaux redondants, **choisis par l'utilisateur** dans l'application |
| Canal serveur livré | E-mail actif ; SMS et appel vocal codés mais **verrouillés** derrière un futur abonnement |
| Détection de chute | Trois critères successifs obligatoires ; compte à rebours réglable ; fonction désactivable |
| Immobilité sans choc | Couverte côté serveur, pas côté téléphone |
| Purge groupe | Extinction du groupe → **suppression immédiate et totale** |
| Purge après alerte | Session et positions conservées **7 jours** puis supprimées : après un accident, retrouver le trajet a une valeur |
| Plateforme | Android uniquement (pas de dossier `ios`) |

## 5. Lot A — Hub de positions

### 5.1 Isolation vis-à-vis du streaming

Rien de ce qui existe sur le serveur n'est modifié. Le streaming conserve
`/root/rtmp-server`, son `docker-compose`, ses conteneurs MediaMTX, son fichier
`drone31.conf` et son certificat.

| Élément | Streaming (inchangé) | Hub de suivi (nouveau) |
|---------|----------------------|------------------------|
| Répertoire | `/root/rtmp-server` | `/root/moto-tracker` |
| Composition Docker | la sienne | la sienne |
| Port interne | `127.0.0.1:3000` | `127.0.0.1:3100` |
| Site nginx | `drone31.conf` | `moto-tracker.conf` |
| Domaine | `drone31.duckdns.org` | `motooffroad.duckdns.org` |
| Certificat | le sien | le sien |
| Dépôt Git | `barbarescomarc/drone31-server` | dépôt distinct |

Le conteneur n'écoute que sur la boucle locale. Seul nginx l'expose, en HTTPS.

Ressources disponibles au moment de la conception : 28 Go de disque libres et
6 Go de mémoire disponible. Le hub consomme une fraction négligeable des deux.

### 5.2 Pile technique

Node.js et Express, cohérents avec le service de streaming. SQLite via
`better-sqlite3` — accès synchrone, pas de conteneur supplémentaire, fichier
unique sauvegardable par simple copie.

### 5.3 Modèle de données

```sql
CREATE TABLE session (
  id             TEXT PRIMARY KEY,   -- uuid interne
  kind           TEXT NOT NULL,      -- 'solo' | 'group'
  watch_token    TEXT UNIQUE,        -- lecture publique, solo uniquement
  join_code      TEXT UNIQUE,        -- 6 caractères, groupe uniquement
  owner_key      TEXT NOT NULL,      -- secret du créateur
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL,
  ended_at       INTEGER,
  deadman_after  INTEGER,            -- secondes de silence avant alerte (solo)
  immobile_after INTEGER,            -- secondes sans déplacement avant alerte (solo)
  alerted_at     INTEGER
);

CREATE TABLE member (
  id         TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  device_key TEXT NOT NULL,          -- secret propre à l'appareil
  name       TEXT NOT NULL,
  color      TEXT NOT NULL,
  joined_at  INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL
);

CREATE TABLE position (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id  TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  member_id   TEXT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
  lat         REAL NOT NULL,
  lng         REAL NOT NULL,
  speed_kmh   REAL,
  heading     REAL,
  altitude    REAL,
  accuracy    REAL,
  recorded_at INTEGER NOT NULL,      -- horodatage du téléphone
  received_at INTEGER NOT NULL       -- horodatage du serveur
);

CREATE TABLE alert (
  id         TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  member_id  TEXT NOT NULL,
  kind       TEXT NOT NULL,          -- 'fall' | 'sos' | 'deadman' | 'immobile'
  lat        REAL,
  lng        REAL,
  created_at INTEGER NOT NULL,
  channels   TEXT NOT NULL           -- JSON : canaux tentés et résultat
);
```

Le tableau `position` est plafonné à **500 points par membre**. Au-delà, les
plus anciens sont supprimés à l'insertion. C'est assez pour dessiner une trace
lisible et cela borne la taille de la base.

### 5.4 Modèle d'accès

Aucun compte, aucun mot de passe. Quatre secrets opaques, chacun avec un rôle
unique :

| Secret | Détenu par | Autorise |
|--------|-----------|----------|
| `owner_key` | le créateur de la session | clore et purger la session |
| `device_key` | chaque appareil membre | envoyer ses positions, lire celles des pairs |
| `watch_token` | la personne de confiance | **lecture seule** de la page de suivi |
| `join_code` | les invités du groupe | rejoindre, une seule fois |

`watch_token` fait 16 caractères tirés au hasard : non devinable par force
brute, et non indexé par les moteurs de recherche (`X-Robots-Tag: noindex` et
`robots.txt`).

### 5.5 Routes

Application, authentifiées par `device_key` ou `owner_key` :

| Route | Rôle |
|-------|------|
| `POST /api/sessions` | Créer une session. Renvoie les identifiants et secrets |
| `POST /api/sessions/join/:joinCode` | Rejoindre un groupe |
| `POST /api/sessions/:id/positions` | Envoyer un lot de positions |
| `GET /api/sessions/:id/peers` | Positions des autres membres (groupe) |
| `POST /api/sessions/:id/alert` | Déclarer une chute ou un SOS |
| `POST /api/sessions/:id/end` | Clore la session et purger |
| `DELETE /api/sessions/:id/members/:memberId` | Quitter un groupe |

Publiques, authentifiées par `watch_token` :

| Route | Rôle |
|-------|------|
| `GET /s/:watchToken` | Page HTML de suivi |
| `GET /api/watch/:watchToken` | État courant en JSON |
| `GET /api/watch/:watchToken/stream` | Flux SSE des mises à jour |

Exploitation : `GET /healthz`.

### 5.6 Cadence et tolérance au réseau

Positions envoyées toutes les **5 secondes** en solo, **3 secondes** en groupe.
Hors réseau, l'application accumule les points et les transmet en un lot au
retour de la couverture — chaque point porte son propre `recorded_at`, si bien
que la trace reste juste malgré le retard.

Limitation de débit : `limit_req` côté nginx et une requête toutes les
2 secondes par `device_key` côté application.

### 5.7 Surveillance côté serveur

Un balayage toutes les 30 secondes examine les sessions solo actives :

- **Homme mort** — aucune position reçue depuis `deadman_after` secondes.
  Couvre le téléphone détruit, déchargé ou hors réseau, cas que le canal
  téléphone ne peut pas traiter par construction.
- **Immobilité** — les positions arrivent mais le pilote ne s'est pas déplacé
  de plus de 50 mètres depuis `immobile_after` secondes. Couvre le malaise, la
  jambe coincée sous la moto, l'endormissement. C'est l'usage enfin réel du
  réglage `immobilityThresholdMin` de `SoloProvider`, aujourd'hui stocké et
  jamais lu.

Une session n'alerte qu'une fois : `alerted_at` verrouille les répétitions.

### 5.8 Purge

- **Clôture d'une session** — suppression immédiate des membres et de toutes
  les positions. La ligne `session` disparaît également.
- **Exception, session ayant déclenché une alerte** — la clôture ne purge rien.
  Session, positions et alerte sont conservées 7 jours puis supprimées, pour
  pouvoir reconstituer le trajet après un accident. C'est le seul cas où des
  positions survivent à la fin d'une sortie.
- **Balayage horaire** — suppression des sessions dont `expires_at` est dépassé
  et des sessions orphelines closes il y a plus de 24 heures, pour les
  applications tuées sans clôture propre.

## 6. Lot B — Suivi solo

### 6.1 Correction d'accès

`SoloScreen` devient atteignable. Une entrée « Mode Solo Sécurisé » est ajoutée
à `SettingsScreen`, et le badge de la carte reste comme raccourci quand le mode
est actif. C'est la correction du défaut qui rend aujourd'hui la saisie d'un
numéro de personne de confiance impossible.

### 6.2 Envoi des positions

Le service d'arrière-plan du lot 1 est étendu : lorsque le mode Solo est actif,
il transmet les positions au hub en plus de les enregistrer localement. La
notification permanente indique que le suivi est en cours — exigence Android,
et transparence utile.

`SoloProvider.trackingUrl` cesse de fabriquer une URL fictive et renvoie
l'adresse réelle servie par le hub.

À l'activation du mode Solo, l'application propose d'envoyer ce lien par SMS
aux contacts sélectionnés, dans un message court du type « Je pars rouler, tu
peux me suivre ici : <lien> ». L'envoi passe par l'application de messagerie et
demande une pression : ici l'utilisateur est disponible, rien ne justifie un
envoi silencieux. Le lien reste consultable et repartageable depuis
`SoloScreen` pendant toute la sortie.

### 6.3 Page de la personne de confiance

Page HTML autonome, sans installation ni compte. Leaflet sur fond
OpenStreetMap, cohérent avec `flutter_map` côté application.

Elle affiche le dernier point connu, la trace parcourue, la vitesse, l'heure du
dernier point reçu et l'état de la sortie : *en route*, *silencieux depuis X
minutes*, ou *alerte*. En cas d'alerte, un bandeau rouge et un bouton
d'appel direct vers le pilote.

Seul le prénom choisi par le pilote y figure. Aucune donnée personnelle
supplémentaire n'est transmise au serveur.

## 7. Lot C — Chute et chaîne d'alerte

### 7.1 Détection en trois temps

Les trois conditions doivent se produire **dans cet ordre** pour qu'une chute
soit retenue :

1. **Choc** — la norme de l'accélération dépasse le seuil. Si une calibration a
   été faite, le seuil est calé sur la mesure de
   `VibrationCalibrationScreen`, qui connaît le niveau de vibration propre à la
   moto et au terrain ; il est plus juste qu'un seuil universel. Sans
   calibration, le seuil retombe sur **4 g**, et l'écran de réglage invite à
   calibrer pour affiner la détection.
2. **Arrêt GPS** — vitesse inférieure à 3 km/h pendant 20 secondes après le
   choc.
3. **Inclinaison figée** — l'orientation du téléphone, déduite du vecteur de
   gravité, ne varie pas de plus de 5° pendant 20 secondes.

Cette conjonction est ce qui rend la fonction utilisable en tout-terrain. Un
saut produit un choc, mais le pilote repart : le deuxième critère l'écarte. Une
chute sans gravité fait bouger le téléphone pendant qu'on se relève : le
troisième l'écarte.

### 7.2 Compte à rebours

Les trois critères réunis déclenchent une alarme sonore, une vibration et un
compte à rebours plein écran. Sa durée est **réglable de 15 à 120 secondes**,
30 secondes par défaut. Une pression annule.

Sans annulation, l'alerte part sur les canaux choisis.

La détection complète est **désactivable** d'un seul interrupteur.

### 7.3 Les deux canaux

**Canal téléphone.** L'application envoie elle-même le SMS aux contacts
sélectionnés. L'envoi doit être réellement automatique : `url_launcher` ouvre
l'application de messagerie et exige une pression, ce qui ne convient pas à
quelqu'un d'inconscient. Un canal natif Android utilisant `SmsManager` est donc
écrit. La permission `SEND_SMS` est déjà déclarée dans le manifeste.

**Canal serveur.** Le hub alerte de son côté, y compris si le téléphone s'est
tu. Trois moyens :

| Moyen | Livré | Verrou |
|-------|-------|--------|
| E-mail | ✅ actif | aucun |
| SMS via passerelle | code écrit, inactif | abonnement |
| Appel vocal automatique | code écrit, inactif | abonnement |

L'appel vocal est le seul moyen de réellement faire sonner le téléphone d'un
proche sans intervention humaine. Android l'interdit depuis l'application ;
seule une passerelle côté serveur peut le faire.

L'utilisateur choisit ses canaux dans l'application : téléphone seul, serveur
seul, ou les deux.

### 7.4 Verrou d'abonnement

Un service dédié répond à une seule question : *ce canal est-il déverrouillé ?*
Il renvoie systématiquement « non » pour le SMS et l'appel vocal tant
qu'aucun système d'abonnement n'existe.

L'interface affiche ces deux options **grisées**, accompagnées d'une mention
« Abonnement — bientôt ». Elles sont visibles, jamais silencieusement absentes.

Brancher l'abonnement plus tard consistera à changer la réponse de ce service,
pas à restructurer la chaîne d'alerte. C'est la raison d'être de cette
abstraction dès maintenant.

## 8. Lot D — Communauté

`GroupProvider.maxMembers` passe de 10 à **20**.

`FirebaseGroupService` est supprimé et remplacé par un service parlant au hub,
avec les mêmes responsabilités : créer ou rejoindre une session, diffuser sa
position, recevoir celle des autres, poser un point de ralliement. Cette fois
`GroupProvider` l'appelle réellement.

`firebase_core`, `firebase_database` et `firebase_auth` sont retirés de
`pubspec.yaml`, l'initialisation disparaît de `main.dart` et
`lib/config/firebase_options.dart` est supprimé.

Sur la carte, chaque pair apparaît comme un marqueur coloré portant son prénom
et sa vitesse. Un marqueur dont la position dépasse 30 secondes est estompé,
et retiré au-delà de 2 minutes : mieux vaut afficher l'absence d'information
qu'une position fausse.

L'extinction du groupe purge tout, immédiatement.

## 9. Lot E — Auto-réponse et partage de position

Aucune dépendance au serveur. Livré en premier.

### 9.1 Auto-réponse aux appels

Quand une personne de confiance appelle pendant que le pilote roule, le
téléphone répond seul par SMS.

Deux garde-fous encadrent la fonction :

- Elle ne s'active que si un **enregistrement est en cours ou le mode Solo est
  actif**. Téléphone posé sur une table, elle dort.
- Seuls les **contacts de confiance** la déclenchent par défaut. Sans ce filtre,
  la position GPS partirait vers des numéros inconnus. Un réglage permet de
  l'étendre à tous les appelants, désactivé par défaut.

Les numéros sont comparés sur leurs **9 derniers chiffres**, ce qui rend
équivalentes les écritures `+33 6 12 34 56 78` et `06 12 34 56 78`.

La détection d'appel entrant est écrite en Kotlin. Elle demande l'ajout de
`READ_PHONE_STATE` au manifeste ; `SEND_SMS` y figure déjà.

### 9.2 Bandeau de réponses rapides

Pendant l'appel, un bandeau propose d'envoyer une réponse préconfigurée d'une
pression. Il est réalisé par une **notification prioritaire à boutons
d'action** : aucune permission spéciale, fonctionne sur tous les téléphones.
Android n'affiche que **trois boutons**, ce qui borne le bandeau à trois
réponses.

L'alternative — une fenêtre par-dessus l'écran d'appel via
`SYSTEM_ALERT_WINDOW` — permettrait des boutons bien plus gros, donc plus
utilisables avec des gants. Elle est écartée pour l'instant : la permission
doit être accordée à la main et les surcouches Xiaomi et Samsung la révoquent
fréquemment. La bascule reste possible si les boutons se révèlent trop petits à
l'usage.

Réponses par défaut, toutes modifiables, chacune avec son propre interrupteur
« joindre ma position » :

| Réponse | Position jointe |
|---------|-----------------|
| « Je roule, je ne peux pas répondre » | non |
| « Je roule, je suis ici » | oui |
| « Tout va bien, j'arrive » | non |

### 9.3 Envoi manuel de position

Un onglet « Envoyer ma position » envoie au contact choisi les coordonnées et
le lien Google Maps. Il répond au cas où la personne de confiance n'ouvre pas
la page web : elle reçoit malgré tout un point à coller dans Google Maps et
sait que tout va bien.

`LocationService` fournit déjà `sosText`, `googleMapsUrl` et `sosMessage` :
c'est de la réutilisation.

## 10. Réglages ajoutés

| Réglage | Défaut | Lot |
|---------|--------|-----|
| Détection de chute | activée | C |
| Durée du compte à rebours | 30 s (15–120) | C |
| Canal d'alerte téléphone | activé | C |
| Canal d'alerte serveur | activé | C |
| Alerte par SMS de passerelle | **verrouillé** | C |
| Alerte par appel vocal | **verrouillé** | C |
| Silence avant alerte homme mort | 15 min | C |
| Immobilité avant alerte | 30 min | C |
| Auto-réponse SMS aux appels | activée | E |
| Joindre ma position à l'auto-réponse | activée | E |
| Répondre à tous les appelants | **désactivé** | E |
| Textes des trois réponses rapides | valeurs par défaut du §9.2 | E |

Tous suivent le format existant de `SettingsProvider` : une clé
`SharedPreferences`, un accesseur, un mutateur.

## 11. Dépendances

**Application** — aucune nouvelle dépendance Flutter. `http`,
`flutter_foreground_task`, `sensors_plus`, `geolocator`, `url_launcher`,
`permission_handler` et `shared_preferences` sont déjà présents. Le code natif
ajouté est écrit directement en Kotlin.

Trois dépendances sont **retirées** : `firebase_core`, `firebase_database`,
`firebase_auth`.

**Serveur** — Node.js, Express, `better-sqlite3`, un client SMTP pour
l'e-mail. La passerelle SMS et vocale n'est intégrée qu'au moment de
l'abonnement.

**Manifeste Android** — ajout de `READ_PHONE_STATE`.

## 12. Contraintes et risques

| Risque | Traitement |
|--------|-----------|
| Localisation bridée en arrière-plan par Android | Service de premier plan avec notification permanente, déjà en place depuis le lot 1 |
| Action de notification sur écran verrouillé | Android peut exiger un déverrouillage selon le modèle. Non garanti ; à vérifier sur le téléphone cible à la livraison |
| Faux positifs de détection de chute | Trois critères successifs, seuil calé par calibration, compte à rebours annulable, fonction désactivable |
| Consommation de batterie | Cadence de 3 à 5 s, envoi par lots, aucune connexion permanente |
| `SEND_SMS` refusée par Google Play | Sans effet : distribution par APK GitHub. À reconsidérer si le Play Store devient une cible |
| Position des pairs = donnée personnelle | Purge immédiate à la clôture, plafond de 500 points, aucun compte, `watch_token` non indexé |
| Panne du hub | Le canal téléphone reste opérationnel ; il ne dépend d'aucun serveur |
| Régression sur le streaming | Aucun fichier du streaming n'est touché ; port, domaine, certificat, dépôt et composition Docker distincts |

## 13. Hors périmètre

- Le système d'abonnement lui-même. Seul le verrou est posé.
- L'intégration effective d'une passerelle SMS ou vocale.
- iOS. L'auto-réponse aux appels y est impossible et le projet n'a pas de
  dossier `ios`.
- Le partage de traces GPX entre membres du groupe.
- Un compagnon PC ou web au-delà de la page de suivi.

## 14. Critères de réussite

1. Un numéro de personne de confiance peut être saisi et survit au redémarrage
   de l'application.
2. La personne de confiance ouvre un lien reçu par SMS et voit la moto se
   déplacer sur un fond de carte, sans installer d'application ni créer de
   compte.
3. Une chute simulée réunissant les trois critères déclenche le compte à
   rebours, et l'alerte part si personne n'annule.
4. Le compte à rebours annulé n'envoie rien.
5. Le silence prolongé d'un téléphone en mode Solo déclenche l'alerte serveur,
   téléphone éteint.
6. Vingt appareils partagent leur position et se voient mutuellement sur la
   carte.
7. L'extinction du groupe efface immédiatement toutes les positions du serveur.
8. Un appel d'un contact de confiance pendant une sortie déclenche l'auto-
   réponse SMS, et le bandeau permet d'envoyer une réponse d'une pression.
9. Les options SMS de passerelle et appel vocal sont visibles, grisées, et
   n'envoient rien.
10. Le service de streaming `drone31` fonctionne à l'identique après le
    déploiement du hub.
