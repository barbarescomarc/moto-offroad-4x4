# Lot 1 — Enregistrement de traces : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre d'enregistrer une sortie moto en arrière-plan, écran éteint, avec pause automatique intelligente, de la stocker localement et de l'exporter en GPX.

**Architecture:** Une machine à états pure (`RideRecorder`) reçoit deux flux injectés — positions GPS et niveau de vibration — et décide seule des transitions enregistrement/pause. Elle n'écrit rien et n'affiche rien, ce qui la rend testable sans matériel. Autour d'elle : un dépôt `sqflite` qui écrit par lots, un service d'arrière-plan `flutter_foreground_task` qui la fait tourner écran éteint, et des providers qui exposent son état à l'interface.

**Tech Stack:** Flutter 3.44 / Dart 3.12, sqflite, flutter_foreground_task, sensors_plus, geolocator, provider, go_router, shared_preferences.

**Spec:** `docs/superpowers/specs/2026-09-02-lot1-enregistrement-traces-design.md`

## Global Constraints

- Cible **Android uniquement**. Le portage iOS est hors périmètre.
- Toute la copie d'interface est en **français**.
- Le style du code suit l'existant : commentaires de section `// ── Titre ─────`, singletons `factory X() => _instance`, providers `ChangeNotifier`.
- **L'altitude est stockée mais aucun dénivelé n'est affiché.** Ne pas ajouter d'affichage de dénivelé, même si `TraceModel` sait le calculer.
- Un point GPS tous les **5 mètres** (`LocationAccuracy.bestForNavigation`, `distanceFilter: 5`) — réglage existant de `LocationService`, à ne pas modifier.
- Seuil de pause automatique configurable : **2 ou 5 km/h**. Reprise au seuil **+ 1 km/h**.
- Délai avant pause automatique : **30 secondes** de conditions réunies en continu.
- Écriture en base par lots : **toutes les 5 secondes ou tous les 10 points**, au premier atteint.
- Ne jamais relier deux segments différents lors d'un tracé sur carte.
- `flutter analyze` doit rester sans erreur après chaque tâche.

---

## Structure des fichiers

**Créés**

| Fichier | Responsabilité |
|---|---|
| `lib/models/ride.dart` | `Ride`, `RidePoint`, `RideStats`, `RideSource`, `RideStatus` |
| `lib/services/ride_database.dart` | Ouverture sqflite, schéma, migrations |
| `lib/services/ride_repository.dart` | Lecture/écriture des sorties et des points |
| `lib/services/vibration_meter.dart` | Fenêtre glissante d'accéléromètre → niveau de secousse |
| `lib/services/vibration_calibration.dart` | Mesures de calibration, seuil, persistance |
| `lib/services/ride_recorder.dart` | Machine à états enregistrement/pause |
| `lib/services/ride_recording_service.dart` | Service d'arrière-plan et notification |
| `lib/services/ride_export_service.dart` | Sortie → GPX → partage Android |
| `lib/providers/recording_provider.dart` | État d'enregistrement exposé à l'interface |
| `lib/providers/rides_provider.dart` | Liste et détail des sorties |
| `lib/widgets/recording_panel.dart` | Bouton REC et bandeau de statistiques |
| `lib/screens/rides/rides_screen.dart` | Onglet Sorties |
| `lib/screens/rides/ride_detail_screen.dart` | Détail d'une sortie |
| `lib/screens/settings/vibration_calibration_screen.dart` | Procédure de calibration guidée |

**Modifiés**

| Fichier | Modification |
|---|---|
| `pubspec.yaml` | Dépendances nouvelles |
| `lib/main.dart:49` | Suppression du wakelock inconditionnel, ajout des providers |
| `lib/app/router.dart` | Info sort de la barre, Sorties entre |
| `lib/screens/map/map_screen.dart` | Insertion du `RecordingPanel` |
| `lib/screens/settings/settings_screen.dart` | Section Enregistrement, section Info |
| `lib/providers/settings_provider.dart` | Préférences d'enregistrement |
| `lib/providers/solo_provider.dart` | Persistance des contacts |

---

## Task 1: Socle — dépendances et infrastructure de test

Le projet n'a **aucun dossier `test/`**. Cette tâche le crée et vérifie que la
chaîne de test tourne, sinon toutes les tâches suivantes sont bloquées.

**Files:**
- Modify: `pubspec.yaml`
- Create: `test/smoke_test.dart`

**Interfaces:**
- Consumes: rien
- Produces: `flutter test` opérationnel, `sqflite_common_ffi` disponible pour les tests de base de données

- [ ] **Step 1: Ajouter les dépendances**

Dans `pubspec.yaml`, section `dependencies`, après le bloc `# ── Stockage ──` :

```yaml
  # ── Enregistrement de sorties (lot 1) ───────────────
  flutter_foreground_task: ^8.10.0   # Service d'arrière-plan + notification
  sensors_plus: ^4.0.2               # Accéléromètre (pause auto, lot 4 choc)
```

Dans `dev_dependencies` :

```yaml
  sqflite_common_ffi: ^2.3.0   # sqflite hors appareil, pour les tests
```

- [ ] **Step 2: Installer**

Run: `flutter pub get`
Expected: `Got dependencies!` sans conflit de version.

Si un conflit apparaît sur `sensors_plus`, prendre la plus haute version
compatible avec Flutter 3.44 plutôt que de rétrograder une autre dépendance.

- [ ] **Step 3: Écrire le test de fumée**

Create `test/smoke_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la chaîne de test fonctionne', () {
    expect(1 + 1, 2);
  });
}
```

- [ ] **Step 4: Vérifier**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock test/smoke_test.dart
git commit -m "chore: dépendances d'enregistrement et infrastructure de test"
```

---

## Task 2: Modèle Ride et calcul des statistiques

Calcul pur, sans base ni capteur. C'est le socle de tout le reste.

**Files:**
- Create: `lib/models/ride.dart`
- Test: `test/models/ride_stats_test.dart`

**Interfaces:**
- Consumes: `latlong2` (`LatLng`, `Distance`)
- Produces:
  - `enum RideSource { recorded, imported }`
  - `enum RideStatus { recording, finished }`
  - `class RidePoint({required String rideId, required int seq, required int segment, required double lat, required double lng, double? altitude, required double speedKmh, required DateTime timestamp})`, getter `LatLng get position`
  - `class RideStats({required double distanceMeters, required Duration totalTime, required Duration movingTime, required double avgSpeedKmh, required double maxSpeedKmh})`, constante `RideStats.empty`, fabrique `RideStats.fromPoints(List<RidePoint>)`
  - `class Ride({required String id, required String name, String? notes, required DateTime startedAt, DateTime? endedAt, required RideSource source, required RideStatus status, required RideStats stats})`, méthode `Ride copyWith({...})`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/models/ride_stats_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';

RidePoint _pt(int seq, double lat, double lng, int secondsFromStart,
    {int segment = 0, double speed = 0}) {
  return RidePoint(
    rideId:    'r1',
    seq:       seq,
    segment:   segment,
    lat:       lat,
    lng:       lng,
    altitude:  120,
    speedKmh:  speed,
    timestamp: DateTime(2026, 9, 2, 10, 0, 0).add(Duration(seconds: secondsFromStart)),
  );
}

void main() {
  group('RideStats.fromPoints', () {
    test('liste vide donne des statistiques nulles', () {
      final stats = RideStats.fromPoints([]);
      expect(stats.distanceMeters, 0);
      expect(stats.movingTime, Duration.zero);
      expect(stats.avgSpeedKmh, 0);
    });

    test('un seul point donne des statistiques nulles', () {
      final stats = RideStats.fromPoints([_pt(0, 44.0, 6.0, 0)]);
      expect(stats.distanceMeters, 0);
    });

    test('deux points espacés de 100 m en 10 s', () {
      // 0.000899° de latitude ≈ 100 m
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
      ]);
      expect(stats.distanceMeters, closeTo(100, 2));
      expect(stats.totalTime, const Duration(seconds: 10));
      expect(stats.movingTime, const Duration(seconds: 10));
      expect(stats.avgSpeedKmh, closeTo(36, 1));
    });

    test('la distance ignore le saut entre deux segments', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
        // reprise 10 km plus loin, segment 1 : le saut ne doit pas compter
        _pt(2, 44.090000, 6.0, 3600, segment: 1),
        _pt(3, 44.090899, 6.0, 3610, segment: 1),
      ]);
      expect(stats.distanceMeters, closeTo(200, 4));
    });

    test('le temps en mouvement exclut la pause entre segments', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
        _pt(2, 44.090000, 6.0, 3600, segment: 1),
        _pt(3, 44.090899, 6.0, 3610, segment: 1),
      ]);
      expect(stats.movingTime, const Duration(seconds: 20));
      expect(stats.totalTime, const Duration(seconds: 3610));
    });

    test('la vitesse maximale est celle du point le plus rapide', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0, speed: 12),
        _pt(1, 44.000899, 6.0, 10, speed: 87.5),
        _pt(2, 44.001798, 6.0, 20, speed: 40),
      ]);
      expect(stats.maxSpeedKmh, 87.5);
    });
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/models/ride_stats_test.dart`
Expected: échec de compilation, `Target of URI doesn't exist: 'package:moto_offroad/models/ride.dart'`.

- [ ] **Step 3: Écrire le modèle**

Create `lib/models/ride.dart` :

