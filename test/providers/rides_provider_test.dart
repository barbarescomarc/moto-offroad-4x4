import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/providers/rides_provider.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late RideRepository repo;
  late RidesProvider provider;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version:  RideDatabase.schemaVersion,
        onCreate: RideDatabase.onCreate,
      ),
    );
    repo = RideRepository(db);
    provider = RidesProvider(repository: repo);
  });

  tearDown(() async => db.close());

  test('au départ le provider est vide et non en chargement', () async {
    expect(provider.rides, isEmpty);
    expect(provider.isLoading, isFalse);
  });

  test('refresh charge les sorties de la base', () async {
    // Insérer deux sorties de test
    final ride1 = Ride(
      id:        'ride-1',
      name:      'Sortie 1',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 5000,
        totalTime:      Duration(hours: 1),
        movingTime:     Duration(minutes: 50),
        avgSpeedKmh:    5.0,
        maxSpeedKmh:    15.0,
      ),
    );
    final ride2 = Ride(
      id:        'ride-2',
      name:      'Sortie 2',
      startedAt: DateTime(2026, 9, 2, 14, 30),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 10000,
        totalTime:      Duration(hours: 2),
        movingTime:     Duration(hours: 1, minutes: 50),
        avgSpeedKmh:    5.4,
        maxSpeedKmh:    20.0,
      ),
    );
    await repo.insertRide(ride1);
    await repo.insertRide(ride2);

    // Refresh
    await provider.refresh();

    // Vérifier que les sorties sont chargées et triées de la plus récente
    expect(provider.rides, hasLength(2));
    expect(provider.rides[0].id, 'ride-2');
    expect(provider.rides[1].id, 'ride-1');
    expect(provider.isLoading, isFalse);
  });

  test('rename met à jour le nom d une sortie', () async {
    final ride = Ride(
      id:        'ride-1',
      name:      'Ancien nom',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 0,
        totalTime:      Duration.zero,
        movingTime:     Duration.zero,
        avgSpeedKmh:    0,
        maxSpeedKmh:    0,
      ),
    );
    await repo.insertRide(ride);
    await provider.refresh();

    await provider.rename('ride-1', 'Nouveau nom');
    await provider.refresh();

    expect(provider.rides[0].name, 'Nouveau nom');
  });

  test('setNotes met à jour les notes d une sortie', () async {
    final ride = Ride(
      id:        'ride-1',
      name:      'Sortie',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 0,
        totalTime:      Duration.zero,
        movingTime:     Duration.zero,
        avgSpeedKmh:    0,
        maxSpeedKmh:    0,
      ),
    );
    await repo.insertRide(ride);
    await provider.refresh();

    await provider.setNotes('ride-1', 'Très bonne sortie!');
    await provider.refresh();

    expect(provider.rides[0].notes, 'Très bonne sortie!');
  });

  test('remove supprime une sortie et ses points', () async {
    final ride = Ride(
      id:        'ride-1',
      name:      'Sortie à supprimer',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 0,
        totalTime:      Duration.zero,
        movingTime:     Duration.zero,
        avgSpeedKmh:    0,
        maxSpeedKmh:    0,
      ),
    );
    await repo.insertRide(ride);

    // Ajouter un point
    final point = RidePoint(
      rideId:    'ride-1',
      seq:       0,
      segment:   0,
      lat:       44.0,
      lng:       6.0,
      speedKmh:  20.0,
      timestamp: DateTime(2026, 9, 1, 10, 0),
    );
    await repo.appendPoints([point]);

    // Vérifier avant suppression
    await provider.refresh();
    expect(provider.rides, hasLength(1));
    var points = await repo.pointsOf('ride-1');
    expect(points, hasLength(1));

    // Supprimer
    await provider.remove('ride-1');
    await provider.refresh();

    // Vérifier après suppression
    expect(provider.rides, isEmpty);
    points = await repo.pointsOf('ride-1');
    expect(points, isEmpty);
  });

  test('pointsOf retourne les points d une sortie', () async {
    final ride = Ride(
      id:        'ride-1',
      name:      'Sortie',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source:    RideSource.recorded,
      status:    RideStatus.finished,
      stats:     const RideStats(
        distanceMeters: 0,
        totalTime:      Duration.zero,
        movingTime:     Duration.zero,
        avgSpeedKmh:    0,
        maxSpeedKmh:    0,
      ),
    );
    await repo.insertRide(ride);

    // Ajouter trois points
    final points = [
      RidePoint(
        rideId:    'ride-1',
        seq:       0,
        segment:   0,
        lat:       44.0,
        lng:       6.0,
        speedKmh:  10.0,
        timestamp: DateTime(2026, 9, 1, 10, 0),
      ),
      RidePoint(
        rideId:    'ride-1',
        seq:       1,
        segment:   0,
        lat:       44.001,
        lng:       6.001,
        speedKmh:  15.0,
        timestamp: DateTime(2026, 9, 1, 10, 1),
      ),
      RidePoint(
        rideId:    'ride-1',
        seq:       2,
        segment:   0,
        lat:       44.002,
        lng:       6.002,
        speedKmh:  20.0,
        timestamp: DateTime(2026, 9, 1, 10, 2),
      ),
    ];
    await repo.appendPoints(points);

    final retrieved = await provider.pointsOf('ride-1');
    expect(retrieved, hasLength(3));
    expect(retrieved[0].seq, 0);
    expect(retrieved[1].seq, 1);
    expect(retrieved[2].seq, 2);
  });

  test('rename d une sortie inexistante ne fait rien', () async {
    await provider.refresh();
    expect(provider.rides, isEmpty);

    // Aucune erreur
    await provider.rename('inexistant', 'Nouveau nom');
    expect(provider.rides, isEmpty);
  });

  test('setNotes d une sortie inexistante ne fait rien', () async {
    await provider.refresh();
    expect(provider.rides, isEmpty);

    // Aucune erreur
    await provider.setNotes('inexistant', 'Notes');
    expect(provider.rides, isEmpty);
  });

  test('remove d une sortie inexistante ne fait rien', () async {
    await provider.refresh();
    expect(provider.rides, isEmpty);

    // Aucune erreur
    await provider.remove('inexistant');
    expect(provider.rides, isEmpty);
  });
}
