import 'package:sqflite/sqflite.dart';

import '../models/aire.dart';
import 'ride_database.dart';

/// Les aires gardées sur le téléphone.
///
/// Un camping-car cherche une aire précisément là où il n'y a pas de réseau :
/// ce cache n'est pas une optimisation, c'est ce qui fait que la
/// fonctionnalité existe au moment où elle sert.
class AiresCache {
  AiresCache({Future<Database> Function()? ouvrir})
      : _ouvrir = ouvrir ?? RideDatabase.open;

  final Future<Database> Function() _ouvrir;

  /// Remplace les aires d'un rectangle par celles qu'on vient de recevoir.
  ///
  /// Effacer d'abord le rectangle plutôt que de simplement insérer : une aire
  /// supprimée en amont doit disparaître du téléphone aussi, sans quoi le
  /// cache accumulerait indéfiniment des aires qui n'existent plus.
  Future<void> remplacerZone({
    required double sud,
    required double ouest,
    required double nord,
    required double est,
    required List<AireModel> aires,
    DateTime? le,
  }) async {
    final db = await _ouvrir();
    final at = (le ?? DateTime.now()).millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete('aires',
          where: 'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
          whereArgs: [sud, nord, ouest, est]);
      for (final aire in aires) {
        await txn.insert('aires', aire.versLigneSqlite(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete('aires_zone',
          where: 'sud = ? AND ouest = ? AND nord = ? AND est = ?',
          whereArgs: [sud, ouest, nord, est]);
      await txn.insert('aires_zone', {
        'sud': sud, 'ouest': ouest, 'nord': nord, 'est': est, 'charge_le': at,
      });
    });
  }

  Future<List<AireModel>> dansRectangle({
    required double sud,
    required double ouest,
    required double nord,
    required double est,
  }) async {
    final db = await _ouvrir();
    final lignes = await db.query('aires',
        where: 'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
        whereArgs: [sud, nord, ouest, est]);
    return lignes.map(AireModel.depuisLigneSqlite).toList();
  }

  /// Quand ce rectangle a-t-il été téléchargé ? `null` s'il ne l'a jamais été.
  ///
  /// Sert à écrire « données du 12 septembre » sur la fiche : laisser croire
  /// qu'un cache de trois mois est à jour serait pire que ne rien afficher.
  Future<DateTime?> chargeeLe({
    required double sud,
    required double ouest,
    required double nord,
    required double est,
  }) async {
    final db = await _ouvrir();
    final lignes = await db.query('aires_zone',
        where: 'sud <= ? AND ouest <= ? AND nord >= ? AND est >= ?',
        whereArgs: [sud, ouest, nord, est],
        orderBy: 'charge_le DESC',
        limit: 1);
    if (lignes.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(lignes.first['charge_le'] as int);
  }

  Future<int> compter() async {
    final db = await _ouvrir();
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM aires');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> vider() async {
    final db = await _ouvrir();
    await db.delete('aires');
    await db.delete('aires_zone');
  }
}
