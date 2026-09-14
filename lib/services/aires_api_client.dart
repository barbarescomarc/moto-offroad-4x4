import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/aire.dart';

/// Le serveur n'a pas répondu, ou a répondu autre chose que des aires.
class AiresIndisponibles implements Exception {
  const AiresIndisponibles(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Un relevé refusé, avec la raison telle que le serveur l'a formulée.
class ContributionRefusee implements Exception {
  const ContributionRefusee(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Les aires de camping-car, servies par le hub.
///
/// Pourquoi passer par le serveur plutôt qu'interroger Overpass directement
/// comme le fait la recherche de carburant : Overpass public rend la même
/// requête en cinq secondes ou en 504 selon l'heure. Un pilote qui cherche
/// une aire à 19 h ne le fait qu'une fois.
class AiresApiClient {
  AiresApiClient({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? readToken,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org',
        _readToken = readToken;

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function()? _readToken;

  static const Duration _delai = Duration(seconds: 12);

  /// Les aires du rectangle affiché. Le serveur refuse au-delà de 5° de côté.
  Future<List<AireModel>> dansRectangle({
    required double sud,
    required double ouest,
    required double nord,
    required double est,
    int? limite,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/aires').replace(queryParameters: {
      'bbox': '$sud,$ouest,$nord,$est',
      if (limite != null) 'limite': '$limite',
    });

    final http.Response reponse;
    try {
      reponse = await _client.get(uri).timeout(_delai);
    } catch (erreur) {
      throw AiresIndisponibles('$erreur');
    }
    if (reponse.statusCode != 200) {
      throw AiresIndisponibles('serveur ${reponse.statusCode}');
    }

    final Map<String, dynamic> corps;
    try {
      corps = jsonDecode(reponse.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AiresIndisponibles('réponse illisible');
    }
    final brutes = corps['aires'] as List<dynamic>? ?? const [];
    return brutes
        .map((a) => AireModel.depuisJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Envoie un relevé. Réservé aux comptes vérifiés côté serveur.
  ///
  /// Rend l'aire telle qu'elle est après coup n'aurait pas de sens : le
  /// serveur peut avoir retenu la valeur, ou l'avoir mise en attente d'un
  /// second avis. C'est cet état qu'on rend, pour que la fiche le dise.
  Future<String> contribuer({
    required String aireId,
    required ChampAire champ,
    required Object valeur,
    DateTime? vuLe,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    final readToken = _readToken;
    if (readToken != null) {
      try {
        final token = await readToken();
        if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      } catch (_) {}
    }

    final uri = Uri.parse('$_baseUrl/api/aires/$aireId/contribution');
    final http.Response reponse;
    try {
      reponse = await _client
          .post(uri,
              headers: headers,
              body: jsonEncode({
                'champ': champ.cleServeur,
                'valeur': valeur,
                if (vuLe != null) 'vuLe': vuLe.millisecondsSinceEpoch,
              }))
          .timeout(_delai);
    } catch (erreur) {
      throw ContributionRefusee('envoi impossible : $erreur');
    }

    if (reponse.statusCode == 201) {
      final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
      return corps['etat'] as String? ?? 'proposee';
    }
    if (reponse.statusCode == 401) {
      throw const ContributionRefusee('connecte-toi pour compléter une aire');
    }
    try {
      final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
      throw ContributionRefusee(corps['error'] as String? ?? 'relevé refusé');
    } on ContributionRefusee {
      rethrow;
    } catch (_) {
      throw ContributionRefusee('relevé refusé (${reponse.statusCode})');
    }
  }

  void dispose() => _client.close();
}
