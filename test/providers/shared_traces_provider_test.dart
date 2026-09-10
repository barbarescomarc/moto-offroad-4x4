import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/providers/shared_traces_provider.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

// Fiche minimale valide, pour ne pas répéter tous les champs obligatoires
// dans chaque test qui n'a besoin que d'un identifiant reconnaissable.
SharedTraceSummary resume(String id) => SharedTraceSummary(
      id: id,
      name: 'Trace $id',
      authorName: 'Un rider',
      vehicle: TraceVehicle.moto,
      difficulty: TraceDifficulty.moyen,
      distanceM: 10000,
      publishedAt: DateTime(2026, 1, 1),
      downloadCount: 0,
      startLat: 43.6,
      startLng: 1.44,
    );

// Double de test : capture les appels plutôt que de taper un vrai réseau, et
// laisse le test choisir la réponse ou l'échec à renvoyer. Les paramètres
// suivent la signature nullable du vrai client (aucun n'est requis côté
// serveur) : c'est le provider qui décide toujours de ce qu'il envoie.
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice()
      : super(
          client: MockClient((_) async => http.Response('', 200)),
          readToken: () async => 'jeton',
        );

  final List<Map<String, Object?>> appels = [];
  List<SharedTraceSummary> reponse = [];
  Object? erreur;

  @override
  Future<List<SharedTraceSummary>> list({
    double? lat,
    double? lng,
    double? radiusKm,
    TraceVehicle? vehicle,
    TraceDifficulty? difficulty,
    String? query,
    int? offset,
  }) async {
    appels.add({'lat': lat, 'rayon': radiusKm, 'engin': vehicle, 'depuis': offset});
    if (erreur != null) throw erreur!;
    return reponse;
  }
}

void main() {
  test('sans point de reference, aucune requete ne part', () async {
    final api = _ApiFactice();
    final provider = SharedTracesProvider(api);

    await provider.refresh();

    expect(api.appels, isEmpty);
    expect(provider.error, isNotNull);
  });

  test('poser la reference declenche le chargement', () async {
    final api = _ApiFactice()..reponse = [resume('t1')];
    final provider = SharedTracesProvider(api);

    await provider.setReference(const LatLng(43.6, 1.44), label: 'Ma position');

    expect(api.appels.single['lat'], 43.6);
    expect(provider.traces.single.id, 't1');
    expect(provider.referenceLabel, 'Ma position');
  });

  test('changer le rayon relance la recherche depuis le debut', () async {
    final api = _ApiFactice()..reponse = [resume('t1')];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44));

    await provider.setRadius(25);

    expect(api.appels.last['rayon'], 25);
    expect(api.appels.last['depuis'], 0);
  });

  test('loadMore ajoute a la suite sans effacer', () async {
    final api = _ApiFactice()..reponse = [resume('t1')];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44));

    api.reponse = [resume('t2')];
    await provider.loadMore();

    expect(provider.traces.map((t) => t.id), ['t1', 't2']);
    expect(api.appels.last['depuis'], 1);
  });

  test('une panne reseau laisse un message et vide le chargement', () async {
    final api = _ApiFactice()..erreur = const SharedTracesException(503, 'Le serveur ne repond pas');
    final provider = SharedTracesProvider(api);

    await provider.setReference(const LatLng(43.6, 1.44));

    expect(provider.isLoading, isFalse);
    expect(provider.error, contains('serveur'));
  });

  // Trouvaille mineure de la revue finale : ce provider est fourni une
  // seule fois pour toute l'application (voir main.dart), donc partagé
  // entre les comptes qui se succèdent sur le même téléphone.
  test('reset efface la reference, son libelle et les resultats', () async {
    final api = _ApiFactice()..reponse = [resume('t1')];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44), label: '12 rue du Sidobre');
    expect(provider.traces, isNotEmpty);

    provider.reset();

    expect(provider.reference, isNull);
    expect(provider.referenceLabel, isNull,
        reason: 'souvent une adresse cherchee par le rider precedent, elle ne doit pas survivre a son depart');
    expect(provider.traces, isEmpty);
    expect(provider.error, isNull);
  });
}
