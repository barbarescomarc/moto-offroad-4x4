# Lot 1 — Stockage local et enregistrement de traces

Design validé le 2 septembre 2026.

## 1. Contexte

L'application sait aujourd'hui importer une trace GPX et l'afficher, mais elle
ne sait pas enregistrer une sortie. Trois manques rendent ce lot nécessaire :

- Aucun enregistrement GPS. `GpxService.exportToGpx()` existe et n'est appelé
  nulle part.
- Aucune persistance. `sqflite` est déclaré dans `pubspec.yaml` mais jamais
  utilisé. Les traces importées et les contacts de confiance disparaissent à la
  fermeture de l'application.
- `WakelockPlus.enable()` est appelé sans condition dans `main.dart:49` :
  l'écran ne s'éteint jamais, quel que soit l'écran affiché.

Ce lot est le premier d'une feuille de route en six lots. Il pose les briques
que les suivants réutilisent : le service d'arrière-plan, l'accéléromètre et la
base de données.

## 2. Feuille de route

| Lot | Contenu |
|-----|---------|
| **1** | Stockage local et enregistrement de traces *(ce document)* |
| 2 | Édition de traces : renommer, découper, supprimer des points, fusionner |
| 3 | Guidage sur trace : flèches activables, distance restante, alerte hors-trace, boussole |
| 4 | Sécurité SOS : détection de choc, immobilité réglable, appel annulable, contact d'urgence |
| 5 | Groupes temps réel : Firebase, durée de vie, point de rendez-vous, positions en opt-in |
| 6 | Companion PC/web |

Deux briques du lot 1 sont dimensionnées pour servir plus loin : le service
d'arrière-plan et l'accéléromètre seront réutilisés tels quels par la détection
de choc du lot 4.

## 3. Décisions de cadrage

| Sujet | Décision |
|-------|----------|
| Enregistrement écran éteint | Oui, via un service d'arrière-plan dédié |
| Écran maintenu allumé | Uniquement en guidage, carte affichée et suivi actif |
| Pause automatique | Vitesse sous seuil **et** absence de vibration |
| Pause manuelle | Conservée, simple appui |
| Arrêt de l'enregistrement | Appui long, pour éviter les arrêts accidentels avec des gants |
| Nommage | Automatique, modifiable ensuite depuis l'historique |
| Démarrage automatique | Proposé en option, désactivé par défaut |
| Récupération après plantage | Oui, non désactivable |
| Calibration des vibrations | Un seul jeu, refaisable, plus un seuil par défaut à l'installation |
| Altitude | Enregistrée en base, dénivelé **non affiché** dans ce lot |
| Traces importées | Sauvegardées dans les mêmes tables que les sorties enregistrées |
| Fusion de sorties | Reportée au lot 2 |
| Commande vocale SOS | Retirée du périmètre du projet |

La pause automatique combine deux conditions parce que la vitesse seule ne
suffit pas : en franchissement, on roule sous 2 km/h pendant plusieurs minutes.
Le téléphone vibre alors, ce qui distingue ce cas d'un arrêt réel.

L'altitude est stockée sans être exploitée afin que le dénivelé puisse être
calculé plus tard sur les sorties déjà enregistrées. Ne pas la stocker aurait
été irréversible.

## 4. Architecture du service d'enregistrement

Cinq pièces, une responsabilité chacune. Le découpage vise à rendre la machine
à états testable sans matériel : l'enregistreur ne reçoit que deux flux et
n'écrit rien lui-même.

### 4.1 Capteur de vibration *(nouveau)*

Écoute l'accéléromètre via `sensors_plus` et expose un unique niveau de secousse
lissé sur une fenêtre glissante de 2 secondes.

Il travaille sur l'**écart-type** de la magnitude, pas sur la magnitude brute :
la gravité vaut en permanence environ 9,8 et écraserait le signal utile.

### 4.2 Source GPS *(existante)*

`LocationService` est conservé sans modification : `LocationAccuracy.bestForNavigation`,
`distanceFilter: 5` (`location_service.dart:88-90`).

### 4.3 Enregistreur *(nouveau)*

La machine à états. Reçoit les positions et le niveau de vibration, tient l'état
courant — `idle`, `recording`, `paused` — et décide des transitions. Ne connaît
ni la base de données ni l'interface.

Les deux flux d'entrée sont injectés, ce qui permet de rejouer une sortie
fictive en test : trente minutes simulées, arrêt déjeuner, reprise, et l'on
vérifie que la pause s'est déclenchée au bon moment.

**Règle de pause automatique**

- Passage en pause : vitesse sous le seuil configuré (2 ou 5 km/h) **et**
  vibration sous le seuil calibré, de façon continue pendant **30 secondes**.
- Reprise : vitesse au-dessus du seuil configuré **plus 1 km/h**, immédiatement.

L'écart entre les deux seuils est une hystérésis délibérée. Avec un seuil
unique, une vitesse oscillant autour de la valeur ferait alterner les états en
boucle.

