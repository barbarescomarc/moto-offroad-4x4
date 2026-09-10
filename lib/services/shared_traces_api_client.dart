import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shared_trace.dart';

/// Levée sur toute réponse hors 2xx du catalogue partagé. [message] est déjà
/// traduit pour l'affichage : les écrans le montrent tel quel, sans
/// re-interpréter [statusCode].
class SharedTracesException implements Exception {
  final int statusCode;
  final String message;
  const SharedTracesException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Client HTTP des routes du catalogue de traces partagées.
///
/// Construit sur le modèle d'`AccountApiClient` : mêmes conventions de
/// baseUrl et d'en-têtes, mais toutes les routes exigent un jeton (le
/// catalogue n'a pas de partie publique), d'où [_headers] qui refuse avant
/// même de partir si [readToken] ne rend rien.
class SharedTracesApiClient {
  SharedTracesApiClient({http.Client? client, String? baseUrl, required this.readToken})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org';

  /// Version des conditions de publication acceptées par le rider : le
  /// serveur refuse toute publication qui ne la porte pas (400 « conditions
  /// de publication non acceptees »), il faut donc toujours l'envoyer.
  static const licenceVersion = '1.0';

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function() readToken;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  /// Formate un nombre pour l'URL : "25" pour une valeur entière, "43.6"
  /// sinon — évite le "25.0" qu'un simple `toString()` produirait sur un
  /// `double`.
  String _formatNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<Map<String, String>> _headers() async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      throw const SharedTracesException(401, 'Ta session a expiré, reconnecte-toi.');
    }
    return {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    };
  }

  String _traduire(int code, String corps) {
    switch (code) {
      case 401:
        return 'Ta session a expiré, reconnecte-toi.';
      case 403:
        return 'Vérifie ton adresse e-mail avant de publier.';
      case 404:
        return "Cette trace n'est plus disponible.";
      case 409:
        return 'Tu as déjà signalé cette trace.';
      case 410:
        return 'Le fichier de cette trace est introuvable.';
      case 413:
        return "Cette trace est trop lourde pour être publiée.";
      case 429:
        return 'Quota de publications atteint, réessaie demain.';
      default:
        return "Le serveur n'a pas répondu correctement ($code).";
    }
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode ~/ 100 != 2) {
      throw SharedTracesException(res.statusCode, _traduire(res.statusCode, res.body));
    }
  }

  /// Fait passer chaque appel réseau par un seul point de conversion : une
  /// panne de transport (pas de réseau, TLS qui échoue, timeout) ou un corps
  /// tronqué que `jsonDecode` refuse de lire ne doivent jamais fuir bruts —
  /// l'écran n'a qu'un type à attraper, `SharedTracesException`. Une
  /// exception déjà de ce type (refus explicite du serveur, jeton absent)
  /// n'est pas une panne de transport : elle repart telle quelle.
  Future<T> _guarded<T>(Future<T> Function() appel) async {
    try {
      return await appel();
    } on SharedTracesException {
      rethrow;
    } catch (_) {
      throw const SharedTracesException(0, 'Connexion impossible, réessaie quand tu auras du réseau.');
    }
  }

  /// Publie une trace. Le rider cède ses droits d'exploitation en publiant :
  /// [licenceVersion] enregistre quelle version des conditions il a
  /// acceptée, et part toujours dans la requête.
  Future<String> publish({
    required String name,
    required String description,
    required String authorName,
    required TraceVehicle vehicle,
    required TraceDifficulty difficulty,
    required String gpx,
    String licenceVersion = SharedTracesApiClient.licenceVersion,
  }) =>
      _guarded(() async {
        final headers = await _headers();
        final res = await _client.post(
          _uri('/api/traces'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'description': description,
            'authorName': authorName,
            'vehicle': vehicle.wire,
            'difficulty': difficulty.wire,
            'gpx': gpx,
            'licenceVersion': licenceVersion,
          }),
        );
        _ensureOk(res);
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return j['id'] as String;
      });

  /// Recherche des traces publiées, éventuellement autour d'un point.
  Future<List<SharedTraceSummary>> list({
    double? lat,
    double? lng,
    double? radiusKm,
    TraceVehicle? vehicle,
    TraceDifficulty? difficulty,
    String? query,
    int? offset,
  }) =>
      _guarded(() async {
        final headers = await _headers();
        final params = <String, String>{
          if (lat != null) 'lat': _formatNum(lat),
          if (lng != null) 'lng': _formatNum(lng),
          if (radiusKm != null) 'rayon': _formatNum(radiusKm),
          if (vehicle != null) 'engin': vehicle.wire,
          if (difficulty != null) 'difficulte': difficulty.wire,
          if (query != null && query.isNotEmpty) 'q': query,
          if (offset != null) 'depuis': offset.toString(),
        };
        final res = await _client.get(_uri('/api/traces', params), headers: headers);
        _ensureOk(res);
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return (j['traces'] as List<dynamic>)
            .map((e) => SharedTraceSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Fiche détaillée d'une trace.
  Future<SharedTraceDetail> detail(String id) => _guarded(() async {
        final headers = await _headers();
        final res = await _client.get(_uri('/api/traces/$id'), headers: headers);
        _ensureOk(res);
        return SharedTraceDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      });

  /// Télécharge le fichier GPX d'une trace.
  Future<String> downloadGpx(String id) => _guarded(() async {
        final headers = await _headers();
        final res = await _client.get(_uri('/api/traces/$id/gpx'), headers: headers);
        _ensureOk(res);
        return res.body;
      });

  /// Mes publications, masquées comprises.
  Future<List<SharedTraceSummary>> mine() => _guarded(() async {
        final headers = await _headers();
        final res = await _client.get(_uri('/api/traces/mine'), headers: headers);
        _ensureOk(res);
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return (j['traces'] as List<dynamic>)
            .map((e) => SharedTraceSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Modifie une de mes publications. Seuls les champs fournis changent.
  Future<void> update(
    String id, {
    String? name,
    String? description,
    String? authorName,
    TraceVehicle? vehicle,
    TraceDifficulty? difficulty,
  }) =>
      _guarded(() async {
        final headers = await _headers();
        final body = <String, dynamic>{
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (authorName != null) 'authorName': authorName,
          if (vehicle != null) 'vehicle': vehicle.wire,
          if (difficulty != null) 'difficulty': difficulty.wire,
        };
        final res = await _client.patch(_uri('/api/traces/$id'), headers: headers, body: jsonEncode(body));
        _ensureOk(res);
      });

  /// Retire une de mes publications du catalogue.
  Future<void> unpublish(String id) => _guarded(() async {
        final headers = await _headers();
        final res = await _client.delete(_uri('/api/traces/$id'), headers: headers);
        _ensureOk(res);
      });

  /// Signale une trace d'un autre auteur.
  Future<void> report(String id, {required String reason, String? detail}) => _guarded(() async {
        final headers = await _headers();
        final body = <String, dynamic>{
          'reason': reason,
          if (detail != null) 'detail': detail,
        };
        final res = await _client.post(_uri('/api/traces/$id/report'), headers: headers, body: jsonEncode(body));
        _ensureOk(res);
      });
}