```dart
import 'package:latlong2/latlong.dart';

// ── Origine d'une sortie ─────────────────────────────────────
enum RideSource { recorded, imported }

// ── État d'une sortie ────────────────────────────────────────
enum RideStatus { recording, finished }

// ── Point enregistré ─────────────────────────────────────────
class RidePoint {
  final String rideId;
  final int seq;
  final int segment;      // incrémenté à chaque reprise après pause
  final double lat;
  final double lng;
  final double? altitude; // mètres, stockée mais non exploitée (lot 1)
  final double speedKmh;
  final DateTime timestamp;

  const RidePoint({
    required this.rideId,
    required this.seq,
    required this.segment,
    required this.lat,
    required this.lng,
    this.altitude,
    required this.speedKmh,
    required this.timestamp,
  });

  LatLng get position => LatLng(lat, lng);
}

// ── Statistiques d'une sortie ────────────────────────────────
class RideStats {
  final double distanceMeters;
  final Duration totalTime;
  final Duration movingTime;
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  const RideStats({
    required this.distanceMeters,
    required this.totalTime,
    required this.movingTime,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
  });

  static const empty = RideStats(
    distanceMeters: 0,
    totalTime:      Duration.zero,
    movingTime:     Duration.zero,
    avgSpeedKmh:    0,
    maxSpeedKmh:    0,
  );

  double get distanceKm => distanceMeters / 1000;

  // Distance et temps ne cumulent qu'à l'intérieur d'un même segment :
  // relier deux segments compterait le trajet fait pendant la pause.
  factory RideStats.fromPoints(List<RidePoint> points) {
    if (points.length < 2) return empty;

    const calc = Distance();
    double distance = 0;
    int movingSeconds = 0;
    double maxSpeed = points.first.speedKmh;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      if (curr.speedKmh > maxSpeed) maxSpeed = curr.speedKmh;
      if (curr.segment != prev.segment) continue;
      distance += calc(prev.position, curr.position);
      movingSeconds += curr.timestamp.difference(prev.timestamp).inSeconds;
    }

    final moving = Duration(seconds: movingSeconds);
    final avg = movingSeconds == 0 ? 0.0 : (distance / movingSeconds) * 3.6;

    return RideStats(
      distanceMeters: distance,
      totalTime:      points.last.timestamp.difference(points.first.timestamp),
      movingTime:     moving,
      avgSpeedKmh:    avg,
      maxSpeedKmh:    maxSpeed,
    );
  }
}

// ── Sortie ───────────────────────────────────────────────────
class Ride {
  final String id;
  final String name;
  final String? notes;
  final DateTime startedAt;
  final DateTime? endedAt;
  final RideSource source;
  final RideStatus status;
  final RideStats stats;

  const Ride({
    required this.id,
    required this.name,
    this.notes,
    required this.startedAt,
    this.endedAt,
    required this.source,
    required this.status,
    required this.stats,
  });

  bool get isRecording => status == RideStatus.recording;

  Ride copyWith({
    String? name,
    String? notes,
    DateTime? endedAt,
    RideStatus? status,
    RideStats? stats,
  }) => Ride(
    id:        id,
    name:      name      ?? this.name,
    notes:     notes     ?? this.notes,
    startedAt: startedAt,
    endedAt:   endedAt   ?? this.endedAt,
    source:    source,
    status:    status    ?? this.status,
    stats:     stats     ?? this.stats,
  );
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/models/ride_stats_test.dart`
Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/ride.dart test/models/ride_stats_test.dart
git commit -m "feat: modèle Ride et calcul des statistiques de sortie"
```

---

## Task 3: Base de données et dépôt de sorties

**Files:**
- Create: `lib/services/ride_database.dart`
- Create: `lib/services/ride_repository.dart`
- Test: `test/services/ride_repository_test.dart`

**Interfaces:**
- Consumes: `Ride`, `RidePoint`, `RideStats`, `RideSource`, `RideStatus` (Task 2)
- Produces:
  - `RideDatabase.schemaVersion` (int), `RideDatabase.onCreate(Database, int)`, `RideDatabase.onUpgrade(Database, int, int)`, `Future<Database> RideDatabase.open()`, `Future<int> RideDatabase.sizeBytes()`
  - `RideRepository(Database db)` avec `insertRide(Ride)`, `updateRide(Ride)`, `deleteRide(String)`, `findRide(String)`, `listRides()`, `findUnfinishedRide()`, `appendPoints(List<RidePoint>)`, `pointsOf(String)`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/services/ride_repository_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';

Ride _ride(String id, {RideStatus status = RideStatus.finished, int day = 2}) => Ride(
  id:        id,
  name:      'Sortie $id',
  startedAt: DateTime(2026, 9, day, 10, 0),
  endedAt:   status == RideStatus.finished ? DateTime(2026, 9, day, 14, 0) : null,
  source:    RideSource.recorded,
  status:    status,
  stats:     RideStats.empty,
);

RidePoint _pt(String rideId, int seq, {int segment = 0}) => RidePoint(
  rideId:    rideId,
  seq:       seq,
  segment:   segment,
  lat:       44.0 + seq * 0.001,
  lng:       6.0,
  altitude:  300,
  speedKmh:  42,
  timestamp: DateTime(2026, 9, 2, 10, 0).add(Duration(seconds: seq)),
);

void main() {
  sqfliteFfiInit();

  late Database db;
  late RideRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version:  RideDatabase.schemaVersion,
        onCreate: RideDatabase.onCreate,
      ),
    );
    repo = RideRepository(db);
  });

  tearDown(() async => db.close());

  test('une sortie insérée se relit à l identique', () async {
    await repo.insertRide(_ride('r1'));
    final found = await repo.findRide('r1');
    expect(found, isNotNull);
    expect(found!.name, 'Sortie r1');
    expect(found.source, RideSource.recorded);
    expect(found.status, RideStatus.finished);
  });

  test('les points se relisent dans l ordre de leur rang', () async {
    await repo.insertRide(_ride('r1'));
    await repo.appendPoints([_pt('r1', 2), _pt('r1', 0), _pt('r1', 1)]);
    final points = await repo.pointsOf('r1');
    expect(points.map((p) => p.seq).toList(), [0, 1, 2]);
    expect(points.first.altitude, 300);
  });

  test('les sorties sont listées de la plus récente à la plus ancienne', () async {
    await repo.insertRide(_ride('vieille', day: 1));
    await repo.insertRide(_ride('recente', day: 5));
    final rides = await repo.listRides();
    expect(rides.map((r) => r.id).toList(), ['recente', 'vieille']);
  });

  test('une sortie restée en cours est retrouvée', () async {
    await repo.insertRide(_ride('finie'));
    await repo.insertRide(_ride('en_cours', status: RideStatus.recording));
    final open = await repo.findUnfinishedRide();
    expect(open?.id, 'en_cours');
  });

  test('sans sortie en cours, la recherche ne renvoie rien', () async {
    await repo.insertRide(_ride('finie'));
    expect(await repo.findUnfinishedRide(), isNull);
  });

  test('la mise à jour enregistre les statistiques et l état', () async {
    await repo.insertRide(_ride('r1', status: RideStatus.recording));
    final updated = (await repo.findRide('r1'))!.copyWith(
      status: RideStatus.finished,
      stats: const RideStats(
        distanceMeters: 42000,
        totalTime:      Duration(hours: 2),
        movingTime:     Duration(minutes: 95),
        avgSpeedKmh:    26.5,
        maxSpeedKmh:    88,
      ),
    );
    await repo.updateRide(updated);
    final found = await repo.findRide('r1');
    expect(found!.status, RideStatus.finished);
    expect(found.stats.distanceMeters, 42000);
    expect(found.stats.maxSpeedKmh, 88);
    expect(found.stats.movingTime, const Duration(minutes: 95));
  });

  test('supprimer une sortie supprime aussi ses points', () async {
    await repo.insertRide(_ride('r1'));
    await repo.appendPoints([_pt('r1', 0), _pt('r1', 1)]);
    await repo.deleteRide('r1');
    expect(await repo.findRide('r1'), isNull);
    expect(await repo.pointsOf('r1'), isEmpty);
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/services/ride_repository_test.dart`
Expected: échec de compilation, `ride_database.dart` introuvable.

- [ ] **Step 3: Écrire le schéma**

Create `lib/services/ride_database.dart` :

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ── Base de données locale des sorties ───────────────────────
class RideDatabase {
  static const int schemaVersion = 1;
  static const String fileName = 'rides.db';

  static Database? _instance;

  // ── Ouverture (singleton) ────────────────────────────────
  static Future<Database> open() async {
    if (_instance != null) return _instance!;
    final path = p.join(await getDatabasesPath(), fileName);
    _instance = await openDatabase(
      path,
      version:   schemaVersion,
      onCreate:  onCreate,
      onUpgrade: onUpgrade,
    );
    return _instance!;
  }

  // ── Création du schéma v1 ────────────────────────────────
  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rides (
        id            TEXT PRIMARY KEY,
        name          TEXT    NOT NULL,
        notes         TEXT,
        started_at    INTEGER NOT NULL,
        ended_at      INTEGER,
        source        TEXT    NOT NULL,
        status        TEXT    NOT NULL,
        distance_m    REAL    NOT NULL DEFAULT 0,
        total_time_s  INTEGER NOT NULL DEFAULT 0,
        moving_time_s INTEGER NOT NULL DEFAULT 0,
        avg_speed_kmh REAL    NOT NULL DEFAULT 0,
        max_speed_kmh REAL    NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ride_points (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        ride_id   TEXT    NOT NULL,
        seq       INTEGER NOT NULL,
        segment   INTEGER NOT NULL,
        lat       REAL    NOT NULL,
        lng       REAL    NOT NULL,
        altitude  REAL,
        speed_kmh REAL    NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_ride_points_ride ON ride_points (ride_id, seq)',
    );
  }

  // ── Migrations des lots suivants ─────────────────────────
  // Aucune migration en v1. Les lots 2 à 6 ajouteront leurs colonnes ici,
  // en incrémentant schemaVersion et en traitant chaque palier.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {}

  // ── Taille occupée sur le disque ─────────────────────────
  static Future<int> sizeBytes() async {
    final path = p.join(await getDatabasesPath(), fileName);
    final file = File(path);
    return await file.exists() ? await file.length() : 0;
  }
}
```

Note : `path` est une dépendance transitive de `sqflite`, aucun ajout au
`pubspec.yaml` n'est nécessaire.

- [ ] **Step 4: Écrire le dépôt**

Create `lib/services/ride_repository.dart` :

```dart
import 'package:sqflite/sqflite.dart';
import '../models/ride.dart';

// ── Dépôt — seule pièce qui lit et écrit les sorties ─────────
class RideRepository {
  RideRepository(this._db);
  final Database _db;

