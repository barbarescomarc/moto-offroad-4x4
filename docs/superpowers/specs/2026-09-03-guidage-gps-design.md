# Guidage GPS (offroad, route, trace GPX)

Design validé le 3 septembre 2026.

## 1. Contexte

L'application affiche aujourd'hui une carte avec quatre fonds (Satellite,
Chemins, IGN Topo, Topo relief) et un switch **Offroad / Route**
(`MapProvider.navMode`, `lib/widgets/mode_switch.dart`) — mais ce switch est
purement visuel : il ne pilote aucun calcul d'itinéraire. Le mode GPX
(`TraceProvider`) affiche une trace importée et suit la progression du rider
dessus (portion parcourue en vert, restante en orange), sans jamais générer
d'instruction ni détecter un écart.

Aucun moteur de routage n'existe dans le code (`grep` sur routing/OSRM/
GraphHopper/Valhalla/directions : zéro résultat). Le besoin exprimé est un
vrai guidage GPS, activable :

- en **Offroad** : sur chemins de terre plutôt que sur route goudronnée
- en **Route** : sur route, avec des réglages fins (éviter autoroutes,
  péages, ferries…)
- sur une **trace GPX déjà importée** : soit juste l'afficher (comportement
  actuel), soit être guidé dessus — au choix de l'utilisateur à chaque
  démarrage de guidage

## 2. Relation avec l'existant

- **`NavMode`** (`lib/providers/map_provider.dart:54`) devient la source du
  profil de routage en plus de son rôle actuel de sélection de fond de
  carte : `cycling-mountain` en Offroad, `driving-car` en Route.
- **`TraceProvider`** n'est pas modifié dans sa logique d'affichage. Le
  guidage GPX se branche dessus en lecture (`activeTrace`) pour dériver un
  itinéraire synthétique, sans toucher au suivi de progression existant.
- **Position d'un rider du groupe comme destination** dépend du hub de
  positions décrit dans `2026-09-03-suivi-securite-personne-de-confiance-design.md`
  (lots A et D). Tant que ce hub n'existe pas, `GroupProvider.members` ne
  contient que des entrées locales non connectées. Ce document **prépare le
  point d'entrée** (menu présent, désactivé) sans en dépendre pour le reste.
- **`RideRecordingService`** (`lib/services/ride_recording_service.dart`) est
  étendu pour partager son service de premier plan avec le guidage, au lieu
  d'être dupliqué.

## 3. Décisions de cadrage

