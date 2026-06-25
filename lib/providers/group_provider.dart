import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

// ── Membre du groupe ─────────────────────────────────────────
class GroupMember {
  final String id;
  final String name;
  final String color;   // hex
  LatLng? position;
  double? speedKmh;
  bool isSharing;
  DateTime? lastUpdate;
  bool isOnline;

  GroupMember({
    required this.id,
    required this.name,
    required this.color,
    this.position,
    this.speedKmh,
    this.isSharing = true,
    this.lastUpdate,
    this.isOnline = false,
  });
}

// ── Provider — Mode Groupe collaboratif ──────────────────────
class GroupProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  bool _groupActive = false;
  bool get groupActive => _groupActive;

  String? _sessionId;
  String? get sessionId => _sessionId;

  String? get inviteLink =>
      _sessionId != null ? 'https://motooffroad.app/g/$_sessionId' : null;

  bool _sharingMyPosition = true;
  bool get sharingMyPosition => _sharingMyPosition;

  final List<GroupMember> _members = [];
  List<GroupMember> get members => List.unmodifiable(_members);

  // Max 10 motos par groupe (incluant soi-même)
  static const int maxMembers = 10;
  bool get isFull => _members.length >= maxMembers;

  LatLng? _rallyPoint;
  LatLng? get rallyPoint => _rallyPoint;

  // ── Créer une session groupe ──────────────────────────────
  void createSession(String myName) {
    _sessionId = _uuid.v4().substring(0, 8).toUpperCase();
    _groupActive = true;
    _members.clear();
    // On s'ajoute comme premier membre
    _members.add(GroupMember(
      id:        'me',
      name:      myName,
      color:     '#5C6BC0',
      isSharing: true,
      isOnline:  true,
    ));
    notifyListeners();
  }

  // ── Rejoindre une session ─────────────────────────────────
  void joinSession(String sessionId, String myName) {
    _sessionId = sessionId;
    _groupActive = true;
    notifyListeners();
  }

  // ── Mettre à jour la position d'un membre ─────────────────
  void updateMemberPosition(String memberId, LatLng pos, double speed) {
    final idx = _members.indexWhere((m) => m.id == memberId);
    if (idx < 0) return;
    _members[idx].position  = pos;
    _members[idx].speedKmh  = speed;
    _members[idx].lastUpdate = DateTime.now();
    _members[idx].isOnline   = true;
    notifyListeners();
  }

  // ── Toggle partage de ma position ────────────────────────
  void toggleMySharing() {
    _sharingMyPosition = !_sharingMyPosition;
    final me = _members.where((m) => m.id == 'me').firstOrNull;
    if (me != null) me.isSharing = _sharingMyPosition;
    notifyListeners();
  }

  // ── Envoyer un point de ralliement ────────────────────────
  void setRallyPoint(LatLng? point) {
    _rallyPoint = point;
    notifyListeners();
  }

  // ── Quitter le groupe ─────────────────────────────────────
  void leaveGroup() {
    _groupActive = false;
    _sessionId = null;
    _members.clear();
    _rallyPoint = null;
    _sharingMyPosition = true;
    notifyListeners();
  }

  // ── Membres en ligne ─────────────────────────────────────
  int get onlineCount => _members.where((m) => m.isOnline).length;
}