  // ── Sorties ──────────────────────────────────────────────
  Future<void> insertRide(Ride ride) =>
      _db.insert('rides', _toRow(ride),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateRide(Ride ride) =>
      _db.update('rides', _toRow(ride), where: 'id = ?', whereArgs: [ride.id]);

  Future<void> deleteRide(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('ride_points', where: 'ride_id = ?', whereArgs: [id]);
      await txn.delete('rides', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Ride?> findRide(String id) async {
    final rows = await _db.query('rides', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _toRide(rows.first);
  }

  Future<List<Ride>> listRides() async {
    final rows = await _db.query('rides', orderBy: 'started_at DESC');
    return rows.map(_toRide).toList();
  }

  Future<Ride?> findUnfinishedRide() async {
    final rows = await _db.query(
      'rides',
      where:    'status = ?',
      whereArgs: [RideStatus.recording.name],
      orderBy:  'started_at DESC',
      limit:    1,
    );
    return rows.isEmpty ? null : _toRide(rows.first);
  }

  // ── Points ───────────────────────────────────────────────
  Future<void> appendPoints(List<RidePoint> points) async {
    if (points.isEmpty) return;
    final batch = _db.batch();
    for (final p in points) {
      batch.insert('ride_points', _toPointRow(p));
    }
    await batch.commit(noResult: true);
  }

  Future<List<RidePoint>> pointsOf(String rideId) async {
    final rows = await _db.query(
      'ride_points',
      where:    'ride_id = ?',
      whereArgs: [rideId],
      orderBy:  'seq ASC',
    );
    return rows.map(_toPoint).toList();
  }

  // ── Conversions ──────────────────────────────────────────
  Map<String, Object?> _toRow(Ride r) => {
    'id':            r.id,
    'name':          r.name,
    'notes':         r.notes,
    'started_at':    r.startedAt.millisecondsSinceEpoch,
    'ended_at':      r.endedAt?.millisecondsSinceEpoch,
    'source':        r.source.name,
    'status':        r.status.name,
    'distance_m':    r.stats.distanceMeters,
    'total_time_s':  r.stats.totalTime.inSeconds,
    'moving_time_s': r.stats.movingTime.inSeconds,
    'avg_speed_kmh': r.stats.avgSpeedKmh,
    'max_speed_kmh': r.stats.maxSpeedKmh,
  };

  Ride _toRide(Map<String, Object?> row) => Ride(
    id:        row['id'] as String,
    name:      row['name'] as String,
    notes:     row['notes'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
    endedAt:   row['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['ended_at'] as int),
    source:    RideSource.values.byName(row['source'] as String),
    status:    RideStatus.values.byName(row['status'] as String),
    stats:     RideStats(
      distanceMeters: (row['distance_m'] as num).toDouble(),
      totalTime:      Duration(seconds: row['total_time_s'] as int),
      movingTime:     Duration(seconds: row['moving_time_s'] as int),
      avgSpeedKmh:    (row['avg_speed_kmh'] as num).toDouble(),
      maxSpeedKmh:    (row['max_speed_kmh'] as num).toDouble(),
    ),
  );

  Map<String, Object?> _toPointRow(RidePoint p) => {
    'ride_id':   p.rideId,
    'seq':       p.seq,
    'segment':   p.segment,
    'lat':       p.lat,
    'lng':       p.lng,
    'altitude':  p.altitude,
    'speed_kmh': p.speedKmh,
    'timestamp': p.timestamp.millisecondsSinceEpoch,
  };

  RidePoint _toPoint(Map<String, Object?> row) => RidePoint(
    rideId:    row['ride_id'] as String,
    seq:       row['seq'] as int,
    segment:   row['segment'] as int,
    lat:       (row['lat'] as num).toDouble(),
    lng:       (row['lng'] as num).toDouble(),
    altitude:  (row['altitude'] as num?)?.toDouble(),
    speedKmh:  (row['speed_kmh'] as num).toDouble(),
    timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
  );
}
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `flutter test test/services/ride_repository_test.dart`
Expected: `All tests passed!` (7 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/services/ride_database.dart lib/services/ride_repository.dart test/services/ride_repository_test.dart
git commit -m "feat: base sqflite et dépôt des sorties"
```

---

## Task 4: Mesure du niveau de vibration

Classe purement calculatoire : elle reçoit des magnitudes d'accéléromètre et
expose l'écart-type sur une fenêtre glissante. Elle ne connaît pas
`sensors_plus` — l'adaptation au capteur réel se fait en Task 8.

L'écart-type est utilisé plutôt que la magnitude brute parce que la gravité
vaut en permanence environ 9,8 : un téléphone posé à plat afficherait déjà une
magnitude élevée alors qu'il est parfaitement immobile.

**Files:**
- Create: `lib/services/vibration_meter.dart`
- Test: `test/services/vibration_meter_test.dart`

**Interfaces:**
- Consumes: rien
- Produces: `VibrationMeter({int windowSize = 100})` avec `void addSample(double)`, `double get level`, `void reset()`, et la fonction statique `double VibrationMeter.magnitudeOf(double x, double y, double z)`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/services/vibration_meter_test.dart` :

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/vibration_meter.dart';

void main() {
  test('sans échantillon le niveau est nul', () {
    expect(VibrationMeter().level, 0);
  });

  test('un signal constant donne un niveau nul même à forte magnitude', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(9.81);
    }
    expect(meter.level, closeTo(0, 0.0001));
  });

  test('un signal qui oscille donne un niveau non nul', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(i.isEven ? 9.6 : 10.0);
    }
    expect(meter.level, closeTo(0.2, 0.01));
  });

  test('la fenêtre glisse : le bruit ancien est oublié', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(i.isEven ? 5.0 : 15.0);
    }
    expect(meter.level, greaterThan(1));
    for (int i = 0; i < 10; i++) {
      meter.addSample(9.81);
    }
    expect(meter.level, closeTo(0, 0.0001));
  });

  test('reset vide la fenêtre', () {
    final meter = VibrationMeter(windowSize: 10);
    meter.addSample(1);
    meter.addSample(20);
    meter.reset();
    expect(meter.level, 0);
  });

  test('la magnitude combine les trois axes', () {
    expect(VibrationMeter.magnitudeOf(0, 0, 9.81), closeTo(9.81, 0.001));
    expect(VibrationMeter.magnitudeOf(3, 4, 0), closeTo(5, 0.001));
    expect(VibrationMeter.magnitudeOf(1, 1, 1), closeTo(sqrt(3), 0.001));
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/services/vibration_meter_test.dart`
Expected: échec de compilation, `vibration_meter.dart` introuvable.

- [ ] **Step 3: Écrire l implémentation**

Create `lib/services/vibration_meter.dart` :

```dart
import 'dart:collection';
import 'dart:math';

// ── Niveau de secousse sur une fenêtre glissante ─────────────
// À 50 Hz, une fenêtre de 100 échantillons couvre environ 2 secondes.
class VibrationMeter {
  VibrationMeter({this.windowSize = 100});

  final int windowSize;
  final Queue<double> _samples = Queue<double>();

  void addSample(double magnitude) {
    _samples.addLast(magnitude);
    while (_samples.length > windowSize) {
      _samples.removeFirst();
    }
  }

  // Écart-type de la fenêtre : indépendant de la gravité, qui n'est
  // qu'une composante constante du signal.
  double get level {
    if (_samples.length < 2) return 0;
    final mean = _samples.reduce((a, b) => a + b) / _samples.length;
    final variance = _samples
        .map((s) => (s - mean) * (s - mean))
        .reduce((a, b) => a + b) / _samples.length;
    return sqrt(variance);
  }

  void reset() => _samples.clear();

  static double magnitudeOf(double x, double y, double z) =>
      sqrt(x * x + y * y + z * z);
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/services/vibration_meter_test.dart`
Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/vibration_meter.dart test/services/vibration_meter_test.dart
git commit -m "feat: mesure du niveau de vibration sur fenêtre glissante"
```

---

## Task 5: Calibration des vibrations

Deux mesures — moteur coupé, puis moteur au ralenti — définissent le seuil qui
sépare « immobile » de « moteur tournant » pour le montage du pilote.

Le seuil est placé à **35 % de l'écart** entre les deux mesures, donc plus près
de la mesure basse. Ce choix est délibéré : plus le seuil est bas, plus la
vibration le dépasse facilement, donc plus l'application considère qu'on roule.
En cas de doute, elle continue d'enregistrer plutôt que de couper au milieu d'un
franchissement.

**Files:**
- Create: `lib/services/vibration_calibration.dart`
- Test: `test/services/vibration_calibration_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`
- Produces: `VibrationCalibration({double? stillLevel, double? idleLevel})` avec `bool get isCalibrated`, `double get threshold`, `static const double defaultThreshold`, `static Future<VibrationCalibration> load()`, `Future<void> save()`, `static Future<void> clear()`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/services/vibration_calibration_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/vibration_calibration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sans calibration, le seuil par défaut s applique', () {
    const cal = VibrationCalibration();
    expect(cal.isCalibrated, isFalse);
    expect(cal.threshold, VibrationCalibration.defaultThreshold);
  });

  test('le seuil se place à 35 % de l écart entre les deux mesures', () {
    const cal = VibrationCalibration(stillLevel: 0.02, idleLevel: 0.32);
    expect(cal.isCalibrated, isTrue);
    expect(cal.threshold, closeTo(0.125, 0.001));
  });

  test('une calibration incohérente retombe sur le seuil par défaut', () {
    // Le ralenti ne peut pas produire moins de vibration que l arrêt moteur.
    const cal = VibrationCalibration(stillLevel: 0.40, idleLevel: 0.10);
    expect(cal.isCalibrated, isFalse);
    expect(cal.threshold, VibrationCalibration.defaultThreshold);
  });

  test('une mesure seule ne suffit pas à calibrer', () {
    const cal = VibrationCalibration(stillLevel: 0.02);
    expect(cal.isCalibrated, isFalse);
  });

  test('la calibration survit à un enregistrement puis relecture', () async {
    SharedPreferences.setMockInitialValues({});
    await const VibrationCalibration(stillLevel: 0.05, idleLevel: 0.45).save();
    final loaded = await VibrationCalibration.load();
    expect(loaded.stillLevel, 0.05);
    expect(loaded.idleLevel, 0.45);
    expect(loaded.threshold, closeTo(0.19, 0.001));
  });

  test('sans rien en mémoire, load renvoie une calibration vide', () async {
    SharedPreferences.setMockInitialValues({});
    final loaded = await VibrationCalibration.load();
    expect(loaded.isCalibrated, isFalse);
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/services/vibration_calibration_test.dart`
Expected: échec de compilation, `vibration_calibration.dart` introuvable.

- [ ] **Step 3: Écrire l implémentation**

Create `lib/services/vibration_calibration.dart` :

```dart
import 'package:shared_preferences/shared_preferences.dart';

// ── Calibration des vibrations ───────────────────────────────
// Un seul jeu de mesures, refait quand le pilote change de moto ou de
// position de téléphone.
class VibrationCalibration {
  static const String _kStill = 'vibration_still_level';
  static const String _kIdle  = 'vibration_idle_level';

  // Seuil retenu tant que le pilote n'a pas calibré.
  static const double defaultThreshold = 0.12;

  // Position du seuil entre les deux mesures. Volontairement bas :
  // en cas de doute, on continue d'enregistrer.
  static const double _ratio = 0.35;

  final double? stillLevel;   // moteur coupé
  final double? idleLevel;    // moteur au ralenti

  const VibrationCalibration({this.stillLevel, this.idleLevel});

  bool get isCalibrated =>
      stillLevel != null && idleLevel != null && idleLevel! > stillLevel!;

  double get threshold => isCalibrated
      ? stillLevel! + (idleLevel! - stillLevel!) * _ratio
      : defaultThreshold;

  // ── Persistance ──────────────────────────────────────────
  static Future<VibrationCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();
    return VibrationCalibration(
      stillLevel: prefs.getDouble(_kStill),
      idleLevel:  prefs.getDouble(_kIdle),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (stillLevel != null) await prefs.setDouble(_kStill, stillLevel!);
    if (idleLevel  != null) await prefs.setDouble(_kIdle,  idleLevel!);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStill);
    await prefs.remove(_kIdle);
  }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/services/vibration_calibration_test.dart`
Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/vibration_calibration.dart test/services/vibration_calibration_test.dart
git commit -m "feat: calibration des vibrations et seuil de pause"
```

---

## Task 6: Machine à états de l'enregistreur

Le cœur du lot. Aucune dépendance à la base, aux capteurs réels ni à
l'interface : deux entrées injectées, des décisions en sortie. C'est ce qui
permet de rejouer une sortie entière en test, sans monter sur la moto.

**Distinction importante, absente du spec et à valider :** une pause
**automatique** se termine automatiquement dès que le pilote roule à nouveau,
mais une pause **manuelle** exige une reprise manuelle. Sans cette distinction,
le pilote qui met en pause pour aller déjeuner à pied verrait l'enregistrement
reprendre tout seul dès qu'il marche à plus de 3 km/h — exactement le cas que la
pause manuelle est censée régler.

**Files:**
- Create: `lib/services/ride_recorder.dart`
- Test: `test/services/ride_recorder_test.dart`

**Interfaces:**
- Consumes: `RidePoint` (Task 2), `GpsSnapshot` de `lib/services/location_service.dart`, `VibrationCalibration.defaultThreshold` (Task 5)
- Produces:
  - `enum RecorderState { idle, recording, paused }`
  - `enum PauseReason { none, auto, manual }`
  - `RecorderConfig({double pauseSpeedKmh = 2, double vibrationThreshold, Duration pauseDelay = const Duration(seconds: 30), bool autoPauseEnabled = true})` avec `double get resumeSpeedKmh`
  - `RideRecorder({required String rideId, required RecorderConfig config})` avec `RecorderState get state`, `PauseReason get pauseReason`, `int get segment`, `int get pointCount`, `void start()`, `void onSample({required GpsSnapshot gps, required double vibrationLevel})`, `void pauseManually()`, `void resumeManually()`, `void stop()`, `List<RidePoint> takePending()`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/services/ride_recorder_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/ride_recorder.dart';

final _t0 = DateTime(2026, 9, 2, 10, 0, 0);

GpsSnapshot _gps(double speedKmh, int secondsFromStart) => GpsSnapshot(
  position:       LatLng(44.0 + secondsFromStart * 0.0001, 6.0),
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       speedKmh,
  headingDeg:     90,
  timestamp:      _t0.add(Duration(seconds: secondsFromStart)),
);

// Alimente l'enregistreur pendant [seconds] secondes, un échantillon par
// seconde, à vitesse et vibration constantes.
void _feed(RideRecorder rec, {
  required double speedKmh,
  required double vibration,
  required int seconds,
  int from = 0,
}) {
  for (int s = from; s < from + seconds; s++) {
    rec.onSample(gps: _gps(speedKmh, s), vibrationLevel: vibration);
  }
}

RideRecorder _recorder({bool autoPause = true, double pauseSpeed = 2}) =>
    RideRecorder(
      rideId: 'r1',
      config: RecorderConfig(
        pauseSpeedKmh:       pauseSpeed,
        vibrationThreshold:  0.12,
        pauseDelay:          const Duration(seconds: 30),
        autoPauseEnabled:    autoPause,
      ),
    );

void main() {
  test('au départ l enregistreur est à l arrêt', () {
    expect(_recorder().state, RecorderState.idle);
  });

  test('tant qu il est à l arrêt, les échantillons sont ignorés', () {
    final rec = _recorder();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    expect(rec.pointCount, 0);
  });

  test('en roulage les points s accumulent sur le segment 0', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 10);
    expect(rec.state, RecorderState.recording);
    expect(rec.pointCount, 10);
    expect(rec.segment, 0);
  });

  test('immobile moins de 30 s, l enregistrement continue', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 20);
    expect(rec.state, RecorderState.recording);
  });

  test('immobile 30 s, la pause automatique se déclenche', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);
    expect(rec.pauseReason, PauseReason.auto);
  });

  test('en pause, plus aucun point n est enregistré', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    final countAtPause = rec.pointCount;
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 60, from: 31);
    expect(rec.pointCount, countAtPause);
  });

  test('franchissement lent moteur tournant : pas de pause', () {
    // Sous 2 km/h pendant 2 minutes, mais le téléphone vibre.
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 1.5, vibration: 0.9, seconds: 120);
    expect(rec.state, RecorderState.recording);
    expect(rec.pointCount, 120);
  });

  test('la reprise après pause automatique ouvre un nouveau segment', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);

    rec.onSample(gps: _gps(12, 200), vibrationLevel: 1.5);
    expect(rec.state, RecorderState.recording);
    expect(rec.segment, 1);
    expect(rec.takePending().last.segment, 1);
  });

  test('sous le seuil de reprise, la pause automatique tient', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    rec.onSample(gps: _gps(2.5, 200), vibrationLevel: 1.5); // seuil de reprise = 3
    expect(rec.state, RecorderState.paused);
  });

  test('pause automatique désactivée : aucune pause même immobile', () {
    final rec = _recorder(autoPause: false)..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 300);
    expect(rec.state, RecorderState.recording);
  });

  test('une pause manuelle ne se termine pas toute seule', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    rec.pauseManually();
    expect(rec.pauseReason, PauseReason.manual);

    // Le pilote marche à 4 km/h vers le restaurant : rien ne doit reprendre.
    _feed(rec, speedKmh: 4, vibration: 1.2, seconds: 60, from: 5);
    expect(rec.state, RecorderState.paused);
  });

  test('la reprise manuelle ouvre aussi un nouveau segment', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    rec.pauseManually();
    rec.resumeManually();
    expect(rec.state, RecorderState.recording);
    expect(rec.segment, 1);
  });

  test('le seuil de pause configurable à 5 km/h est respecté', () {
    final rec = _recorder(pauseSpeed: 5)..start();
    _feed(rec, speedKmh: 4, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);
  });

  test('takePending vide le tampon', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 4);
    expect(rec.takePending().length, 4);
    expect(rec.takePending(), isEmpty);
    expect(rec.pointCount, 4); // le compteur total ne se vide pas
  });

  test('stop ramène à l état initial', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 4);
    rec.stop();
    expect(rec.state, RecorderState.idle);
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/services/ride_recorder_test.dart`
Expected: échec de compilation, `ride_recorder.dart` introuvable.

- [ ] **Step 3: Écrire la machine à états**

Create `lib/services/ride_recorder.dart` :

```dart
import '../models/ride.dart';
import 'location_service.dart';
import 'vibration_calibration.dart';