| Sujet | Décision |
|-------|----------|
| Moteur de routage | Service en ligne gratuit — OpenRouteService (aucun serveur à gérer) |
| Profil Offroad | `cycling-mountain` (le plus proche des chemins de terre chez ORS) |
| Profil Route | `driving-car` |
| Réglages Route | Fins : cases indépendantes éviter autoroutes / péages / ferries, persistées dans `SettingsProvider` |
| Guidage sur trace GPX | Les deux modes coexistent, choisis par l'utilisateur à chaque démarrage : alerte de déviation, ou virage par virage dérivé de la trace |
| Annonces | Voix (TTS français) + visuel, son mutable indépendamment |
| Arrière-plan | Doit continuer écran éteint / app en arrière-plan, comme l'enregistrement de sortie |
| Sources de destination | Recherche d'adresse, appui long sur la carte, favoris, position d'un rider du groupe (préparé mais inactif tant que le hub n'existe pas) |
| Plateforme | Android uniquement (cohérent avec le reste du projet) |

## 4. Architecture & composants

Nouveaux fichiers :

| Fichier | Rôle |
|---------|------|
| `lib/models/route_result.dart` | `RouteResult` (polyligne + étapes + distance/durée totales) et `RouteStep` (instruction, distance, type de manœuvre, position) — contrat commun, indépendant de la source |
| `lib/services/routing_service.dart` | Appelle l'API Directions d'OpenRouteService, `http.Client?` injectable (même convention que `weather_service.dart`), parse la réponse en `RouteResult` |
| `lib/services/gpx_route_deriver.dart` | Fonction pure : `TraceModel` → `RouteResult` synthétique. Sans réseau. |
| `lib/providers/guidance_provider.dart` | État du guidage : route active, étape courante, distance/ETA, déviation, mode, mute |
| `lib/services/guidance_voice_service.dart` | Fine couche autour de `flutter_tts`, voix FR, mutable |
| `lib/services/background_service_coordinator.dart` | Coordonne les clients du service de premier plan partagé (voir §7) |
| `lib/providers/favorites_provider.dart` | CRUD favoris, persistance `shared_preferences` (même pattern que `QuickReplyProvider`) |
| `lib/widgets/guidance_banner.dart` | Bandeau d'instruction (icône, texte, distance) + footer (distance restante, ETA, mute, arrêter) |
| `lib/screens/favorites/favorites_screen.dart` | Liste des favoris |
| `lib/config/api_keys.dart` | + clé OpenRouteService (gratuite, openrouteservice.org), même convention que les clés météo déjà présentes |

## 5. Déclenchement du guidage

Quatre points d'entrée, tous menant au même flux (`GuidanceProvider.startToDestination`) :

1. Barre de recherche existante → résultat → bouton **Guider**
2. Appui long sur la carte → feuille contextuelle **Guider ici / Ajouter aux favoris**
3. Écran Favoris → **Guider**
4. Position d'un rider du groupe (menu présent, grisé + message explicatif
   tant que `GroupProvider` n'est pas connecté au hub)

Cas particulier — trace GPX active : un bouton **Démarrer le guidage** sur
l'écran de trace ouvre le choix *Alerte de déviation* / *Guidage virage par
virage*, puis appelle `GuidanceProvider.startOnTrace(mode)`. Ces deux modes
sont **entièrement hors-ligne** (`gpx_route_deriver.dart` ne fait aucun appel
réseau) — un vrai atout puisque le GPX sert justement là où le réseau
manque.

## 6. Pendant le guidage

Le service d'arrière-plan démarre (voir §7). `LocationService` alimente
`GuidanceProvider` à chaque position :

- **Avancement d'étape** : quand la position entre dans le rayon d'arrivée
  (~30 m) de la prochaine manœuvre, l'étape suivante devient active.
  Pré-annonces vocales échelonnées (~300 m, ~100 m, « maintenant »).
- **Détection de déviation** : distance perpendiculaire de la position à la
  polyligne active, autour du segment courant. Seuil plus large en Offroad
  (chemins moins précis dans les données) qu'en Route.
  - Mode destination : recalcul silencieux via `RoutingService`, throttlé à
    une tentative par 20 s pour ne pas spammer l'API.
  - Mode GPX-alerte : annonce + indication de direction pour rejoindre la
    trace, pas de recalcul (la trace ne change pas).
- **Arrivée** : dernière étape atteinte (destination) ou dernier point de la
  trace atteint (GPX) → arrêt automatique + annonce « Destination atteinte ».
- **`GuidanceBanner`** affiche l'instruction courante, la distance, et un
  footer distance restante / ETA / bouton mute / bouton Arrêter.

## 7. Service d'arrière-plan partagé

`RideRecordingService` encapsule déjà le singleton `FlutterForegroundTask`
(un seul service de premier plan pour toute l'app). `background_service_
coordinator.dart` introduit une petite couche par-dessus :

- `RideRecordingService` et un nouveau `GuidanceBackgroundClient` deviennent
  chacun un client nommé du coordinateur.
- Le coordinateur démarre le service au premier client actif, l'arrête au
  retrait du dernier.
- Le texte de la notification reflète les clients actifs (« Enregistrement
  en cours » et/ou « Guidage actif »).
- Aucun changement d'API pour `RecordingProvider` — le guidage peut tourner
  sans enregistrer de sortie, et inversement.

## 8. Gestion d'erreurs

| Situation | Comportement |
|-----------|--------------|
| Pas de réseau au calcul d'itinéraire | Bandeau d'erreur, guidage non démarré, pas de plantage |
| Pas de réseau pendant un recalcul (déviation) | Dernier itinéraire connu conservé, nouvelle tentative throttlée |
| Quota ORS dépassé (gratuit : 2000 req/jour) | Bandeau générique « Service de guidage indisponible » |
| Signal GPS perdu en cours de guidage | Guidage figé sur la dernière instruction + indicateur « Signal GPS perdu », reprise automatique au retour du fix (même logique que `LocationService.lastSnapshot` déjà utilisé par l'auto-réponse) |
| Destination = rider du groupe, hub absent | Entrée désactivée avec message — pas une erreur runtime |

## 9. Réglages ajoutés

Dans l'écran Réglages existant :

- Évitements Route : autoroutes / péages / ferries (cases indépendantes)
- Voix du guidage : activée / muette (par défaut activée)

## 10. Dépendances

- `flutter_tts` — synthèse vocale française, gratuite, pas de clé API
- Clé API OpenRouteService — gratuite, à créer par l'utilisateur sur
  openrouteservice.org (2000 requêtes/jour, 40/minute), suit le pattern déjà
  en place dans `lib/config/api_keys.dart` (fichier gitignored, guide en
  commentaire)

## 11. Tests

Conventions déjà en place dans le projet : `package:http/testing.dart`
`MockClient`, providers testés avec dépendances injectées (voir
`test/services/update_checker_test.dart`).

- `RoutingService` : parsing de la réponse ORS, gestion des erreurs HTTP/réseau
- `gpx_route_deriver` : fonction pure — ligne droite = aucun virage détecté ;
  tracé en L = virage à 90° classé gauche/droite ; bruit GPS ne crée pas de
  faux virages
- Distance point-polyligne (déviation) : sur le segment = 0 m, décalage
  perpendiculaire = distance attendue, au-delà des extrémités = distance au
  point le plus proche
- `GuidanceProvider` : avancement d'étape, détection d'arrivée, changement de
  mode, mute, avec `LocationService`/`RoutingService` factices
- `background_service_coordinator` : démarrage/arrêt selon les clients actifs,
  composition du texte de notification
- **Test manuel obligatoire sur appareil réel** avant tout déploiement — la
  voix en arrière-plan écran éteint ne se vérifie pas par un test automatisé

## 12. Hors périmètre

- Guidage vers la position d'un rider du groupe tant que le hub de positions
  (lot A/D de `2026-09-03-suivi-securite-personne-de-confiance-design.md`)
  n'est pas construit — seul le point d'entrée est préparé
- Moteur de routage auto-hébergé ou 100% hors-ligne pour le mode destination
  (écarté à la question de cadrage §3 — limite connue : `cycling-mountain`
  n'est qu'une approximation des chemins de terre, pas un vrai profil
  4x4/moto)
- iOS (le projet n'a pas de dossier `ios`)

## 13. Critères de réussite

- Depuis chacune des 4 sources de destination (sauf rider du groupe, hors
  périmètre), un guidage démarre et annonce des instructions cohérentes
- Le profil de routage change effectivement avec le switch Offroad/Route
- Une trace GPX peut être suivie en mode alerte ou virage par virage, sans
  réseau
- Le guidage vocal continue écran éteint, sans dupliquer la notification de
  l'enregistrement de sortie quand les deux tournent ensemble
- Aucune régression sur l'enregistrement de sortie existant
