import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Compare deux numéros de version du type « 1.2.3 ».
///
/// Renvoie un nombre positif si [a] est plus récent que [b], zéro si les deux
/// désignent la même version, un nombre négatif sinon. Le préfixe « v » et le
/// numéro de build (« 1.2.3+7 ») sont ignorés : ils ne distinguent pas deux
/// versions aux yeux de l'utilisateur.
///
/// La comparaison se fait segment par segment, en nombres. Comparés comme du
/// texte, « 1.0.10 » passerait avant « 1.0.9 » et une mise à jour sur dix ne
/// serait jamais annoncée.
int compareVersions(String a, String b) {
  final va = _segments(a);
  final vb = _segments(b);
  final longueur = va.length > vb.length ? va.length : vb.length;
  for (var i = 0; i < longueur; i++) {
    final x = i < va.length ? va[i] : 0;
    final y = i < vb.length ? vb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

List<int> _segments(String version) {
  final nettoye = version.trim().replaceFirst(RegExp(r'^v'), '').split('+').first;
  return nettoye.split('.').map((s) => int.tryParse(s) ?? -1).toList();
}

/// Une version publiée plus récente que celle qui tourne.
class UpdateInfo {
  final String version;
  final String url;
  const UpdateInfo({required this.version, required this.url});
}

/// Interroge les Releases GitHub pour savoir si une version plus récente est
/// disponible.
///
/// L'application est distribuée hors magasin : personne ne prévient
/// l'utilisateur à notre place. Mais une mise à jour n'est jamais urgente, donc
/// toute panne — réseau absent, GitHub en vrac, réponse inattendue — se solde
/// par un silence et non par une erreur affichée au milieu d'une balade.
class UpdateChecker {
  UpdateChecker._();

  static const String repo = 'barbarescomarc/moto-offroad-4x4';

  /// Lien permanent : sert toujours l'APK de la dernière Release.
  static const String downloadUrl =
      'https://github.com/$repo/releases/latest/download/moto-offroad.apk';

  static const String _apiUrl =
      'https://api.github.com/repos/$repo/releases/latest';

  static const String _kDerniereVerif = 'update_last_check';

  /// Délai minimum entre deux interrogations de GitHub.
  static const Duration intervalle = Duration(days: 1);

  /// Interroge GitHub sans tenir compte de la date de dernière vérification.
  static Future<UpdateInfo?> fetchLatest({
    required String currentVersion,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final reponse = await c
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));
      if (reponse.statusCode != 200) return null;

      final corps = jsonDecode(reponse.body);
      if (corps is! Map) return null;
      final tag = corps['tag_name'];
      if (tag is! String || tag.isEmpty) return null;

      final version = tag.replaceFirst(RegExp(r'^v'), '');
      if (compareVersions(version, currentVersion) <= 0) return null;
      return UpdateInfo(version: version, url: downloadUrl);
    } catch (_) {
      // Silence volontaire : voir la note de classe.
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Comme [fetchLatest], mais au plus une fois par [intervalle].
  ///
  /// [force] contourne cette limite, pour le bouton « Vérifier maintenant »
  /// des réglages : quand l'utilisateur demande explicitement, il attend une
  /// réponse, pas un silence parce que l'appli a déjà regardé ce matin.
  static Future<UpdateInfo?> checkIfDue({
    required String currentVersion,
    bool force = false,
    http.Client? client,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final maintenant = DateTime.now().millisecondsSinceEpoch;

    if (!force) {
      final precedent = prefs.getInt(_kDerniereVerif) ?? 0;
      if (maintenant - precedent < intervalle.inMilliseconds) return null;
    }

    // La date est notée avant l'appel : si GitHub est injoignable, on ne
    // réessaie pas à chaque ouverture de l'écran.
    await prefs.setInt(_kDerniereVerif, maintenant);
    return fetchLatest(currentVersion: currentVersion, client: client);
  }
}