// ── États et causes de pause ─────────────────────────────────
enum RecorderState { idle, recording, paused }
enum PauseReason { none, auto, manual }

// ── Réglages de l'enregistreur ───────────────────────────────
class RecorderConfig {
  final double pauseSpeedKmh;       // 2 ou 5 selon le réglage du pilote
  final double vibrationThreshold;  // issu de la calibration
  final Duration pauseDelay;
  final bool autoPauseEnabled;

  const RecorderConfig({
    this.pauseSpeedKmh      = 2,
    this.vibrationThreshold = VibrationCalibration.defaultThreshold,
    this.pauseDelay         = const Duration(seconds: 30),
    this.autoPauseEnabled   = true,
  });

  // Hystérésis : sans écart entre pause et reprise, une vitesse oscillant
  // autour du seuil ferait alterner les deux états en boucle.
  double get resumeSpeedKmh => pauseSpeedKmh + 1;
}

// ── Machine à états — ne lit ni n'écrit rien ─────────────────
class RideRecorder {
  RideRecorder({required this.rideId, required this.config});

  final String rideId;
  final RecorderConfig config;

  RecorderState _state = RecorderState.idle;
  PauseReason _pauseReason = PauseReason.none;
  int _segment = 0;
  int _seq = 0;
  DateTime? _stillSince;
  final List<RidePoint> _pending = [];

  RecorderState get state => _state;
  PauseReason get pauseReason => _pauseReason;
  int get segment => _segment;
  int get pointCount => _seq;

