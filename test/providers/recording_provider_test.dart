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

// Dépôt qui refuse d'écrire, pour simuler un disque plein ou une base
// verrouillée en pleine balade.
class _RepoQuiEchoue extends RideRepository {
  _RepoQuiEchoue(super.db);

  bool enPanne = true;

  @override
  Future<void> appendPoints(List<RidePoint> points) async {
    if (enPanne) throw Exception('écriture impossible');
    return super.appendPoints(points);
  }
}

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

  test('une écriture qui échoue ne perd pas les points : ils sont rejoués',
      () async {
    final repoKo = _RepoQuiEchoue(db);
    final p = RecordingProvider(repository: repoKo, service: null);
    await p.startRide(name: 'Panne disque', config: const RecorderConfig());

    for (int i = 0; i < 12; i++) {
      p.onGpsSample(_gps(40, i));
    }
    await p.flush();

    // L écriture a échoué : rien en base, mais rien de perdu non plus.
    expect(await repoKo.pointsOf(p.currentRide!.id), isEmpty);
    expect(p.hasUnsavedPoints, isTrue);

    // Le disque se libère, le flush suivant rattrape tout.
    repoKo.enPanne = false;
    await p.flush();

    expect(p.hasUnsavedPoints, isFalse);
    expect((await repoKo.pointsOf(p.currentRide!.id)).length, 12);
  });

  // Les statistiques du bandeau sont accumulées point par point pour éviter un
  // recalcul complet à chaque rafraîchissement. Ce test les tient alignées sur
  // RideStats.fromPoints, qui reste la référence : deux implémentations de la
  // même règle divergent tôt ou tard si rien ne les compare.
  test('les statistiques en direct égalent le calcul de référence, pauses comprises',
      () async {
    await provider.startRide(name: 'S', config: const RecorderConfig());

    // Roulage, pause manuelle (nouveau segment à la reprise), puis roulage.
    for (int s = 0; s < 15; s++) {
      provider.onGpsSample(_gps(40, s));
    }
    await provider.togglePause();
    await provider.togglePause();
    for (int s = 20; s < 40; s++) {
      provider.onGpsSample(_gps(55, s));
    }
    await provider.flush();

    final points = await repo.pointsOf(provider.currentRide!.id);
    final reference = RideStats.fromPoints(points);
    final live = provider.liveStats;

    expect(points.map((p) => p.segment).toSet().length, greaterThan(1),
        reason: 'le scénario doit couvrir plusieurs segments');
    expect(live.distanceMeters, closeTo(reference.distanceMeters, 0.001));
    expect(live.movingTime, reference.movingTime);
    expect(live.totalTime, reference.totalTime);
    expect(live.maxSpeedKmh, reference.maxSpeedKmh);
    expect(live.avgSpeedKmh, closeTo(reference.avgSpeedKmh, 0.001));
  });

  // Chemin complet : la perte de signal coupe la trace, et l information
  // survit à l arrêt pour que le dialogue de fusion puisse la proposer.
  test('une perte de signal survit à l arrêt et reste proposable à la fusion',
      () async {
    await provider.startRide(
      name: 'Forêt',
      config: const RecorderConfig(signalGapDelay: Duration(seconds: 90)),
    );
    for (int s = 0; s < 5; s++) {
      provider.onGpsSample(_gps(40, s));
    }
    // Trois minutes sous les arbres, puis le signal revient.
    provider.onGpsSample(_gps(40, 185));
    provider.onGpsSample(_gps(40, 186));

    final ride = await provider.stopRide();

    expect(provider.signalGapSegments, contains(1));
    final points = await repo.pointsOf(ride!.id);
    expect(points.map((p) => p.segment).toSet(), {0, 1});
  });
}