Si l'utilisateur coupe le moteur en plein franchissement, la pause se déclenche
au bout de 30 secondes. Le tracé n'est pas perdu : les points de part et
d'autre appartiennent à des segments différents mais restent enregistrés.

### 4.4 Dépôt de sorties *(nouveau)*

Seule pièce qui écrit en base. Écriture continue par lots : toutes les
5 secondes ou tous les 10 points, au premier des deux atteint. Aucune donnée
n'attend l'appui sur stop, ce qui rend la récupération après plantage possible.

### 4.5 Notification *(nouveau)*

Affiche l'état vivant de l'enregistrement — par exemple `12,4 km · 1 h 23 · en pause` —
et se met à jour toutes les quelques secondes. L'état de pause doit y être
explicite : la pause automatique agit sans l'utilisateur, qui doit pouvoir
vérifier sa décision sans déverrouiller le téléphone.

### 4.6 Calibration des vibrations

Procédure guidée en deux mesures de 10 secondes :

1. Moteur coupé, téléphone en place → niveau « immobile ».
2. Moteur au ralenti, moto à l'arrêt → niveau « moteur tournant ».

Le seuil est placé entre les deux mesures, plus près de la mesure basse : en cas
de doute, on continue d'enregistrer plutôt que de risquer de couper au milieu
d'un passage technique.

Les deux mesures et le seuil retenu sont conservés dans `SharedPreferences` et
affichés à l'utilisateur après la calibration, accompagnés d'un test en direct
permettant de vérifier que l'application le voit bien immobile.

Un seuil par défaut est fourni à l'installation pour que la pause automatique
fonctionne sans calibration préalable.

## 5. Modèle de données

Base `sqflite`, schéma versionné dès la version 1 avec mécanisme de migration :
les lots suivants ajouteront des colonnes et ne doivent pas imposer l'effacement
des sorties existantes.

### 5.1 Table des sorties

Champs : identifiant, nom, commentaire libre, date de début, date de fin,
origine (`recorded` ou `imported`), état (`recording` ou `finished`), et les
statistiques calculées une fois à l'arrêt : distance, temps total, temps en
mouvement, vitesse moyenne, vitesse maximale.

Les statistiques sont figées en base plutôt que recalculées à l'affichage.
Ouvrir une liste de cent sorties ne doit pas relire des millions de points.

### 5.2 Table des points

Champs : sortie de rattachement (indexée), rang, latitude, longitude, altitude,
vitesse, horodatage, **numéro de segment**.

Le numéro de segment est incrémenté à chaque pause. La carte dessine une
polyligne par segment et ne relie jamais deux segments entre eux. Sans cela, une
pause suivie d'un déplacement en véhicule afficherait un trait rectiligne à
travers la carte.

### 5.3 Unification des traces importées

Importer une trace GPX la sauvegarde dans ces mêmes tables, avec l'origine
`imported`. Trois conséquences :

- les traces importées survivent à la fermeture de l'application ;
- l'écran Sorties liste enregistrements et imports au même endroit ;
- l'éditeur du lot 2 fonctionnera d'emblée sur les deux, sans code
  supplémentaire.

`TraceModel` reste le modèle en mémoire utilisé pour l'affichage sur la carte.
Une conversion sortie → `TraceModel` fait le lien, et `TraceProvider` continue
de gérer la trace active sans modification de son interface.

### 5.4 Volume

À raison d'un point tous les 5 mètres, une sortie de 100 km représente environ
20 000 points, soit près de 2 Mo. Cent sorties de cette taille approchent
200 Mo.

Aucune compression n'est mise en place dans ce lot : le lot 2 a besoin d'accéder
aux points individuellement pour les éditer, et compresser maintenant
compliquerait ce travail sans besoin démontré. L'écran Sorties affiche l'espace
occupé pour rendre la question visible.

### 5.5 Export GPX

Réutilisation de `GpxService.exportToGpx()` (`gpx_service.dart:116`), déjà écrit
et jamais appelé. La sortie est convertie vers `TraceModel`, exportée, écrite
via `path_provider` puis proposée au menu de partage Android via `share_plus`.
Les deux dépendances sont déjà présentes.

Ce même fichier GPX sera le format consommé par le companion PC du lot 6.

### 5.6 Contacts de confiance

Les contacts gérés par `SoloProvider` sont aujourd'hui conservés en mémoire vive
et perdus à chaque fermeture. Ils sont désormais persistés. Correctif mineur
inclus dans ce lot parce qu'il s'agit d'une perte de données réelle.

## 6. Écrans

### 6.1 Carte

Un bouton REC dimensionné pour être atteint avec des gants. Une fois
l'enregistrement lancé, il laisse place à un bandeau compact affichant distance,
durée et vitesse, avec les commandes pause et arrêt.

- Arrêt : **appui long**. Un arrêt accidentel après trois heures de sortie n'est
  pas rattrapable.
- Pause manuelle : simple appui. Une erreur n'y coûte rien.
- L'état de pause change la couleur du bandeau et est mentionné explicitement.