  // ── Cycle de vie ─────────────────────────────────────────
  void start() {
    _state = RecorderState.recording;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void stop() {
    _state = RecorderState.idle;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void pauseManually() {
    if (_state != RecorderState.recording) return;
    _state = RecorderState.paused;
    _pauseReason = PauseReason.manual;
    _stillSince = null;
  }

  void resumeManually() {
    if (_state != RecorderState.paused) return;
    _resume();
  }

  // ── Réception d'un échantillon ───────────────────────────
  void onSample({required GpsSnapshot gps, required double vibrationLevel}) {
    switch (_state) {
      case RecorderState.idle:
        return;

      case RecorderState.paused:
        // Seule une pause automatique se termine d'elle-même. Une pause
        // manuelle attend une reprise manuelle : sinon marcher jusqu'au
        // restaurant relancerait l'enregistrement.
        if (_pauseReason == PauseReason.auto &&
            gps.speedKmh > config.resumeSpeedKmh) {
          _resume();
          _append(gps);
        }
        return;

      case RecorderState.recording:
        final isStill = gps.speedKmh < config.pauseSpeedKmh &&
            vibrationLevel < config.vibrationThreshold;

        if (config.autoPauseEnabled && isStill) {
          _stillSince ??= gps.timestamp;
          if (gps.timestamp.difference(_stillSince!) >= config.pauseDelay) {
            _state = RecorderState.paused;
            _pauseReason = PauseReason.auto;
            _stillSince = null;
            return;
          }
        } else {
          _stillSince = null;
        }
        _append(gps);
    }
  }

  // ── Tampon d'écriture ────────────────────────────────────
  List<RidePoint> takePending() {
    final batch = List<RidePoint>.from(_pending);
    _pending.clear();
    return batch;
  }

  // ── Interne ──────────────────────────────────────────────
  void _resume() {
    _segment++;
    _state = RecorderState.recording;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void _append(GpsSnapshot gps) {
    _pending.add(RidePoint(
      rideId:    rideId,
      seq:       _seq++,
      segment:   _segment,
      lat:       gps.position.latitude,
      lng:       gps.position.longitude,
      altitude:  gps.altitudeMeters,
      speedKmh:  gps.speedKmh,
      timestamp: gps.timestamp,
    ));
  }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/services/ride_recorder_test.dart`
Expected: `All tests passed!` (15 tests).

- [ ] **Step 5: Vérifier l ensemble et l analyse statique**

Run: `flutter test && flutter analyze`
Expected: tous les tests passent, aucune erreur d'analyse.

- [ ] **Step 6: Commit**

```bash
git add lib/services/ride_recorder.dart test/services/ride_recorder_test.dart
git commit -m "feat: machine à états d'enregistrement avec pause automatique"
```

---

## Task 7: Préférences d'enregistrement

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Test: `test/providers/settings_provider_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`
- Produces, sur `SettingsProvider` : `bool get autoPauseEnabled`, `int get pauseSpeedKmh`, `bool get askNameOnStop`, `bool get suggestAutoStart`, `bool get useMiles`, `bool get keepScreenOnMap`, et les setters `setAutoPauseEnabled(bool)`, `setPauseSpeedKmh(int)`, `setAskNameOnStop(bool)`, `setSuggestAutoStart(bool)`, `setUseMiles(bool)`, `setKeepScreenOnMap(bool)`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/providers/settings_provider_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les valeurs par défaut sont celles du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.autoPauseEnabled, isTrue);
    expect(s.pauseSpeedKmh, 2);
    expect(s.askNameOnStop, isFalse);
    expect(s.suggestAutoStart, isFalse);
    expect(s.useMiles, isFalse);
    expect(s.keepScreenOnMap, isTrue);
  });

  test('les réglages survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoPauseEnabled(false);
    await s.setPauseSpeedKmh(5);
    await s.setAskNameOnStop(true);
    await s.setKeepScreenOnMap(false);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.autoPauseEnabled, isFalse);
    expect(reloaded.pauseSpeedKmh, 5);
    expect(reloaded.askNameOnStop, isTrue);
    expect(reloaded.keepScreenOnMap, isFalse);
  });

  test('un seuil de pause hors des valeurs prévues retombe sur 2', () async {
    SharedPreferences.setMockInitialValues({'rec_pause_speed': 17});
    final s = SettingsProvider();
    await s.load();
    expect(s.pauseSpeedKmh, 2);
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: échec, `autoPauseEnabled` n'existe pas.

- [ ] **Step 3: Étendre le provider**

Dans `lib/providers/settings_provider.dart`, ajouter les clés après `_kName` :

```dart
  static const _kAutoPause   = 'rec_auto_pause';
  static const _kPauseSpeed  = 'rec_pause_speed';
  static const _kAskName     = 'rec_ask_name';
  static const _kAutoStart   = 'rec_suggest_autostart';
  static const _kMiles       = 'unit_miles';
  static const _kScreenOn    = 'map_keep_screen_on';

  // Seuils de pause proposés, en km/h. Un curseur libre autoriserait des
  // valeurs absurdes qui déclencheraient des pauses intempestives.
  static const List<int> pauseSpeedChoices = [2, 5];
```

Ajouter les champs et accesseurs après `_riderName` :

```dart
  bool _autoPauseEnabled = true;
  int  _pauseSpeedKmh    = 2;
  bool _askNameOnStop    = false;
  bool _suggestAutoStart = false;
  bool _useMiles         = false;
  bool _keepScreenOnMap  = true;

  bool get autoPauseEnabled => _autoPauseEnabled;
  int  get pauseSpeedKmh    => _pauseSpeedKmh;
  bool get askNameOnStop    => _askNameOnStop;
  bool get suggestAutoStart => _suggestAutoStart;
  bool get useMiles         => _useMiles;
  bool get keepScreenOnMap  => _keepScreenOnMap;
```

Dans `load()`, avant `notifyListeners()` :

```dart
    _autoPauseEnabled = prefs.getBool(_kAutoPause)  ?? true;
    final speed       = prefs.getInt(_kPauseSpeed)  ?? 2;
    _pauseSpeedKmh    = pauseSpeedChoices.contains(speed) ? speed : 2;
    _askNameOnStop    = prefs.getBool(_kAskName)    ?? false;
    _suggestAutoStart = prefs.getBool(_kAutoStart)  ?? false;
    _useMiles         = prefs.getBool(_kMiles)      ?? false;
    _keepScreenOnMap  = prefs.getBool(_kScreenOn)   ?? true;
```

Ajouter les setters à la fin de la classe :

```dart
  // ── Réglages d'enregistrement ────────────────────────────
  Future<void> setAutoPauseEnabled(bool v) async {
    _autoPauseEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoPause, v);
    notifyListeners();
  }

  Future<void> setPauseSpeedKmh(int v) async {
    _pauseSpeedKmh = pauseSpeedChoices.contains(v) ? v : 2;
    (await SharedPreferences.getInstance()).setInt(_kPauseSpeed, _pauseSpeedKmh);
    notifyListeners();
  }

  Future<void> setAskNameOnStop(bool v) async {
    _askNameOnStop = v;
    (await SharedPreferences.getInstance()).setBool(_kAskName, v);
    notifyListeners();
  }

  Future<void> setSuggestAutoStart(bool v) async {
    _suggestAutoStart = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoStart, v);
    notifyListeners();
  }

  Future<void> setUseMiles(bool v) async {
    _useMiles = v;
    (await SharedPreferences.getInstance()).setBool(_kMiles, v);
    notifyListeners();
  }

  Future<void> setKeepScreenOnMap(bool v) async {
    _keepScreenOnMap = v;
    (await SharedPreferences.getInstance()).setBool(_kScreenOn, v);
    notifyListeners();
  }
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/providers/settings_provider.dart test/providers/settings_provider_test.dart
git commit -m "feat: préférences d'enregistrement persistées"
```

---

## Task 8: Service d'arrière-plan Android

**Choix d'architecture, à respecter :** le service d'arrière-plan sert
uniquement à **maintenir le processus vivant et à afficher la notification**.
Le GPS, l'accéléromètre et la machine à états restent dans l'isolat principal.

L'alternative — faire tourner la logique dans un isolat séparé via un
`TaskHandler` — impose de sérialiser les échanges entre isolats et de dupliquer
l'accès à la base. Le gain serait de survivre à la mort de l'isolat d'interface,
cas déjà couvert par la récupération après plantage (Task 14). Le coût ne se
justifie pas.

**Files:**
- Create: `lib/services/ride_recording_service.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: `flutter_foreground_task`
- Produces: `RideRecordingService()` (singleton) avec `Future<void> init()`, `Future<bool> requestPermissions()`, `Future<bool> start({required String title, required String text})`, `Future<void> updateNotification({required String title, required String text})`, `Future<void> stop()`, `Future<bool> get isRunning`

- [ ] **Step 1: Déclarer les permissions Android**

Dans `android/app/src/main/AndroidManifest.xml`, à l'intérieur de `<manifest>`
et **avant** `<application>` :

```xml
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

Les permissions de localisation existent déjà dans le projet ; ne pas les
dupliquer. Vérifier avant d'ajouter :

Run: `grep -n "uses-permission" android/app/src/main/AndroidManifest.xml`

- [ ] **Step 2: Écrire le service**

Create `lib/services/ride_recording_service.dart` :

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ── Service d'arrière-plan ───────────────────────────────────
// Ne fait que deux choses : maintenir le processus vivant pendant
// l'enregistrement, et afficher une notification à jour. Toute la logique
// d'enregistrement vit dans l'isolat principal (RecordingProvider).
class RideRecordingService {
  static final RideRecordingService _instance = RideRecordingService._();
  factory RideRecordingService() => _instance;
  RideRecordingService._();

  static const String _channelId = 'moto_offroad_recording';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:         _channelId,
        channelName:       'Enregistrement de sortie',
        channelDescription:
            'Maintient l\'enregistrement actif quand l\'écran est éteint.',
        channelImportance: NotificationChannelImportance.LOW,
        priority:          NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 8.17.0 : plus de champ `interval`, la cadence passe par eventAction.
        eventAction:       ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot:     false,
        allowWakeLock:     true,
        allowWifiLock:     false,
      ),
    );
    _initialized = true;
  }

  // ── Permissions : notification puis optimisation batterie ─
  Future<bool> requestPermissions() async {
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      final asked = await FlutterForegroundTask.requestNotificationPermission();
      if (asked != NotificationPermission.granted) return false;
    }

    // Sans cette exemption, Xiaomi, Huawei, Oppo et certains Samsung tuent le
    // service malgré la notification. Refus non bloquant : on enregistre
    // quand même, en acceptant le risque.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<bool> start({required String title, required String text}) async {
    await init();
    if (await isRunning) return true;
    final result = await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText:  text,
    );
    return result is ServiceRequestSuccess;
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!await isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText:  text,
    );
  }

  Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
  }
}
```

- [ ] **Step 3: Vérifier la compilation et l'API de la version installée**

Run: `flutter analyze lib/services/ride_recording_service.dart`
Expected: aucune erreur.

La version installée est **8.17.0**, vérifiée : `ForegroundTaskOptions` y prend
`eventAction: ForegroundTaskEventAction.repeat(int millis)` et conserve les
champs booléens `autoRunOnBoot`, `allowWakeLock`, `allowWifiLock`. Si un autre
nom de paramètre est refusé, ouvrir
`~/.pub-cache/hosted/pub.dev/flutter_foreground_task-8.17.0/example/lib/main.dart`
et aligner le nommage. Ne pas changer l'architecture.

- [ ] **Step 4: Vérifier sur appareil**

Run: `flutter run` puis, depuis l'app, appeler manuellement le service depuis
un bouton temporaire ou le débogueur.
Expected: une notification « Enregistrement de sortie » apparaît et persiste
quand l'application passe en arrière-plan.

- [ ] **Step 5: Commit**

```bash
git add lib/services/ride_recording_service.dart android/app/src/main/AndroidManifest.xml
git commit -m "feat: service d'arrière-plan et notification d'enregistrement"
```

---

## Task 9: Orchestration de l'enregistrement

Le provider assemble les pièces : il branche le GPS et l'accéléromètre sur la
machine à états, écrit par lots en base, met à jour la notification, et expose
l'état à l'interface.

**Files:**
- Create: `lib/providers/recording_provider.dart`
- Test: `test/providers/recording_provider_test.dart`

**Interfaces:**
- Consumes: `RideRecorder`, `RecorderConfig`, `RecorderState`, `PauseReason` (Task 6) ; `RideRepository` (Task 3) ; `VibrationMeter` (Task 4) ; `VibrationCalibration` (Task 5) ; `RideRecordingService` (Task 8) ; `GpsSnapshot`, `LocationService` (existant) ; `Ride`, `RideStats` (Task 2)
- Produces: `RecordingProvider({required RideRepository repository, RideRecordingService? service})` avec `RecorderState get state`, `bool get isRecording`, `bool get isPaused`, `PauseReason get pauseReason`, `Ride? get currentRide`, `RideStats get liveStats`, `Future<void> startRide({required String name, required RecorderConfig config})`, `void onGpsSample(GpsSnapshot)`, `void onAccelerometer(double x, double y, double z)`, `Future<void> togglePause()`, `Future<Ride?> stopRide()`, `Future<void> flush()`

- [ ] **Step 1: Écrire les tests qui échouent**

Create `test/providers/recording_provider_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/providers/recording_provider.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_recorder.dart';
import 'package:moto_offroad/services/ride_repository.dart';

final _t0 = DateTime(2026, 9, 2, 10, 0, 0);

GpsSnapshot _gps(double speedKmh, int s) => GpsSnapshot(
  position:       LatLng(44.0 + s * 0.0001, 6.0),
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       speedKmh,
  headingDeg:     90,
  timestamp:      _t0.add(Duration(seconds: s)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late RideRepository repo;
  late RecordingProvider provider;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version:  RideDatabase.schemaVersion,
        onCreate: RideDatabase.onCreate,
      ),
    );
    repo = RideRepository(db);
    // service null : aucune notification ni service Android en test
    provider = RecordingProvider(repository: repo, service: null);
  });

  tearDown(() async => db.close());

  test('démarrer crée une sortie en base à l état recording', () async {
    await provider.startRide(
      name: 'Sortie test',
      config: const RecorderConfig(),
    );
    expect(provider.isRecording, isTrue);
    final open = await repo.findUnfinishedRide();
    expect(open, isNotNull);
    expect(open!.name, 'Sortie test');
  });

  test('les points sont écrits en base après un flush', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    for (int s = 0; s < 12; s++) {
      provider.onAccelerometer(0, 0, 12.0 + (s.isEven ? 1 : -1));
      provider.onGpsSample(_gps(40, s));
    }
    await provider.flush();
    final points = await repo.pointsOf(provider.currentRide!.id);
    expect(points.length, 12);
    expect(points.first.segment, 0);
  });

  test('les statistiques en direct suivent les points enregistrés', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    for (int s = 0; s < 10; s++) {
      provider.onAccelerometer(0, 0, 12.0 + (s.isEven ? 1 : -1));
      provider.onGpsSample(_gps(40, s));
    }
    expect(provider.liveStats.distanceMeters, greaterThan(0));
    expect(provider.liveStats.maxSpeedKmh, 40);
  });

  test('arrêter clôture la sortie avec ses statistiques', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    for (int s = 0; s < 10; s++) {
      provider.onAccelerometer(0, 0, 12.0 + (s.isEven ? 1 : -1));
      provider.onGpsSample(_gps(40, s));
    }
    final ride = await provider.stopRide();
    expect(ride, isNotNull);
    expect(ride!.status, RideStatus.finished);
    expect(ride.endedAt, isNotNull);
    expect(ride.stats.distanceMeters, greaterThan(0));
    expect(provider.state, RecorderState.idle);
    expect(await repo.findUnfinishedRide(), isNull);
  });

  test('la bascule de pause passe en pause manuelle puis reprend', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    provider.onGpsSample(_gps(40, 0));
    await provider.togglePause();
    expect(provider.isPaused, isTrue);
    expect(provider.pauseReason, PauseReason.manual);
    await provider.togglePause();
    expect(provider.isRecording, isTrue);
  });

  test('l accéléromètre alimente le niveau de vibration transmis', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    // Signal constant : niveau nul, donc immobile si la vitesse est nulle.
    for (int s = 0; s < 40; s++) {
      provider.onAccelerometer(0, 0, 9.81);
      provider.onGpsSample(_gps(0, s));
    }
    expect(provider.isPaused, isTrue);
    expect(provider.pauseReason, PauseReason.auto);
  });
}
```

- [ ] **Step 2: Vérifier que les tests échouent**

Run: `flutter test test/providers/recording_provider_test.dart`
Expected: échec de compilation, `recording_provider.dart` introuvable.

- [ ] **Step 3: Écrire le provider**

Create `lib/providers/recording_provider.dart` :

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/ride.dart';
import '../services/location_service.dart';
import '../services/ride_recorder.dart';
import '../services/ride_recording_service.dart';
import '../services/ride_repository.dart';
import '../services/vibration_meter.dart';

// ── Provider — orchestration de l'enregistrement ─────────────
class RecordingProvider extends ChangeNotifier {
  RecordingProvider({
    required RideRepository repository,
    RideRecordingService? service,
  })  : _repo = repository,
        _service = service;

  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _flushPointCount = 10;

  final RideRepository _repo;
  final RideRecordingService? _service;
  final _uuid = const Uuid();
  final _meter = VibrationMeter();

  RideRecorder? _recorder;
  Ride? _currentRide;
  Timer? _flushTimer;
  final List<RidePoint> _written = [];

  RecorderState get state => _recorder?.state ?? RecorderState.idle;
  bool get isRecording => state == RecorderState.recording;
  bool get isPaused    => state == RecorderState.paused;
  PauseReason get pauseReason => _recorder?.pauseReason ?? PauseReason.none;
  Ride? get currentRide => _currentRide;

  // Statistiques recalculées sur les points déjà écrits : la liste d'une
  // sortie de 4 h reste en mémoire, mais le calcul est linéaire et n'a lieu
  // qu'à l'affichage.
  RideStats get liveStats => RideStats.fromPoints(_written);

  // ── Démarrage ────────────────────────────────────────────
  Future<void> startRide({
    required String name,
    required RecorderConfig config,
  }) async {
    final ride = Ride(
      id:        _uuid.v4(),
      name:      name,
      startedAt: DateTime.now(),
      source:    RideSource.recorded,
      status:    RideStatus.recording,
      stats:     RideStats.empty,
    );
    await _repo.insertRide(ride);

    _currentRide = ride;
    _written.clear();
    _meter.reset();
    _recorder = RideRecorder(rideId: ride.id, config: config)..start();

    await _service?.start(
      title: 'Enregistrement en cours',
      text:  '0,0 km · 00:00',
    );

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
    notifyListeners();
  }

  // ── Entrées capteurs ─────────────────────────────────────
  void onAccelerometer(double x, double y, double z) {
    _meter.addSample(VibrationMeter.magnitudeOf(x, y, z));
  }

  void onGpsSample(GpsSnapshot gps) {
    final rec = _recorder;
    if (rec == null) return;

    final before = rec.state;
    rec.onSample(gps: gps, vibrationLevel: _meter.level);

    if (rec.pointCount - _written.length >= _flushPointCount) {
      flush();
    }
    if (rec.state != before) {
      _updateNotification();
    }
    notifyListeners();
  }

  // ── Pause ────────────────────────────────────────────────
  Future<void> togglePause() async {
    final rec = _recorder;
    if (rec == null) return;
    if (rec.state == RecorderState.recording) {
      rec.pauseManually();
    } else if (rec.state == RecorderState.paused) {
      rec.resumeManually();
    }
    await flush();
    await _updateNotification();
    notifyListeners();
  }

  // ── Écriture par lots ────────────────────────────────────
  Future<void> flush() async {
    final rec = _recorder;
    if (rec == null) return;
    final batch = rec.takePending();
    if (batch.isEmpty) return;
    _written.addAll(batch);
    await _repo.appendPoints(batch);
    await _updateNotification();
  }

  // ── Arrêt ────────────────────────────────────────────────
  Future<Ride?> stopRide() async {
    final rec = _recorder;
    final ride = _currentRide;
    if (rec == null || ride == null) return null;

    await flush();
    rec.stop();
    _flushTimer?.cancel();
    _flushTimer = null;

    final finished = ride.copyWith(
      status:  RideStatus.finished,
      endedAt: DateTime.now(),
      stats:   RideStats.fromPoints(_written),
    );
    await _repo.updateRide(finished);
    await _service?.stop();

    _recorder = null;
    _currentRide = null;
    notifyListeners();
    return finished;
  }

  // ── Notification ─────────────────────────────────────────
  Future<void> _updateNotification() async {
    if (_service == null || _recorder == null) return;
    final s = liveStats;
    final d = s.totalTime;
    final duree = '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    final km = s.distanceKm.toStringAsFixed(1).replaceAll('.', ',');
    final etat = isPaused ? ' · en pause' : '';
    await _service.updateNotification(
      title: 'Enregistrement en cours',
      text:  '$km km · $duree$etat',
    );
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/providers/recording_provider_test.dart`
Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/providers/recording_provider.dart test/providers/recording_provider_test.dart
git commit -m "feat: orchestration de l'enregistrement et écriture par lots"
```

---

## Task 10: Bouton REC et bandeau sur la carte

`map_screen.dart` compte 792 lignes. L'interface d'enregistrement va dans son
propre fichier : les lots 3 et 5 devront eux aussi ajouter des éléments à cette
carte, et le fichier doit cesser de grossir.

**Files:**
- Create: `lib/services/ride_sensor_bridge.dart`
- Create: `lib/widgets/recording_panel.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/map/map_screen.dart:117-121` et `:145-153`

**Interfaces:**
- Consumes: `RecordingProvider` (Task 9), `SettingsProvider` (Task 7), `LocationService` (existant), `sensors_plus`
- Produces:
  - `RideSensorBridge()` (singleton) avec `void attach(RecordingProvider)`, `void detach()`
  - `RecordingPanel` — widget sans paramètre, à placer dans une `Column`

- [ ] **Step 1: Écrire le pont capteurs**

Create `lib/services/ride_sensor_bridge.dart` :

```dart
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../providers/recording_provider.dart';
import 'location_service.dart';

// ── Pont entre les capteurs réels et le provider ─────────────
// Isolé du provider pour que la logique d'enregistrement reste testable
// sans matériel.
class RideSensorBridge {
  static final RideSensorBridge _instance = RideSensorBridge._();
  factory RideSensorBridge() => _instance;
  RideSensorBridge._();

  StreamSubscription? _gpsSub;
  StreamSubscription? _accelSub;

  void attach(RecordingProvider provider) {
    detach();
    _gpsSub = LocationService().stream.listen(provider.onGpsSample);
    _accelSub = accelerometerEventStream().listen(
      (e) => provider.onAccelerometer(e.x, e.y, e.z),
    );
  }

  void detach() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gpsSub = null;
    _accelSub = null;
  }
}
```

La version installée est **sensors_plus 4.0.2**, vérifiée : le getter
`accelerometerEvents` y est marqué `@Deprecated`. Utiliser la fonction
`accelerometerEventStream()`, comme ci-dessus.

- [ ] **Step 2: Écrire le panneau**

Create `lib/widgets/recording_panel.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ride_recorder.dart';
import '../services/ride_sensor_bridge.dart';
import '../services/vibration_calibration.dart';

// ── Bouton REC et bandeau de statistiques ────────────────────
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    return rec.state == RecorderState.idle
        ? const _RecButton()
        : const _RecordingBar();
  }
}

// ── Bouton de démarrage ──────────────────────────────────────
class _RecButton extends StatelessWidget {
  const _RecButton();

  Future<void> _start(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final rec = context.read<RecordingProvider>();
    final calibration = await VibrationCalibration.load();

    final now = DateTime.now();
    await rec.startRide(
      name: 'Sortie du ${now.day}/${now.month}/${now.year}',
      config: RecorderConfig(
        pauseSpeedKmh:      settings.pauseSpeedKmh.toDouble(),
        vibrationThreshold: calibration.threshold,
        autoPauseEnabled:   settings.autoPauseEnabled,
      ),
    );
    RideSensorBridge().attach(rec);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: () => _start(context),
          icon: const Icon(Icons.fiber_manual_record, size: 26),
          label: const Text('ENREGISTRER',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF5350),
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Bandeau pendant l'enregistrement ─────────────────────────
class _RecordingBar extends StatelessWidget {
  const _RecordingBar();

  Future<void> _stop(BuildContext context) async {
    final rec = context.read<RecordingProvider>();
    RideSensorBridge().detach();
    final ride = await rec.stopRide();
    if (ride != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sortie enregistrée : ${ride.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    final stats = rec.liveStats;
    final paused = rec.isPaused;
    final d = stats.totalTime;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: paused ? const Color(0xFF5C4B1F) : const Color(0xFF7A1F1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: paused ? const Color(0xFFF9A825) : const Color(0xFFEF5350),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(paused ? Icons.pause_circle : Icons.fiber_manual_record,
              color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  paused ? 'EN PAUSE' : 'ENREGISTREMENT',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
                Text(
                  '${stats.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
                  ' · ${d.inHours.toString().padLeft(2, '0')}'
                  ':${(d.inMinutes % 60).toString().padLeft(2, '0')}'
                  ' · ${stats.avgSpeedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: paused ? 'Reprendre' : 'Mettre en pause',
            icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                color: Colors.white, size: 28),
            onPressed: () => context.read<RecordingProvider>().togglePause(),
          ),
          // Appui long : un arrêt accidentel après trois heures de sortie
          // n'est pas rattrapable.
          GestureDetector(
            onLongPress: () => _stop(context),
            child: Tooltip(
              message: 'Appui long pour arrêter',
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.stop, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Brancher le provider dans l'application**

Dans `lib/main.dart`, ajouter les imports :

```dart
import 'providers/recording_provider.dart';
import 'services/ride_database.dart';
import 'services/ride_repository.dart';
```

Dans `main()`, après l'initialisation Firebase et **avant** `runApp` :

```dart
  // Base locale des sorties
  final rideRepository = RideRepository(await RideDatabase.open());
```

Passer le dépôt à l'application :

```dart
  runApp(MotoOffroadApp(rideRepository: rideRepository));
```

Adapter la classe :

```dart
class MotoOffroadApp extends StatelessWidget {
  const MotoOffroadApp({super.key, required this.rideRepository});

  final RideRepository rideRepository;
```

et ajouter dans la liste `providers` :

```dart
        ChangeNotifierProvider(
          create: (_) => RecordingProvider(
            repository: rideRepository,
            service:    RideRecordingService(),
          ),
        ),
```

avec l'import `import 'services/ride_recording_service.dart';`.

- [ ] **Step 4: Insérer le panneau dans la carte**

Dans `lib/screens/map/map_screen.dart`, ajouter l'import :

```dart
import '../../widgets/recording_panel.dart';
```

Dans la branche portrait, la `Column` de la ligne 120 devient :

```dart
              child: Column(children: [
                const RecordingPanel(),
                _buildStatsBar(),
```

Faire la même insertion dans la branche paysage, dans la `Column` qui suit
`MapSearchBar` (ligne 150-153), après `_buildMapControls()`.

- [ ] **Step 5: Vérifier**

Run: `flutter analyze && flutter test`
Expected: aucune erreur, tous les tests passent.

Run: `flutter run` — appuyer sur ENREGISTRER, vérifier que le bandeau
apparaît, que la distance augmente en roulant ou en simulant une position,
que la notification s'affiche, et que l'appui long arrête bien la sortie.

- [ ] **Step 6: Commit**

```bash
git add lib/services/ride_sensor_bridge.dart lib/widgets/recording_panel.dart lib/main.dart lib/screens/map/map_screen.dart
git commit -m "feat: bouton REC et bandeau d'enregistrement sur la carte"
```

---

## Task 11: Onglet Sorties

**Files:**
- Create: `lib/providers/rides_provider.dart`
- Create: `lib/screens/rides/rides_screen.dart`
- Create: `lib/screens/rides/ride_detail_screen.dart`
- Modify: `lib/app/router.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `RideRepository` (Task 3), `Ride`, `RideStats` (Task 2)
- Produces: `RidesProvider({required RideRepository repository})` avec `List<Ride> get rides`, `bool get isLoading`, `Future<void> refresh()`, `Future<void> rename(String id, String name)`, `Future<void> setNotes(String id, String notes)`, `Future<void> remove(String id)`, `Future<List<RidePoint>> pointsOf(String id)` ; routes `AppRoutes.rides` (`/rides`) et `AppRoutes.rideDetail` (`/rides/:id`)

- [ ] **Step 1: Écrire le provider**

Create `lib/providers/rides_provider.dart` :

```dart
import 'package:flutter/foundation.dart';
import '../models/ride.dart';
import '../services/ride_repository.dart';

// ── Provider — historique des sorties ────────────────────────
class RidesProvider extends ChangeNotifier {
  RidesProvider({required RideRepository repository}) : _repo = repository;

  final RideRepository _repo;
  List<Ride> _rides = [];
  bool _isLoading = false;

  List<Ride> get rides => List.unmodifiable(_rides);
  bool get isLoading => _isLoading;

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    _rides = await _repo.listRides();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final ride = await _repo.findRide(id);
    if (ride == null) return;
    await _repo.updateRide(ride.copyWith(name: name));
    await refresh();
  }

  Future<void> setNotes(String id, String notes) async {
    final ride = await _repo.findRide(id);
    if (ride == null) return;
    await _repo.updateRide(ride.copyWith(notes: notes));
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.deleteRide(id);
    await refresh();
  }

  Future<List<RidePoint>> pointsOf(String id) => _repo.pointsOf(id);
}
```

- [ ] **Step 2: Écrire l'écran liste**

Create `lib/screens/rides/rides_screen.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../models/ride.dart';
import '../../providers/rides_provider.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<RidesProvider>().refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RidesProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('🏍️  SORTIES')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.rides.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: provider.refresh,
                  child: ListView.separated(
                    itemCount: provider.rides.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _RideTile(ride: provider.rides[i]),
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucune sortie pour l\'instant.\n\n'
            'Appuyez sur ENREGISTRER depuis la carte pour garder la trace '
            'de votre prochaine balade.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final d = ride.stats.totalTime;
    return ListTile(
      leading: Icon(
        ride.source == RideSource.recorded
            ? Icons.fiber_manual_record
            : Icons.download,
        color: ride.source == RideSource.recorded
            ? const Color(0xFFEF5350)
            : const Color(0xFF5C6BC0),
      ),
      title: Text(ride.name),
      subtitle: Text(
        '${ride.startedAt.day}/${ride.startedAt.month}/${ride.startedAt.year}'
        ' · ${ride.stats.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
        ' · ${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('${AppRoutes.rides}/${ride.id}'),
    );
  }
}
```

- [ ] **Step 3: Écrire l'écran de détail**

Create `lib/screens/rides/ride_detail_screen.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/ride.dart';
import '../../providers/rides_provider.dart';

class RideDetailScreen extends StatelessWidget {
  const RideDetailScreen({super.key, required this.rideId});
  final String rideId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RidesProvider>();
    final ride = provider.rides.where((r) => r.id == rideId).firstOrNull;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('Sortie introuvable')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Renommer',
            onPressed: () => _rename(context, ride),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _confirmDelete(context, ride),
          ),
        ],
      ),
      body: FutureBuilder<List<RidePoint>>(
        future: provider.pointsOf(rideId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              SizedBox(height: 280, child: _RideMap(points: snap.data!)),
              Expanded(child: _StatsList(ride: ride)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, Ride ride) async {
    final controller = TextEditingController(text: ride.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la sortie'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<RidesProvider>().rename(ride.id, name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Ride ride) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette sortie ?'),
        content: Text('« ${ride.name} » et sa trace seront définitivement '
            'effacées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<RidesProvider>().remove(ride.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ── Carte de la sortie : une polyligne par segment ───────────
class _RideMap extends StatelessWidget {
  const _RideMap({required this.points});
  final List<RidePoint> points;

  // Deux segments ne sont jamais reliés : le trajet fait pendant une pause
  // n'a pas été enregistré et un trait droit mentirait sur le parcours.
  List<List<LatLng>> get _segments {
    final result = <List<LatLng>>[];
    List<LatLng>? current;
    int? currentSegment;
    for (final p in points) {
      if (p.segment != currentSegment) {
        if (current != null) result.add(current);
        current = [];
        currentSegment = p.segment;
      }
      current!.add(p.position);
    }
    if (current != null) result.add(current);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Aucun point enregistré'));
    }
    return FlutterMap(
      options: MapOptions(
        initialCenter: points[points.length ~/ 2].position,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.motooffroad.app',
        ),
        PolylineLayer(
          polylines: _segments
              .map((seg) => Polyline(
                    points: seg,
                    strokeWidth: 4,
                    color: const Color(0xFFEF5350),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final s = ride.stats;
    final total = s.totalTime;
    final moving = s.movingTime;
    return ListView(
      children: [
        _row('Distance',
            '${s.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'),
        _row('Durée totale',
            '${total.inHours}h${(total.inMinutes % 60).toString().padLeft(2, '0')}'),
        _row('Temps en mouvement',
            '${moving.inHours}h${(moving.inMinutes % 60).toString().padLeft(2, '0')}'),
        _row('Vitesse moyenne', '${s.avgSpeedKmh.toStringAsFixed(1)} km/h'),
        _row('Vitesse maximale', '${s.maxSpeedKmh.toStringAsFixed(1)} km/h'),
        _row('Origine',
            ride.source == RideSource.recorded ? 'Enregistrée' : 'Importée'),
      ],
    );
  }

  Widget _row(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );
}
```

- [ ] **Step 4: Modifier la navigation**

Dans `lib/app/router.dart` :

1. Remplacer `static const String info = '/info';` par
   `static const String rides = '/rides';`
2. Ajouter l'import de `RidesScreen` et `RideDetailScreen`, retirer celui de
   `InfoScreen`.
3. Dans le `ShellRoute`, remplacer la `GoRoute` de `/info` par :

```dart
        GoRoute(
          path: AppRoutes.rides,
          pageBuilder: (_, __) => const NoTransitionPage(child: RidesScreen()),
          routes: [
            GoRoute(
              path: ':id',
              pageBuilder: (_, state) => MaterialPage(
                child: RideDetailScreen(rideId: state.pathParameters['id']!),
              ),
            ),
          ],
        ),
```

4. Dans `_currentIndex`, remplacer `case AppRoutes.info: return 2;` par :

```dart
      case AppRoutes.rides:    return 2;
```

et faire précéder le `switch` d'une prise en compte des sous-routes :

```dart
    if (location.startsWith(AppRoutes.rides)) return 2;
```

5. Dans la `BottomNavigationBar`, remplacer l'élément Info par :

```dart
          BottomNavigationBarItem(icon: Icon(Icons.route_outlined),           activeIcon: Icon(Icons.route),               label: 'Sorties'),
```

6. Dans `_onNavTap`, remplacer `case 2: context.go(AppRoutes.info); break;`
   par `case 2: context.go(AppRoutes.rides); break;`

- [ ] **Step 5: Enregistrer le provider**

Dans `lib/main.dart`, ajouter à la liste `providers` :

```dart
        ChangeNotifierProvider(
          create: (_) => RidesProvider(repository: rideRepository),
        ),
```

avec `import 'providers/rides_provider.dart';`.

- [ ] **Step 6: Vérifier**

Run: `flutter analyze && flutter test`
Expected: aucune erreur, tous les tests passent.

Run: `flutter run` — enregistrer une courte sortie, l'arrêter, ouvrir l'onglet
Sorties, vérifier qu'elle apparaît avec ses statistiques, l'ouvrir, vérifier
que la trace s'affiche, la renommer, puis la supprimer.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/rides_provider.dart lib/screens/rides/ lib/app/router.dart lib/main.dart
git commit -m "feat: onglet Sorties avec liste, détail et suppression"
```

---

## Task 12: Export GPX et persistance des traces importées

`GpxService.exportToGpx()` (`gpx_service.dart:116`) est écrit et n'a jamais été
appelé. Cette tâche le branche enfin, et fait en sorte qu'une trace importée
survive à la fermeture de l'application.

**Files:**
- Create: `lib/services/ride_export_service.dart`
- Test: `test/services/ride_export_service_test.dart`
- Modify: `lib/providers/trace_provider.dart`
- Modify: `lib/screens/rides/ride_detail_screen.dart`

**Interfaces:**
- Consumes: `Ride`, `RidePoint` (Task 2), `GpxService` et `TraceModel` (existants), `path_provider`, `share_plus`
- Produces: `RideExportService()` (singleton) avec `TraceModel toTraceModel(Ride, List<RidePoint>)`, `String toGpx(Ride, List<RidePoint>)`, `Future<void> shareGpx(Ride, List<RidePoint>)` ; sur `TraceProvider` : `Future<bool> importFromFile(String path, {RideRepository? repository})` qui persiste quand un dépôt est fourni

- [ ] **Step 1: Écrire le test qui échoue**

Create `test/services/ride_export_service_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/ride_export_service.dart';

Ride _ride() => Ride(
  id:        'r1',
  name:      'Sortie du Ventoux',
  startedAt: DateTime.utc(2026, 9, 2, 8, 0),
  endedAt:   DateTime.utc(2026, 9, 2, 12, 0),
  source:    RideSource.recorded,
  status:    RideStatus.finished,
  stats:     RideStats.empty,
);

List<RidePoint> _points() => [
  RidePoint(rideId: 'r1', seq: 0, segment: 0, lat: 44.1, lng: 5.2,
      altitude: 800, speedKmh: 30, timestamp: DateTime.utc(2026, 9, 2, 8, 0)),
  RidePoint(rideId: 'r1', seq: 1, segment: 0, lat: 44.2, lng: 5.3,
      altitude: 1200, speedKmh: 25, timestamp: DateTime.utc(2026, 9, 2, 9, 0)),
];

void main() {
  test('la conversion garde le nom, les points et les altitudes', () {
    final trace = RideExportService().toTraceModel(_ride(), _points());
    expect(trace.name, 'Sortie du Ventoux');
    expect(trace.points.length, 2);
    expect(trace.points.first.elevation, 800);
    expect(trace.points.first.position.latitude, 44.1);
  });

  test('le GPX produit contient les coordonnées et le nom', () {
    final gpx = RideExportService().toGpx(_ride(), _points());
    expect(gpx, contains('<gpx'));
    expect(gpx, contains('44.1'));
    expect(gpx, contains('5.3'));
    expect(gpx, contains('Sortie du Ventoux'));
  });

  test('une sortie sans point produit un GPX valide mais vide', () {
    final gpx = RideExportService().toGpx(_ride(), []);
    expect(gpx, contains('<gpx'));
  });
}
```

- [ ] **Step 2: Vérifier que le test échoue**

Run: `flutter test test/services/ride_export_service_test.dart`
Expected: échec de compilation, `ride_export_service.dart` introuvable.

- [ ] **Step 3: Écrire le service**

Create `lib/services/ride_export_service.dart` :

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/ride.dart';
import '../models/trace.dart';
import 'gpx_service.dart';

// ── Export d'une sortie vers GPX ─────────────────────────────
class RideExportService {
  static final RideExportService _instance = RideExportService._();
  factory RideExportService() => _instance;
  RideExportService._();

  final _gpx = GpxService();

  TraceModel toTraceModel(Ride ride, List<RidePoint> points) => TraceModel(
        id:     ride.id,
        name:   ride.name,
        description: ride.notes,
        date:   ride.startedAt,
        source: ride.source.name,
        points: points
            .map((p) => TracePoint(
                  position:  p.position,
                  elevation: p.altitude,
                  time:      p.timestamp,
                  speed:     p.speedKmh,
                ))
            .toList(),
      );

  String toGpx(Ride ride, List<RidePoint> points) =>
      _gpx.exportToGpx(toTraceModel(ride, points));

  // ── Écriture d'un fichier puis menu de partage Android ────
  Future<void> shareGpx(Ride ride, List<RidePoint> points) async {
    final dir = await getTemporaryDirectory();
    final safeName = ride.name.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File('${dir.path}/$safeName.gpx');
    await file.writeAsString(toGpx(ride, points));
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: ride.name,
      text:    'Trace ${ride.name}',
    );
  }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `flutter test test/services/ride_export_service_test.dart`
Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Ajouter le bouton d'export**

Dans `lib/screens/rides/ride_detail_screen.dart`, ajouter l'import
`import '../../services/ride_export_service.dart';` et insérer dans la liste
`actions` de l'`AppBar`, avant l'icône de suppression :

```dart
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exporter en GPX',
            onPressed: () async {
              final points =
                  await context.read<RidesProvider>().pointsOf(rideId);
              await RideExportService().shareGpx(ride, points);
            },
          ),
```

- [ ] **Step 6: Persister les traces importées**

Dans `lib/providers/trace_provider.dart`, ajouter les imports :

```dart
import 'package:uuid/uuid.dart';
import '../models/ride.dart';
import '../services/ride_repository.dart';
```

Ajouter la méthode privée à la fin de la classe :

```dart
  // ── Sauvegarde d'une trace importée ──────────────────────
  // Une trace importée devient une sortie d'origine "imported" : elle
  // survit à la fermeture de l'app et devient éditable au lot 2.
  Future<void> _persist(TraceModel trace, RideRepository repo) async {
    final rideId = const Uuid().v4();
    final started = trace.date ?? DateTime.now();
    final points = <RidePoint>[];
    for (int i = 0; i < trace.points.length; i++) {
      final p = trace.points[i];
      points.add(RidePoint(
        rideId:    rideId,
        seq:       i,
        segment:   0,
        lat:       p.position.latitude,
        lng:       p.position.longitude,
        altitude:  p.elevation,
        speedKmh:  p.speed ?? 0,
        timestamp: p.time ?? started,
      ));
    }
    await repo.insertRide(Ride(
      id:        rideId,
      name:      trace.name,
      startedAt: started,
      endedAt:   started,
      source:    RideSource.imported,
      status:    RideStatus.finished,
      stats:     RideStats.fromPoints(points),
    ));
    await repo.appendPoints(points);
  }
```

Modifier la signature d'`importFromFile` et d'`importFromUrl` pour accepter
`{RideRepository? repository}`, et appeler `_persist` juste avant le
`return true` de chacune :

```dart
    if (repository != null) await _persist(trace, repository);
```

Dans `lib/widgets/gpx_import_sheet.dart`, passer le dépôt aux deux appels
d'import via `context.read<RideRepository>()` — ajouter pour cela un
`Provider<RideRepository>.value(value: rideRepository)` dans la liste
`providers` de `lib/main.dart`.

- [ ] **Step 7: Vérifier**

Run: `flutter analyze && flutter test`
Expected: aucune erreur, tous les tests passent.

Run: `flutter run` — exporter une sortie et vérifier que le menu de partage
Android s'ouvre avec un fichier `.gpx`. Importer ce même fichier, fermer
l'application, la rouvrir, vérifier que la trace importée est toujours dans
l'onglet Sorties.

- [ ] **Step 8: Commit**

```bash
git add lib/services/ride_export_service.dart test/services/ride_export_service_test.dart lib/providers/trace_provider.dart lib/screens/rides/ride_detail_screen.dart lib/widgets/gpx_import_sheet.dart lib/main.dart
git commit -m "feat: export GPX des sorties et persistance des traces importées"
```

---

## Task 13: Réglages, calibration guidée et section Info

**Files:**
- Create: `lib/screens/settings/vibration_calibration_screen.dart`
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/widgets/recording_panel.dart`
- Modify: `lib/app/router.dart`

**Interfaces:**
- Consumes: `SettingsProvider` (Task 7), `VibrationCalibration` (Task 5), `VibrationMeter` (Task 4), `sensors_plus`
- Produces: `VibrationCalibrationScreen` ; route `AppRoutes.calibration` (`/calibration`) ; clé de préférence `calibration_prompt_shown`

- [ ] **Step 1: Écrire l'écran de calibration**

Create `lib/screens/settings/vibration_calibration_screen.dart` :

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../services/vibration_calibration.dart';
import '../../services/vibration_meter.dart';

enum _Phase { intro, still, idle, done }

class VibrationCalibrationScreen extends StatefulWidget {
  const VibrationCalibrationScreen({super.key});

  @override
  State<VibrationCalibrationScreen> createState() =>
      _VibrationCalibrationScreenState();
}

class _VibrationCalibrationScreenState
    extends State<VibrationCalibrationScreen> {
  static const Duration _measureDuration = Duration(seconds: 10);

  final _meter = VibrationMeter(windowSize: 500);
  StreamSubscription? _sub;
  Timer? _timer;

  _Phase _phase = _Phase.intro;
  int _remaining = 0;
  double? _stillLevel;
  double? _idleLevel;

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream().listen((e) {
      _meter.addSample(VibrationMeter.magnitudeOf(e.x, e.y, e.z));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _measure(_Phase phase) {
    _meter.reset();
    setState(() {
      _phase = phase;
      _remaining = _measureDuration.inSeconds;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      setState(() => _remaining--);
      if (_remaining > 0) return;
      t.cancel();
      final level = _meter.level;
      if (phase == _Phase.still) {
        setState(() => _stillLevel = level);
      } else {
        setState(() {
          _idleLevel = level;
          _phase = _Phase.done;
        });
        await VibrationCalibration(stillLevel: _stillLevel, idleLevel: level)
            .save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CALIBRER LES VIBRATIONS')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_phase) {
          _Phase.intro => _intro(),
          _Phase.still => _countdown(
              'Moteur coupé, téléphone en place.\nNe touchez à rien.'),
          _Phase.idle => _countdown(
              'Démarrez le moteur et laissez-le tourner au ralenti.'),
          _Phase.done => _result(),
        },
      ),
    );
  }

  Widget _intro() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'La calibration apprend à l\'application ce que « immobile » veut '
            'dire pour votre moto et pour la position de votre téléphone.\n\n'
            'Deux mesures de 10 secondes : moteur coupé, puis moteur au '
            'ralenti. Installez le téléphone comme quand vous roulez.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => _measure(_Phase.still),
            child: const Text('Commencer'),
          ),
        ],
      );

  Widget _countdown(String instruction) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          Text('$_remaining',
              style: const TextStyle(
                  fontSize: 64, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (_phase == _Phase.still && _stillLevel != null)
            const Text('Mesure 1 terminée'),
        ],
      );

  Widget _result() {
    final cal =
        VibrationCalibration(stillLevel: _stillLevel, idleLevel: _idleLevel);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Immobile : ${_stillLevel!.toStringAsFixed(3)}'),
        Text('Ralenti : ${_idleLevel!.toStringAsFixed(3)}'),
        const SizedBox(height: 12),
        Text('Seuil retenu : ${cal.threshold.toStringAsFixed(3)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 20),
        if (!cal.isCalibrated)
          const Text(
            'Mesures incohérentes : le ralenti doit vibrer davantage que '
            'l\'arrêt moteur. Le seuil par défaut reste utilisé. '
            'Recommencez en installant le téléphone comme quand vous roulez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFF9A825)),
          ),
        const SizedBox(height: 20),
        // Test en direct : sans lui, on calibre à l'aveugle.
        StreamBuilder<int>(
          stream: Stream.periodic(const Duration(milliseconds: 400), (i) => i),
          builder: (_, __) {
            final live = _meter.level;
            final immobile = live < cal.threshold;
            return Text(
              immobile
                  ? 'Test en direct : immobile ✓'
                  : 'Test en direct : en mouvement',
              style: TextStyle(
                  color: immobile
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFEF5350)),
            );
          },
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => _measure(_Phase.still),
              child: const Text('Recommencer'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminer'),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Déclarer la route**

Dans `lib/app/router.dart`, ajouter
`static const String calibration = '/calibration';` à `AppRoutes`, l'import de
l'écran, puis une route hors du shell, à côté des modals existants :

```dart
    GoRoute(
      path: AppRoutes.calibration,
      pageBuilder: (_, __) => const MaterialPage(
          fullscreenDialog: true, child: VibrationCalibrationScreen()),
    ),
```

- [ ] **Step 3: Ajouter la section Enregistrement aux Réglages**

Dans `lib/screens/settings/settings_screen.dart`, ajouter une section
« ENREGISTREMENT » construite sur le même modèle visuel que les sections
existantes, contenant :

```dart
        SwitchListTile(
          title: const Text('Pause automatique'),
          subtitle: const Text(
              'Suspend l\'enregistrement à l\'arrêt, moteur coupé.'),
          value: settings.autoPauseEnabled,
          onChanged: settings.setAutoPauseEnabled,
        ),
        ListTile(
          title: const Text('Seuil de la pause automatique'),
          subtitle: const Text('Vitesse en dessous de laquelle on considère '
              'que la moto est arrêtée.'),
          trailing: DropdownButton<int>(
            value: settings.pauseSpeedKmh,
            items: SettingsProvider.pauseSpeedChoices
                .map((v) => DropdownMenuItem(value: v, child: Text('$v km/h')))
                .toList(),
            onChanged: (v) => v == null ? null : settings.setPauseSpeedKmh(v),
          ),
        ),
        SwitchListTile(
          title: const Text('Demander le nom à l\'arrêt'),
          subtitle: const Text('Sinon, un nom automatique est donné, '
              'modifiable depuis l\'onglet Sorties.'),
          value: settings.askNameOnStop,
          onChanged: settings.setAskNameOnStop,
        ),
        SwitchListTile(
          title: const Text('Proposer de démarrer l\'enregistrement'),
          subtitle: const Text('Quand l\'application détecte un roulage.'),
          value: settings.suggestAutoStart,
          onChanged: settings.setSuggestAutoStart,
        ),
        SwitchListTile(
          title: const Text('Garder l\'écran allumé sur la carte'),
          subtitle: const Text('Pour le guidage, téléphone sur le guidon.'),
          value: settings.keepScreenOnMap,
          onChanged: settings.setKeepScreenOnMap,
        ),
        SwitchListTile(
          title: const Text('Afficher les distances en miles'),
          value: settings.useMiles,
          onChanged: settings.setUseMiles,
        ),
        ListTile(
          leading: const Icon(Icons.vibration),
          title: const Text('Calibrer les vibrations'),
          subtitle: const Text('20 secondes, pour une pause automatique '
              'fiable sur votre moto.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.calibration),
        ),
```

Ajouter les imports nécessaires : `go_router`, `AppRoutes`, `SettingsProvider`.

- [ ] **Step 4: Descendre le contenu d'Info dans les Réglages**

`InfoScreen` n'est plus atteignable depuis la barre de navigation. Déplacer son
contenu dans une section « INFO » de l'écran Réglages, à la fin. Le plus simple
et le moins risqué : conserver `info_screen.dart` et l'inclure comme section
repliable :

```dart
        ExpansionTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('INFO'),
          children: const [InfoScreen(embedded: true)],
        ),
```

Ajouter à `InfoScreen` un paramètre `final bool embedded;` valant `false` par
défaut, et dans son `build`, renvoyer directement le corps sans `Scaffold` ni
`AppBar` quand `embedded` vaut `true`.

- [ ] **Step 5: Inviter à calibrer après la première sortie**

Dans `lib/widgets/recording_panel.dart`, méthode `_stop`, après l'affichage du
`SnackBar` :

```dart
      final prefs = await SharedPreferences.getInstance();
      final dejaPropose = prefs.getBool('calibration_prompt_shown') ?? false;
      final cal = await VibrationCalibration.load();
      if (!dejaPropose && !cal.isCalibrated && context.mounted) {
        await prefs.setBool('calibration_prompt_shown', true);
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Calibrer les vibrations ?'),
            content: const Text(
                'La pause automatique sera bien plus fiable si l\'application '
                'connaît les vibrations de votre moto. Cela prend '
                '20 secondes.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Plus tard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Calibrer'),
              ),
            ],
          ),
        );
        if (go == true && context.mounted) context.push(AppRoutes.calibration);
      }
```

avec les imports `shared_preferences`, `go_router`, `AppRoutes` et
`VibrationCalibration`.

- [ ] **Step 6: Vérifier**

Run: `flutter analyze && flutter test`
Expected: aucune erreur, tous les tests passent.

Run: `flutter run` — ouvrir Réglages, vérifier les sept réglages et la section
Info, lancer la calibration, vérifier les deux comptes à rebours, le résultat
chiffré et le test en direct.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/settings/ lib/screens/info/info_screen.dart lib/widgets/recording_panel.dart lib/app/router.dart
git commit -m "feat: réglages d'enregistrement, calibration guidée et section Info"
```

---

## Task 14: Écran conditionnel, récupération après plantage, contacts persistés

Quatre correctifs indépendants qui referment le lot.

**Files:**
- Modify: `lib/main.dart:49`
- Modify: `lib/screens/map/map_screen.dart`
- Modify: `lib/screens/rides/rides_screen.dart`
- Modify: `lib/providers/solo_provider.dart`
- Test: `test/providers/solo_provider_test.dart`

**Interfaces:**
- Consumes: `SettingsProvider.keepScreenOnMap` (Task 7), `RideRepository.findUnfinishedRide` (Task 3), `MapProvider.followPosition` (existant)
- Produces: sur `SoloProvider` : `Future<void> loadContacts()`, persistance automatique dans `addContact` et `removeContact`

- [ ] **Step 1: Rendre le maintien d'écran conditionnel**

Dans `lib/main.dart`, **supprimer** les deux lignes :

```dart
  // Maintenir l'écran allumé par défaut (navigation active)
  WakelockPlus.enable();
```

ainsi que l'import `package:wakelock_plus/wakelock_plus.dart` s'il devient
inutilisé.

Dans `lib/screens/map/map_screen.dart`, ajouter l'import de `wakelock_plus` et,
dans l'`initState` / le `dispose` de l'état de l'écran :

```dart
  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }
```

et dans la méthode `build`, avant le `return`, synchroniser l'état :

```dart
    // Écran maintenu allumé uniquement en guidage : carte affichée et suivi
    // de position actif. Ailleurs, l'écran s'éteint normalement.
    final keepOn = context.watch<SettingsProvider>().keepScreenOnMap &&
        mapProv.followPosition;
    WakelockPlus.toggle(enable: keepOn);
```

- [ ] **Step 2: Vérifier le comportement de l'écran**

Run: `flutter run`
Expected: sur l'onglet Météo, l'écran s'éteint après le délai système. Sur la
carte avec le suivi actif, il reste allumé. Suivi désactivé : il s'éteint.

- [ ] **Step 3: Proposer la reprise d'une sortie interrompue**

Dans `lib/screens/rides/rides_screen.dart`, dans `initState`, après le
`refresh()` :

```dart
      final open = await context.read<RidesProvider>().findUnfinished();
```

Ajouter à `RidesProvider` :

```dart
  Future<Ride?> findUnfinished() => _repo.findUnfinishedRide();

  Future<void> closeUnfinished(Ride ride) async {
    final points = await _repo.pointsOf(ride.id);
    await _repo.updateRide(ride.copyWith(
      status:  RideStatus.finished,
      endedAt: points.isEmpty ? ride.startedAt : points.last.timestamp,
      stats:   RideStats.fromPoints(points),
    ));
    await refresh();
  }
```

Afficher un bandeau non bloquant en tête de la liste quand une sortie est
restée ouverte :

```dart
  Widget _recoveryBanner(Ride ride) => MaterialBanner(
        content: Text('La sortie « ${ride.name} » a été interrompue.'),
        leading: const Icon(Icons.warning_amber),
        actions: [
          TextButton(
            onPressed: () => context.read<RidesProvider>().closeUnfinished(ride),
            child: const Text('Clôturer'),
          ),
          TextButton(
            onPressed: () => context.read<RidesProvider>().remove(ride.id),
            child: const Text('Supprimer'),
          ),
        ],
      );
```

Stocker la sortie interrompue dans l'état de `_RidesScreenState` et placer le
bandeau au-dessus de la `ListView` dans une `Column`.

- [ ] **Step 4: Écrire le test de persistance des contacts**

Create `test/providers/solo_provider_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/solo_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les contacts survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur');

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts.length, 1);
    expect(reloaded.contacts.first.name, 'Claire');
    expect(reloaded.contacts.first.phone, '+33600000000');
  });

  test('la suppression est persistée elle aussi', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur');
    await s.removeContact(s.contacts.first.id);

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts, isEmpty);
  });

  test('la limite de trois contacts est conservée', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    for (int i = 0; i < 5; i++) {
      await s.addContact(name: 'C$i', phone: '060000000$i', relation: 'Ami');
    }
    expect(s.contacts.length, 3);
  });
}
```

- [ ] **Step 5: Vérifier que le test échoue**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: échec, `loadContacts` n'existe pas et `addContact` n'est pas
asynchrone.

- [ ] **Step 6: Persister les contacts**

Dans `lib/providers/solo_provider.dart`, ajouter les imports
`dart:convert` et `package:shared_preferences/shared_preferences.dart`,
donner à `TrustedContact` une conversion JSON :

```dart
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'phone': phone, 'relation': relation,
  };

  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    id:       j['id'] as String,
    name:     j['name'] as String,
    phone:    j['phone'] as String,
    relation: j['relation'] as String,
  );
