# État du projet — synthèse du 4 septembre 2026

Ce document existe parce que **deux sessions Claude Code ont travaillé en
parallèle** sur ce projet le 3 et 4 septembre, sans se voir. Il sert à ce
qu'une nouvelle session (ou toi) reparte avec le tableau complet plutôt que de
redécouvrir tout ça à la main.

## Les deux dépôts

| Dépôt | Rôle |
|---|---|
| `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto_offroad/` | L'application Flutter (Android) |
| `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server/` | Le serveur Node/Express/SQLite du suivi de position, sur le Hetzner |

Le serveur de streaming (`drone31-server`) est un **troisième** dépôt, sans
rapport, sur le **même Hetzner** (`ssh drone31`) mais isolé (autre port, autre
domaine, autre conteneur).

## Ce qui est fait et tourne en production

**Hub de positions (lot A)** — déployé, sain :
- Code : `moto-tracker-server`, GitHub `barbarescomarc/moto-tracker-server` (privé)
- Prod : `https://motooffroad.duckdns.org`, `/root/moto-tracker` sur le serveur,
  conteneur `node:18` en boucle locale port 3100, nginx + Let's Encrypt
- Santé : `GET /healthz` → `{"ok":true}` (vérifié à l'instant)
- Déployer : `./deploy.sh "message"` depuis le dépôt local (push + pull +
  redémarrage du conteneur sur le serveur)
- Tests : **jamais `npm test` directement sur ce Mac** (Xcode CLT cassés,
  aucun addon natif ne compile — voir mémoire `mac-xcode-clt-broken`). Toujours
  via Docker : `docker run --rm -v "<dépôt>:/app" -w /app node:18 sh -c "npm install && npm test"`

**Suivi Solo (lot B)** — câblé côté app :
- `SoloProvider` crée une vraie session sur le hub (plus de token factice)
- Envoi de position démarré/arrêté avec l'activation du mode Solo
- Lien de suivi partagé par SMS depuis l'écran Solo
- Client HTTP tolérant aux coupures réseau, tamponne et renvoie
  (`lib/services/tracker_api_client.dart`, `PositionUplinkService`)

**Communauté (lot D)** — câblé côté app :
- Firebase entièrement retiré (dépendances, init dans `main.dart`)
- `GroupProvider` crée/rejoint une vraie session sur le hub, jusqu'à 20 pilotes
- Positions des pairs reçues et affichées sur la carte, avec estompage et
  expiration des marqueurs anciens
- Point de ralliement partagé

**Icône et écran de démarrage** — refaits (par l'autre session, remplace ma
propre tentative de ce jour) : un skull illustré dans un casque motocross avec
pistons croisés, icône adaptative Android correcte (`mipmap-anydpi-v26/`),
splash screen assorti. Commit `4e996d0`.

**140 → 172 tests** côté app depuis mon dernier commit connu (`fd2852f`),
tous au vert.

## Ce qui est en suspens, à ne pas écraser par erreur

1. **Un commit serveur non déployé** — `e357bef` (« e-mail pilote/contacts et
   délai homme-mort configurable ») est validé en local dans
   `moto-tracker-server` mais **jamais poussé sur GitHub, jamais déployé**. La
   prod tourne encore sur `45263e8`.
2. **Du travail non commité, dans ce même dépôt** — `src/mailer.js` et
   `test/mailer.test.js` existent sur le disque, jamais validés dans git.
   `package.json`/`package-lock.json` sont modifiés aussi (dépendance
   `nodemailer` ajoutée). Ça ressemble à une implémentation en cours du
   canal e-mail du lot C (voir plus bas) — **vérifier si une session tourne
   encore dessus avant d'y toucher.**

## Ce qui est planifié mais pas codé

**Lot C — Chute, chaîne d'alerte et newsletter.** Spec et plan écrits
(`docs/superpowers/specs/2026-09-03-suivi-securite-solo-communaute.md`,
`docs/superpowers/plans/2026-09-03-lot-c-chute-alerte-newsletter.md`), rien
implémenté. Dix tâches :
- Côté serveur : schéma (e-mail pilote/contacts, délai homme-mort réglable),
  module mailer (Brevo via nodemailer), branchement dans la surveillance
  homme-mort/immobilité, endpoint d'alerte chute/SOS, routes newsletter +
  table `subscriber`, opt-in sur la page de suivi
- Côté app : champ e-mail sur `TrustedContact`, réglage du délai homme-mort
  dans `SoloScreen`

Le `src/mailer.js` non commité correspond très probablement à la Tâche 2 de
ce plan, déjà entamée.

**Guidage GPS (offroad, route, trace GPX).** Spec et plan écrits
(`docs/superpowers/specs/2026-09-03-guidage-gps-design.md`,
`docs/superpowers/plans/2026-09-03-guidage-gps.md`), rien implémenté. Dix-huit
tâches : service de routage via OpenRouteService, dérivation depuis une trace
GPX, guidage vocal, favoris, bandeau d'instruction, appui long sur la carte,
service d'arrière-plan partagé avec l'enregistrement.

**Lot E — Auto-réponse et partage de position.** C'est le lot que *cette*
session a construit et fusionné en premier (avant la découverte de la session
parallèle) : menu radial d'appel, auto-réponse SMS, envoi manuel de position.
Terminé, fusionné dans `main`.

## Ce que cette session-ci a fait, en plus du lot E

Après la fusion du lot E, sans savoir qu'une autre session avançait sur le
hub, cette session a fait une passe d'interface sur l'écran carte :

- Menu radial sur les commandes d'enregistrement (Pause/Reprendre, Arrêter)
- Menu radial sur le bouton Recentrer (Recherche d'adresse, Météo, Mode Solo)
- Barre de navigation auto-masquée au déplacement de la carte, réglable
- Correction du chevauchement radar/plein écran, retrait des boutons zoom
- Entrée « Mode Solo Sécurisé » ajoutée aux réglages (le seul chemin d'accès
  à l'écran manquait jusque-là)
- Style visuel unifié façon verre dépoli sur les contrôles flottants, la
  barre de navigation et les sections de réglages
- Correctif du radar météo RainViewer (URL dynamique + plafond de zoom à 7)
- Une tentative d'icône (skull + casque + pistons en SVG maison) —
  **remplacée depuis par la version de l'autre session**, plus aboutie ;
  aucune trace n'en reste sur le disque

Commit correspondant : `fd2852f` sur `main`, poussé sur GitHub. La CI a
compilé avec succès mais **n'a rien publié** : le numéro de version dans
`pubspec.yaml` n'a pas changé, et le système ne publie une nouvelle version
téléchargeable que si ce numéro change.

## Pièges connus, à ne pas réapprendre à la dure

- **Ne jamais lancer `npm test` directement sur ce Mac** pour le serveur —
  Xcode CLT cassés, tout addon natif échoue. Toujours via Docker (commande
  ci-dessus).
- **RainViewer plafonne son zoom à 7** — `maxNativeZoom: 7` obligatoire sur
  la couche radar, sinon erreur « zoom level not supported » en zoomant.
- **Le lanceur Android (surtout Samsung One UI) découpe les icônes en
  cercle** — toute icône doit laisser une marge de sécurité, sinon le
  découpage mange le haut/bas du dessin.
- **`nginx/moto-tracker.conf` dans le dépôt n'est qu'une copie de
  référence** — modifier le fichier réel impose de le recopier à la main
  dans `/etc/nginx/sites-available/` sur le serveur, puis `nginx -t` et
  reload.
- Le lien de téléchargement public de l'app
  (`releases/latest/download/moto-offroad.apk`) ne se met à jour que si le
  numéro de version dans `pubspec.yaml` change avant de pousser.

## Prochaines étapes possibles

1. Vérifier si une session tourne encore sur `src/mailer.js` avant d'y
   toucher ; sinon, terminer/committer ce travail ou repartir du plan du
   lot C proprement.
2. Décider si le commit serveur `e357bef` doit être poussé et déployé tel
   quel, ou attendre qu'il soit regroupé avec la suite du lot C.
3. Implémenter le lot C (chute, alerte, newsletter) — spec et plan déjà
   écrits, prêts à exécuter.
4. Implémenter le guidage GPS — spec et plan déjà écrits, prêts à exécuter.
5. Monter le numéro de version de l'app et pousser, pour publier enfin une
   release téléchargeable incluant tout ce travail.
