import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_reply.dart';

// ── Les trois réponses rapides du bandeau d'appel ────────────
//
// Le nombre est fixe : Android n'affiche que trois boutons d'action dans une
// notification. Les textes et l'ajout de la position sont modifiables.
class QuickReplyProvider extends ChangeNotifier {
  static const _kReplies = 'quick_replies';
  static const int maxReplies = 3;

  static List<QuickReply> get defaults => const [
    QuickReply(id: 'r1', text: 'Je roule, je ne peux pas répondre', attachPosition: false),
    QuickReply(id: 'r2', text: 'Je roule, je suis ici',            attachPosition: true),
    QuickReply(id: 'r3', text: "Tout va bien, j'arrive",           attachPosition: false),
  ];

  List<QuickReply> _replies = List.of(defaults);
  List<QuickReply> get replies => List.unmodifiable(_replies);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kReplies);
    _replies = _decode(raw);
    notifyListeners();
  }

  // Une sauvegarde corrompue ou incomplète ne doit pas priver le pilote de ses
  // réponses : chaque identifiant manquant reprend sa valeur par défaut.
  List<QuickReply> _decode(String? raw) {
    if (raw == null) return List.of(defaults);
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => QuickReply.fromJson(e as Map<String, dynamic>))
          .toList();
      return defaults
          .map((d) => list.firstWhere((r) => r.id == d.id, orElse: () => d))
          .toList();
    } catch (_) {
      return List.of(defaults);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kReplies,
      jsonEncode(_replies.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> updateReply(String id, {String? text, bool? attachPosition}) async {
    final index = _replies.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final fallback = defaults.firstWhere((d) => d.id == id).text;
    final cleaned = text?.trim();
    _replies[index] = _replies[index].copyWith(
      text:           cleaned == null ? null : (cleaned.isEmpty ? fallback : cleaned),
      attachPosition: attachPosition,
    );
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _replies = List.of(defaults);
    await _save();
    notifyListeners();
  }
}