```

puis dans `SoloProvider` :

```dart
  static const _kContacts = 'trusted_contacts';

  Future<void> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContacts);
    _contacts.clear();
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _contacts.addAll(list
          .map((e) => TrustedContact.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kContacts,
      jsonEncode(_contacts.map((c) => c.toJson()).toList()),
    );
  }
```

Rendre `addContact` et `removeContact` asynchrones et appeler `_saveContacts()`
avant `notifyListeners()`. Adapter les appels dans `solo_screen.dart`.

Dans `lib/main.dart`, charger les contacts au démarrage, sur le modèle de
`SettingsProvider` :

```dart
        ChangeNotifierProvider(create: (_) {
          final s = SoloProvider();
          s.loadContacts();
          return s;
        }),
```

- [ ] **Step 7: Vérifier l'ensemble**

Run: `flutter test && flutter analyze`
Expected: tous les tests passent, aucune erreur.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/screens/map/map_screen.dart lib/screens/rides/rides_screen.dart lib/providers/rides_provider.dart lib/providers/recording_provider.dart lib/widgets/recording_panel.dart lib/providers/solo_provider.dart lib/screens/solo/solo_screen.dart test/providers/
git commit -m "fix: écran allumé conditionnel, reprise après plantage, contacts persistés"
```

