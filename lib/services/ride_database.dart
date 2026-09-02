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
