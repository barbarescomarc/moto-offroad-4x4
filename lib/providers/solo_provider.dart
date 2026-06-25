import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// ── Contact de confiance ─────────────────────────────────────
class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final String relation;
  bool isNotified;

  TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
    this.isNotified = false,
  });
}

// ── Provider — Mode Solo Sécurisé ────────────────────────────
class SoloProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  bool _soloActive = false;
  bool get soloActive => _soloActive;

  String? _trackingToken;   // token URL de suivi
  String? get trackingToken => _trackingToken;

  String? get trackingUrl =>
      _trackingToken != null ? 'https://motooffroad.app/s/$_trackingToken' : null;

  final List<TrustedContact> _contacts = [];
  List<TrustedContact> get contacts => List.unmodifiable(_contacts);

  int _immobilityThresholdMin = 30;   // alerte si immobile > N min
  int get immobilityThresholdMin => _immobilityThresholdMin;

  DateTime? _sessionStart;
  DateTime? get sessionStart => _sessionStart;

  // ── Ajouter un contact de confiance ──────────────────────
  void addContact({
    required String name,
    required String phone,
    required String relation,
  }) {
    if (_contacts.length >= 3) return; // max 3 contacts
    _contacts.add(TrustedContact(
      id:       _uuid.v4(),
      name:     name,
      phone:    phone,
      relation: relation,
    ));
    notifyListeners();
  }

  void removeContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // ── Activer le mode Solo ──────────────────────────────────
  Future<void> activate(List<String> contactIds) async {
    if (_contacts.isEmpty) return;

    // Génère un token de suivi unique et chiffré
    final raw = '${_uuid.v4()}${DateTime.now().millisecondsSinceEpoch}';
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    _trackingToken = digest.toString().substring(0, 12);

    _sessionStart = DateTime.now();
    _soloActive = true;

    // Marque les contacts sélectionnés comme notifiés
    for (final c in _contacts) {
      c.isNotified = contactIds.contains(c.id);
    }

    notifyListeners();
  }

  // ── Désactiver le mode Solo ───────────────────────────────
  void deactivate() {
    _soloActive = false;
    _trackingToken = null;
    _sessionStart = null;
    for (final c in _contacts) {
      c.isNotified = false;
    }
    notifyListeners();
  }

  void setImmobilityThreshold(int minutes) {
    _immobilityThresholdMin = minutes;
    notifyListeners();
  }
}