**Extraction préalable** : `map_screen.dart` compte 792 lignes, le plus gros
fichier du projet. L'interface d'enregistrement est écrite dans son propre
fichier de widget plutôt qu'ajoutée à l'existant. Les lots 3 et 5 devront eux
aussi ajouter des éléments à cette carte — guidage, positions du groupe.

### 6.2 Onglet Sorties

L'onglet **Info** quitte la barre de navigation et devient une section de
l'écran Réglages. L'emplacement libéré accueille **Sorties**. La barre reste à
cinq onglets : Carte, Carbu, Sorties, Météo, Réglages.

Liste triée par date : nom, date, distance, durée, pastille d'origine.

Détail d'une sortie : la trace sur une carte, les statistiques, et les actions —
renommer, commenter, afficher sur la carte principale, exporter en GPX,
supprimer. La suppression demande confirmation.

### 6.3 Réglages

Nouvelle section « Enregistrement » :

- Pause automatique — activée ou désactivée
- Seuil de la pause automatique — 2 ou 5 km/h
- Nommage à l'arrêt — automatique ou demandé
- Proposer de démarrer l'enregistrement quand un roulage est détecté — désactivé par défaut
- Unités — kilomètres ou miles
- Maintien de l'écran allumé sur la carte — activé par défaut
- Bouton **Calibrer les vibrations**

Persistance via `SharedPreferences`, en suivant le motif déjà en place dans
`settings_provider.dart`.

La récupération après plantage et l'écriture au fil de l'eau ne sont pas
configurables : ce sont des filets de sécurité.

La page Info descend dans cet écran comme une simple section.

### 6.4 Maintien de l'écran

`WakelockPlus` n'est plus activé au démarrage. Il l'est uniquement lorsque
l'écran Carte est affiché **et** que le suivi de position est actif — l'usage
guidon. Partout ailleurs, l'écran s'éteint normalement. Un réglage permet de
désactiver ce maintien.

### 6.5 Récupération après plantage

Au lancement, si une sortie est restée à l'état `recording`, un bandeau non
bloquant propose de la reprendre, de la clôturer telle quelle, ou de la
supprimer.

### 6.6 Invitation à calibrer

Après le **premier** enregistrement terminé, une invitation à calibrer les
vibrations est affichée. Pas avant : tant que l'utilisateur n'a pas enregistré
une fois, la calibration n'a pas de sens pour lui.

## 7. Dépendances

Ajoutées :

- `flutter_foreground_task` — service d'arrière-plan avec notification pilotée
- `sensors_plus` — accéléromètre

Activée pour la première fois :

- `sqflite` — déjà déclaré dans `pubspec.yaml`, jamais utilisé

Déjà présentes et réutilisées : `geolocator`, `gpx`, `path_provider`,
`share_plus`, `shared_preferences`, `wakelock_plus`.

## 8. Contraintes et risques

**Constructeurs agressifs.** Xiaomi, Huawei, Oppo et certains Samsung
interrompent les services d'arrière-plan indépendamment de l'implémentation
choisie. Aucune solution logicielle n'y échappe. L'application détecte le cas et
affiche une aide générique expliquant le réglage d'optimisation batterie à
modifier. Aucune spécialisation par modèle dans ce lot.

**Marche après descente de moto.** Si l'utilisateur s'éloigne à pied avec le
téléphone, il dépasse le seuil de vitesse et le téléphone est secoué par ses
pas : les deux conditions de pause échouent et le trajet à pied est enregistré.
Distinguer la marche du roulage demanderait une analyse de signal hors périmètre.
Deux filets sont retenus : la pause manuelle, et une notification « Toujours en
balade ? » proposée après un quart d'heure sous 10 km/h. Le résidu se supprime
en deux gestes avec l'éditeur du lot 2.

**Portage iOS.** Le service d'arrière-plan et le maintien d'écran devront être
revus lors du portage iOS envisagé. Ce lot cible Android.

## 9. Hors périmètre

- Fusion et édition de traces → lot 2
- Guidage, flèches, boussole → lot 3
- Détection de choc et SOS automatique → lot 4
- Affichage du dénivelé → décision reportée, la donnée est stockée
- Compression ou archivage des sorties anciennes
- Profils de calibration multiples : un seul jeu, refaisable en vingt secondes

## 10. Critères de réussite

1. Un enregistrement lancé continue écran éteint et application quittée, et la
   notification affiche une distance qui progresse.
2. Un arrêt moteur coupé de plus de 30 secondes déclenche la pause automatique ;
   un franchissement sous 2 km/h moteur tournant ne la déclenche pas.
3. Une coupure brutale de l'application laisse une sortie récupérable au
   redémarrage, avec les points enregistrés jusqu'à quelques secondes avant la
   coupure.
4. Une sortie terminée apparaît dans l'onglet Sorties avec ses statistiques, et
   s'exporte en GPX relisible par l'import de l'application.
5. Une trace GPX importée survit au redémarrage de l'application.
6. L'écran s'éteint normalement sur les écrans Météo et Réglages.
7. La machine à états de l'enregistreur est couverte par des tests rejouant une
   sortie simulée, sans matériel.
