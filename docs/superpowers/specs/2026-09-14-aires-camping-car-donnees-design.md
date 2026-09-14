# Aires de camping-car — sources de données et architecture

État au 2026-09-14. Document de décision pour le mode camping-car de GO FREE.

## 1. Le besoin

Au clic sur une aire, la fiche doit afficher :

| Élément | Statut |
|---|---|
| Nom de l'aire | réalisable, ~100 % après fusion |
| Naviguer vers | **déjà en place** (`map_screen.dart:2137`) |
| Services (eau, vidange, électricité, WC, douche) | réalisable, couverture partielle |
| Prix | réalisable, couverture faible |
| Nombre de places | réalisable, couverture faible |
| Hauteur / longueur limite | **le trou noir — quasi inexistant en base** |

## 2. Catalogue des jeux de données

### Exploitables

| Source | Zone | Volume | Licence | Accès | Verdict |
|---|---|---|---|---|---|
| **OpenStreetMap** `tourism=caravan_site` | Monde / Europe | **36 705** objets | ODbL (attribution obligatoire) | Overpass API, ou extraits Geofabrik par pays | **Socle.** Déjà branché (`poi.dart:99`) |
| **OpenStreetMap** `amenity=sanitary_dump_station` | Monde / Europe | **11 436** objets | ODbL | idem | **Socle.** Déjà branché |
| **DATAtourisme** `dt:CamperVanArea` | France | national, offices de tourisme | Licence Ouverte / ODbL selon flux | API REST `api.datatourisme.fr` + flux quotidien | **Enrichissement FR.** Connecteur déjà écrit (`data_tourisme_service.dart`), il ne demande que le type `Camping` |

### Open data public français — patchwork

Pas de jeu national unique sur data.gouv.fr. Uniquement du régional /
départemental, la plupart en Opendatasoft avec API JSON/CSV :

- Pays de la Loire — <https://data.paysdelaloire.fr/explore/dataset/234400034_070-001_offre-touristique-aires-de-camping-car-rpdl/api/>
- Loire-Atlantique — <https://data.loire-atlantique.fr/explore/dataset/793866443_aires-de-camping-car-loire-atlantique/api/>
- Centre-Val de Loire — <https://data.centrevaldeloire.fr/explore/dataset/aires-de-camping-car-en-region-centre-val-de-loire/api/>
- Hérault — <https://www.herault-data.fr/explore/dataset/aires-de-camping-car/api/>
- CC Val2C, Tours Métropole, Orne, Cesson-Sévigné, Lisieux… (jeux communaux)
- Index data.gouv.fr — <https://www.data.gouv.fr/datasets/aires-de-campings-cars>

Ces données remontent en grande partie dans DATAtourisme via les SIT
départementaux. **Intégrer les 15+ portails un par un n'est pas rentable** :
15 schémas différents pour un gain marginal sur DATAtourisme.

### Non exploitables sans accord commercial

| Source | Volume | Pourquoi non |
|---|---|---|
| **park4night** | ~370 000 lieux, 100+ pays | Base propriétaire. L'endpoint `/api/places/around` répond sans clé mais **n'est pas une API publiée** : pas de licence, pas de CGU d'usage tiers, plafond ~100 résultats. L'utiliser dans une app publiée = hors CGU |
| **Campercontact** | ~16 000 aires, 38 pays | Propriétaire. Exports OV2/CSV pour usage GPS personnel |
| **Campingcar-Infos** | la plus grosse base francophone FR/Europe | Propriétaire, alimentée par des bénévoles. GPX gratuits, usage personnel, pas de redistribution |
| **i-campingcar.fr**, **serdef.fr** | FR/Europe, PDF + POI GPS mensuels | idem |
| **France Passion**, **CampingCarPark** | réseaux commerciaux FR | Aucun open data, modèle sur abonnement |

Les trois premières sont les meilleures bases du marché. La seule voie
légale est un partenariat négocié, pas l'aspiration.

## 3. Couverture réelle des champs — le point qui décide de tout

Répartition des tags sur les 36 705 `tourism=caravan_site` d'OSM
(source : taginfo, monde entier) :

| Tag OSM | Objets | Part |
|---|---|---|
| `name` | 27 376 | **75 %** |
| `fee` (payant oui/non) | 12 933 | 35 % |
| `power_supply` | 12 358 | 34 % |
| `sanitary_dump_station` | 10 992 | 30 % |
| `capacity` (**nombre de places**) | 7 922 | **22 %** |
| `internet_access` | 5 389 | 15 % |
| `toilets` | 4 955 | 13 % |
| `charge` (**prix**) | 4 263 | **12 %** |
| `opening_hours` | 2 881 | 8 % |
| `shower` | 2 706 | 7 % |
| `drinking_water` | 1 930 | 5 % |
| `maxheight` (**hauteur limite**) | hors du top 60 | **< 1,5 %** |