---

- [ ] **Step 9: Afficher l'espace occupé (spec §5.4)**

`RideDatabase.sizeBytes()` existe depuis la Task 3 et n'est pas encore
utilisé. L'afficher en pied de l'onglet Sorties rend visible le coût des
traces, qu'aucune compression ne réduit dans ce lot.

Dans `lib/screens/rides/rides_screen.dart`, ajouter sous la liste :

```dart
  Widget _storageFooter() => FutureBuilder<int>(
        future: RideDatabase.sizeBytes(),
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final mo = snap.data! / (1024 * 1024);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${provider.rides.length} sorties · '
              '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo occupés',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          );
        },
      );
```

avec l'import `import '../../services/ride_database.dart';`, et le placer dans
la `Column` sous la `ListView`.

- [ ] **Step 10: Rappel « Toujours en balade ? » (spec §8)**

Filet pour le cas non couvert par la pause automatique : le pilote descend de
moto et s'éloigne à pied, donc au-dessus du seuil de vitesse et téléphone
secoué par ses pas.

Dans `lib/providers/recording_provider.dart`, ajouter les champs :

```dart
  static const Duration _reminderAfter = Duration(minutes: 15);
  static const double _reminderSpeedKmh = 10;

  DateTime? _slowSince;
  bool _reminderShown = false;
  bool get shouldRemindPause => _reminderShown == false && _slowSince != null &&
      DateTime.now().difference(_slowSince!) >= _reminderAfter;

  void acknowledgeReminder() {
    _reminderShown = true;
    notifyListeners();
  }
```

