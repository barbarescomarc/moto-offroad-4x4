import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ── Base de données locale des sorties ───────────────────────
class RideDatabase {
  static const int schemaVersion = 3;
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

  // ── Création du schéma (installation neuve) ──────────────
  //
  // Construit directement le schéma courant (schemaVersion, v2 comprise :
  // shared_trace_id est déjà présente ci-dessous) — sqflite n'appelle
  // jamais onUpgrade sur une base neuve, qui n'a donc pas besoin de
  // repasser par les paliers de migration.
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
        max_speed_kmh REAL    NOT NULL DEFAULT 0,
        shared_trace_id TEXT
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

    await creerTablesAires(db);
  }

  // ── Aires de camping-car gardées hors ligne (v3) ─────────
  //
  // Un camping-car cherche une aire précisément là où il n'y a pas de
  // réseau. Le hors-ligne n'est donc pas un confort : sans lui la
  // fonctionnalité manque au moment où elle sert.
  //
  // `aires_zone` retient quel rectangle a été téléchargé et quand, pour
  // pouvoir dire à l'écran « données du 12 septembre » plutôt que de laisser
  // croire que la carte est à jour.
  static Future<void> creerTablesAires(Database db) async {
    await db.execute('''
      CREATE TABLE aires (
        id            TEXT PRIMARY KEY,
        lat           REAL    NOT NULL,
        lng           REAL    NOT NULL,
        source        TEXT    NOT NULL,
        name          TEXT,
        description   TEXT,
        services_json TEXT,
        price_text    TEXT,
        price_eur     REAL,
        capacity      INTEGER,
        max_height_m  REAL,
        max_length_m  REAL,
        opening_hours TEXT,
        phone         TEXT,
        website       TEXT,
        updated_at    INTEGER
      )
    ''');

    await db.execute('CREATE INDEX idx_aires_position ON aires (lat, lng)');

    await db.execute('''
      CREATE TABLE aires_zone (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        sud        REAL    NOT NULL,
        ouest      REAL    NOT NULL,
        nord       REAL    NOT NULL,
        est        REAL    NOT NULL,
        charge_le  INTEGER NOT NULL
      )
    ''');
  }

  // ── Migrations ───────────────────────────────────────────
  // v2 : origine d'une sortie téléchargée depuis le catalogue partagé.
  // Elle empêche de republier la trace d'un autre, et sert à afficher
  // « téléchargée depuis le partage » sur la fiche locale.
  //
  // La vérification de colonne existante rend le palier idempotent : une
  // base ouverte via onCreate (qui construit déjà le schéma courant, colonne
  // comprise, comme le veut sqflite pour une installation neuve) ne doit pas
  // faire échouer un ALTER TABLE en double si onUpgrade est rejoué dessus.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='aires'");
      if (tables.isEmpty) await creerTablesAires(db);
    }
    if (oldVersion < 2) {
      final columns = await db.rawQuery('PRAGMA table_info(rides)');
      final hasSharedTraceId = columns.any((c) => c['name'] == 'shared_trace_id');
      if (!hasSharedTraceId) {
        await db.execute('ALTER TABLE rides ADD COLUMN shared_trace_id TEXT');
      }
    }
  }

  // ── Taille occupée sur le disque ─────────────────────────
  static Future<int> sizeBytes() async {
    final path = p.join(await getDatabasesPath(), fileName);
    final file = File(path);
    return await file.exists() ? await file.length() : 0;
  }
}