Conséquences à accepter dès la conception :

1. **Le prix et le nombre de places manqueront sur la majorité des aires.**
   La fiche doit afficher « non renseigné » proprement et proposer de
   compléter, sinon elle aura l'air cassée sur 4 aires sur 5.
2. **La hauteur limite de l'aire n'existe pratiquement nulle part.** Elle
   devra venir des utilisateurs. En attendant, la vraie protection est
   ailleurs et **elle est déjà en place** : le profil `driving-hgv` d'ORS
   reçoit hauteur, longueur et poids et écarte les ponts et barres trop bas
   sur tout le trajet (`routing_service.dart:123`).
3. DATAtourisme comble une partie du trou côté France : `rdfs:label`,
   description, services, `schema:priceSpecification`, capacité d'accueil,
   horaires — mais pas la hauteur non plus.

## 4. Dans l'app ou sur le serveur ? — **Sur le serveur**

Quatre raisons, dans l'ordre de poids :

1. **Overpass public n'est pas fiable en production.** Le constat est déjà
   écrit dans le code : « Overpass public est très irrégulier : la même
   requête rend 200 en cinq secondes ou 504 » (`fuel_poi_service.dart:46`).
   Un camping-cariste qui cherche une aire à 19 h le fait une fois ; s'il
   tombe sur un 504 il désinstalle.
2. **Il faut fusionner et dédoublonner.** OSM + DATAtourisme décrivent
   souvent la même aire à 30 m d'écart, avec des champs complémentaires.
   Ce rapprochement géographique ne peut pas se refaire sur le téléphone à
   chaque panoramique de carte.
3. **Les champs manquants devront être complétés par les utilisateurs.**
   Prix, places, hauteur : c'est de la contribution communautaire, donc de
   l'écriture. Une base embarquée en lecture seule ne peut rien en faire.
4. **Le volume tombe pile entre les deux.** ~48 000 points pour l'Europe,
   soit 5 à 10 Mo — trop lourd et trop périssable pour un asset figé dans
   l'APK (chaque correction imposerait une release), trop léger pour
   justifier autre chose que le serveur déjà en production.

### Architecture retenue

```
OSM (Geofabrik, hebdo)  ─┐
DATAtourisme (flux quotidien) ─┼─> ingestion + dédoublonnage ─> SQLite `aires`
contributions utilisateurs ─┘                                      │
                                                                   v
                                        moto-tracker-server : GET /aires?bbox=…
                                                                   │
                                                  app : cache SQLite local par région
```

- **Serveur** : `moto-tracker-server` (Node/SQLite, déjà en prod sur le
  Hetzner). Un cron hebdomadaire réingère OSM, un cron quotidien
  DATAtourisme. Aucune nouvelle infrastructure.
- **App** : télécharge un pack par région traversée et le garde en SQLite
  local. **Le hors-ligne n'est pas optionnel** — un camping-car cherche une
  aire précisément là où il n'y a pas de réseau.

### Schéma de table proposé

```sql
CREATE TABLE aires (
  id            TEXT PRIMARY KEY,   -- 'osm:node/123', 'dt:uuid'
  lat, lon      REAL NOT NULL,
  nom           TEXT,
  services      TEXT,               -- JSON : eau, vidange, elec, wc, douche, wifi
  prix_texte    TEXT,               -- '11 EUR/24h' tel quel
  prix_eur      REAL,               -- normalisé quand analysable
  places        INTEGER,
  max_hauteur_m REAL,
  max_longueur_m REAL,
  horaires      TEXT,
  telephone     TEXT,
  site          TEXT,
  sources       TEXT,               -- JSON : ids fusionnés, pour l'attribution ODbL
  maj           TEXT
);
```

L'attribution ODbL d'OpenStreetMap doit apparaître dans la fiche ou les
mentions légales de l'app — c'est une obligation de licence, pas une
politesse.

## 5. Mode guidage camping-car — déjà actif

Livré en 1.13.0, commits `a488d2c` et `8d2f5ef` :

- Réglages → véhicule **« Van / Camping-car »** (`settings_screen.dart:215`)
- le guidage bascule alors sur le profil ORS `driving-hgv`, **le seul qui
  accepte des contraintes de gabarit** (`map_screen.dart:2149`)
- hauteur, longueur et poids saisis dans les Réglages partent dans
  `profile_params.restrictions` à chaque calcul **et à chaque recalcul après
  déviation** (`routing_service.dart:123`, `guidance_provider.dart:126`)
