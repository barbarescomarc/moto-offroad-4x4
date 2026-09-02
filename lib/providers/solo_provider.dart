import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Conversion vers JSON pour la persistance
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relation': relation,
  };

  // Construction depuis JSON
  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    id:       j['id'] as String,
    name:     j['name'] as String,
    phone:    j['phone'] as String,
    relation: j['relation'] as String,
  );
}

// ── Provider — Mode Solo Sécurisé ────────────────────────────
class SoloProvider extends ChangeNotifier {
  static const _kContacts = 'trusted_contacts';

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

  // ── Charger les contacts depuis le stockage persistant ────
  Future<void> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContacts);
    _contacts.clear();
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _contacts.addAll(list
          .map((e) => TrustedContact.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  // ── Persister les contacts dans le stockage ──────────────
  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kContacts,
      jsonEncode(_contacts.map((c) => c.toJson()).toList()),
    );
  }

  // ── Ajouter un contact de confiance ──────────────────────
  Future<void> addContact({
    required String name,
    required String phone,
    required String relation,
  }) async {
    if (_contacts.length >= 3) return; // max 3 contacts
    _contacts.add(TrustedContact(
      id:       _uuid.v4(),
      name:     name,
      phone:    phone,
      relation: relation,
    ));
    await _saveContacts();
    notifyListeners();
  }

  Future<void> removeContact(String id) async {
    _contacts.removeWhere((c) => c.id == id);
    await _saveContacts();
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