et, dans `onGpsSample`, après l'appel à `rec.onSample` :

```dart
    if (rec.state == RecorderState.recording) {
      if (gps.speedKmh < _reminderSpeedKmh) {
        _slowSince ??= gps.timestamp;
      } else {
        _slowSince = null;
        _reminderShown = false;
      }
    }
```

Réinitialiser `_slowSince` et `_reminderShown` dans `startRide`.

Dans `lib/widgets/recording_panel.dart`, afficher dans `_RecordingBar` un
`MaterialBanner` quand `rec.shouldRemindPause` vaut vrai, proposant
« Mettre en pause » (appelle `togglePause`) et « Continuer » (appelle
`acknowledgeReminder`).

Ajouter le test correspondant dans `test/providers/recording_provider_test.dart` :

```dart
  test('le rappel se déclenche après 15 min sous 10 km/h', () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());
    provider.onGpsSample(_gps(4, 0));
    expect(provider.shouldRemindPause, isFalse);
    // Un échantillon 16 minutes plus tard, toujours lent.
    provider.onGpsSample(_gps(4, 960));
    expect(provider.shouldRemindPause, isTrue);
    provider.acknowledgeReminder();
    expect(provider.shouldRemindPause, isFalse);
  });
```

Attention : `shouldRemindPause` compare à `DateTime.now()` alors que
`_slowSince` vient de l'horodatage GPS. En test, les deux doivent partager la
même base de temps — remplacer `DateTime.now()` par l'horodatage du dernier
échantillon reçu, stocké dans un champ `_lastSampleAt`.


## Vérification finale du lot

Une fois les 14 tâches terminées, dérouler les 7 critères de réussite du spec
sur un appareil réel :

1. Enregistrement qui continue écran éteint et application quittée, notification
   dont la distance progresse.
2. Arrêt moteur coupé de plus de 30 s → pause automatique. Franchissement sous
   2 km/h moteur tournant → pas de pause.
3. Coupure brutale (forcer l'arrêt depuis les réglages Android) → sortie
   récupérable au redémarrage.
4. Sortie terminée visible dans l'onglet Sorties, exportable en GPX, et ce GPX
   réimportable dans l'application.
5. Trace GPX importée toujours présente après redémarrage.
6. Écran qui s'éteint normalement sur Météo et Réglages.
7. `flutter test` : toute la machine à états couverte, sans matériel.