- la piste hors-route est refusée au camping-car par défaut
  (`vehicle_kind.dart`, `roulesHorsRoute`), **sauf si le pilote ouvre
  « Autoriser les pistes »** dans Réglages → Mon véhicule : les fourgons 4x4
  existent, et leur refuser la piste reviendrait à décider à leur place.
  Contrepartie annoncée dans le réglage : sur piste, ORS n'accepte plus le
  profil poids lourd, donc plus les restrictions de hauteur et de tonnage
- couvert par `test/services/routing_gabarit_test.dart`

Il n'y a donc rien à activer côté code : **choisir le véhicule dans les
Réglages suffit**, les itinéraires sont déjà calculés en fonction de la
hauteur.

## 6. Contributions : ce que l'utilisateur renseigne sert à tout le monde

Décision du 2026-09-14. Les champs manquants ne sont pas un défaut à cacher,
c'est le point de départ de la base propriétaire de GO FREE.

### Principe

1. Un champ absent s'affiche **« Non renseigné · compléter »**, jamais un vide
   ni un tiret muet. C'est une invitation, pas un aveu.
2. Ce que le pilote saisit part au serveur, **est conservé**, et redescend
   dans le pack régional de tous les autres utilisateurs.
3. La base de contributions est la **valeur propriétaire du produit** : OSM et
   DATAtourisme sont à tout le monde, les relevés terrain des utilisateurs de
   GO FREE n'appartiennent qu'à GO FREE.

### Ce qu'on demande, par ordre d'intérêt

| Champ | Pourquoi lui |
|---|---|
| **Hauteur / longueur limite** | Inexistant partout ailleurs (< 1,5 % dans OSM). C'est *le* champ qui n'a aucun équivalent chez park4night ou Campercontact — celui qui peut faire la différence du produit |
| **Prix** | 12 % dans OSM, périmé vite, seul le terrain le tient à jour |
| **Nombre de places** | 22 % dans OSM |
| **Services** | Complète et corrige OSM |
| Photo, dernière visite | Preuve de fraîcheur |

### Table serveur

```sql
CREATE TABLE contributions (
  id        INTEGER PRIMARY KEY,
  aire_id   TEXT NOT NULL,       -- 'osm:node/123', 'dt:uuid'
  champ     TEXT NOT NULL,       -- 'max_hauteur_m', 'prix_eur', 'places'…
  valeur    TEXT NOT NULL,
  auteur    TEXT NOT NULL,       -- compte GO FREE
  vu_le     TEXT,                -- date de la visite, pas de la saisie
  cree_le   TEXT NOT NULL,
  etat      TEXT NOT NULL        -- 'proposee' | 'retenue' | 'ecartee'
);
```

**Rien n'est jamais écrasé** : la table est un journal. La valeur publiée est
calculée à partir de lui. Une contribution isolée passe en `retenue` si elle
est la première sur un champ vide ; une contribution qui contredit une valeur
déjà retenue attend un second avis concordant. Ça suffit à bloquer la bêtise
sans transformer le produit en outil de modération.

### Point juridique

La contribution est un relevé saisi par l'utilisateur, pas une donnée dérivée
d'OpenStreetMap : elle n'est pas contaminée par l'ODbL et reste la propriété
de GO FREE, même posée sur une aire dont la position vient d'OSM. Conserver
`sources` (les ids fusionnés) permet de garder cette frontière nette — et
c'est ce qui rend la base revendable ou reversable à OSM au choix.

Deux conditions à ne pas oublier : annoncer clairement dans les CGU que les
contributions deviennent partie de la base, et garder l'attribution ODbL pour
ce qui vient d'OSM.

## 7. Avancement

**Fait le 2026-09-14** — les aires DATAtourisme sont branchées :
`PoiCategory.aireCampingCar` interroge le type `CamperVanArea`
(`data_tourisme_service.dart`), et la feuille de recherche ne propose le
filtre « Aire camping-car » qu'aux camping-cars, coché d'office puisque c'est
leur recherche la plus utile. Les aires municipales françaises apparaissent
donc avec nom, adresse et contact, sans rien attendre du chantier serveur.

**Reste à faire**, dans l'ordre : table `aires` côté serveur → ingestion OSM
Europe → ingestion DATAtourisme → endpoint `bbox` → cache hors-ligne dans
l'app → fiche détaillée au clic (nom, services, prix, places, gabarit) →
contribution utilisateur sur les champs manquants (section 6).

À noter : tant que la fiche détaillée n'existe pas, les aires s'affichent avec
ce que rend l'API — nom, adresse, téléphone, site. Le prix, les places et la
hauteur limite viendront avec le serveur, seul endroit où les contributions
peuvent être écrites.
