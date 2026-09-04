import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/tracker_api_client.dart';

// ── Contact de confiance ─────────────────────────────────────
class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String relation;
  bool isNotified;

  TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.relation,
    this.isNotified = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'relation': relation,
  };

  // Les contacts enregistrés avant ce lot n'ont pas d'e-mail en stockage —
  // '' plutôt qu'un champ nullable, pour que le reste du code n'ait qu'un
  // seul cas à traiter (« vide » = à compléter), pas deux (null vs vide).
  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    id:       j['id'] as String,
    name:     j['name'] as String,
    phone:    j['phone'] as String,
    email:    j['email'] as String? ?? '',
    relation: j['relation'] as String,
  );
}

// ── Provider — Mode Solo Sécurisé ────────────────────────────
class SoloProvider extends ChangeNotifier {
  SoloProvider({TrackerApiClient? trackerClient})
      : _tracker = trackerClient ?? TrackerApiClient();

  static const _kContacts = 'trusted_contacts';
  static const String watchBaseUrl = 'https://motooffroad.duckdns.org/s/';

  final _uuid = const Uuid();
  final TrackerApiClient _tracker;

  bool _soloActive = false;
  bool get soloActive => _soloActive;

  String? _watchToken;
  String? get trackingUrl => _watchToken != null ? '$watchBaseUrl$_watchToken' : null;

  String? _sessionId;
  String? get sessionId => _sessionId;
  String? _deviceKey;
  String? get deviceKey => _deviceKey;
  String? _memberId;
  String? get memberId => _memberId;
  String? _ownerKey;

  final List<TrustedContact> _contacts = [];
  List<TrustedContact> get contacts => List.unmodifiable(_contacts);

  int _immobilityThresholdMin = 30;   // alerte si immobile > N min
  int get immobilityThresholdMin => _immobilityThresholdMin;

  int _deadmanThresholdMin = 15;   // alerte si silence total > N min
  int get deadmanThresholdMin => _deadmanThresholdMin;

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
    required String email,
    required String relation,
  }) async {
    if (_contacts.length >= 3) return; // max 3 contacts
    _contacts.add(TrustedContact(
      id:       _uuid.v4(),
      name:     name,
      phone:    phone,
      email:    email,
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
  Future<bool> activate(List<String> contactIds) async {
    if (_contacts.isEmpty) return false;

    final created = await _tracker.createSoloSession(
      name: 'Pilote',
      immobileAfterSec: _immobilityThresholdMin * 60,
    );
    if (created == null || created.watchToken == null) return false;

    _sessionId  = created.sessionId;
    _deviceKey  = created.deviceKey;
    _memberId   = created.memberId;
    _ownerKey   = created.ownerKey;
    _watchToken = created.watchToken;
    _sessionStart = DateTime.now();
    _soloActive = true;

    for (final c in _contacts) {
      c.isNotified = contactIds.contains(c.id);
    }

    notifyListeners();
    return true;
  }

  // ── Désactiver le mode Solo ───────────────────────────────
  void deactivate() {
    final sid = _sessionId;
    final ok = _ownerKey;
    if (sid != null && ok != null) {
      _tracker.endSession(sessionId: sid, ownerKey: ok); // fire-and-forget, échec avalé par le client
    }

    _soloActive = false;
    _watchToken = null;
    _sessionId = null;
    _deviceKey = null;
    _memberId = null;
    _ownerKey = null;
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

  void setDeadmanThreshold(int minutes) {
    _deadmanThresholdMin = minutes;
    notifyListeners();
  }
}
