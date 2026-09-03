import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/position_uplink_service.dart';
import '../services/tracker_api_client.dart';

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
  GroupProvider({TrackerApiClient? trackerClient})
      : _tracker = trackerClient ?? TrackerApiClient();

  static const String watchBaseUrl = 'https://motooffroad.duckdns.org/g/';

  final TrackerApiClient _tracker;

  bool _groupActive = false;
  bool get groupActive => _groupActive;

  // Code public affiché/partagé (le join code à 6 caractères) — jamais l'id
  // interne réel du serveur, qui vit dans _hubSessionId ci-dessous.
  String? _sessionId;
  String? get sessionId => _sessionId;

  // Id de session réel côté hub, utilisé pour tous les appels API — distinct
  // du join code affiché : le serveur clé ses routes sur cet id, jamais sur
  // le code à 6 caractères que les pilotes se partagent.
  String? _hubSessionId;

  String? _ownerKey;
  String? _deviceKey;
  String? get deviceKey => _deviceKey;
  String? _myMemberId;
  String? get myMemberId => _myMemberId;

  String? get inviteLink => _sessionId != null ? '$watchBaseUrl$_sessionId' : null;

  bool _sharingMyPosition = true;
  bool get sharingMyPosition => _sharingMyPosition;

  final List<GroupMember> _members = [];
  List<GroupMember> get members => List.unmodifiable(_members);

  // Jusqu'à 20 motos par groupe (incluant soi-même) — lot D.
  static const int maxMembers = 20;
  bool get isFull => _members.length >= maxMembers;

  LatLng? _rallyPoint;
  LatLng? get rallyPoint => _rallyPoint;

  Timer? _pollTimer;
  PositionUplinkService? _uplink;
  int _liveGeneration = 0;

  // ── Créer une session groupe ──────────────────────────────
  Future<bool> createSession(String myName) async {
    final created = await _tracker.createGroupSession(name: myName);
    if (created == null || created.joinCode == null) return false;

    _sessionId = created.joinCode;
    _hubSessionId = created.sessionId;
    _ownerKey  = created.ownerKey;
    _deviceKey = created.deviceKey;
    _myMemberId = created.memberId;
    _groupActive = true;
    _members
      ..clear()
      ..add(GroupMember(
        id: created.memberId, name: myName, color: '#5C6BC0',
        isSharing: true, isOnline: true,
      ));
    notifyListeners();
    return true;
  }

  // ── Rejoindre une session ─────────────────────────────────
  Future<bool> joinSession(String joinCode, String myName) async {
    final joined = await _tracker.joinGroupSession(joinCode: joinCode, name: myName);
    if (joined == null) return false;

    _sessionId = joinCode; // le code que le pilote vient de saisir, pas l'id interne
    _hubSessionId = joined.sessionId;
    _deviceKey = joined.deviceKey;
    _myMemberId = joined.memberId;
    _groupActive = true;
    _members
      ..clear()
      ..add(GroupMember(
        id: joined.memberId, name: myName, color: joined.color,
        isSharing: true, isOnline: true,
      ));
    notifyListeners();
    return true;
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
    final me = _members.where((m) => m.id == _myMemberId).firstOrNull;
    if (me != null) me.isSharing = _sharingMyPosition;
    notifyListeners();
  }

  // ── Envoyer un point de ralliement ────────────────────────
  Future<void> setRallyPoint(LatLng? point) async {
    final sid = _hubSessionId, dk = _deviceKey;
    if (sid == null || dk == null) return;
    if (point == null) {
      await _tracker.clearRally(sessionId: sid, deviceKey: dk);
    } else {
      await _tracker.setRally(sessionId: sid, deviceKey: dk, point: point);
    }
    _rallyPoint = point;
    notifyListeners();
  }

  // ── Partager les positions en direct ─────────────────────
  void startLiveSharing({
    required Stream<GpsSnapshot> positions,
    Duration pollInterval = const Duration(seconds: 3),
  }) {
    final sid = _hubSessionId, dk = _deviceKey, mid = _myMemberId;
    if (sid == null || dk == null || mid == null) return;

    final generation = _liveGeneration;

    _uplink?.stop();
    _uplink = PositionUplinkService(sendPositions: _tracker.sendPositions)
      ..start(positions: positions, sessionId: sid, deviceKey: dk, memberId: mid, interval: pollInterval);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      if (!_groupActive) return;
      final peers = await _tracker.fetchPeers(sessionId: sid, deviceKey: dk, memberId: mid);
      if (generation != _liveGeneration || !_groupActive) return;
      for (final peer in peers) {
        final idx = _members.indexWhere((m) => m.id == peer.memberId);
        if (idx >= 0) {
          _members[idx].position   = peer.position;
          _members[idx].speedKmh   = peer.speedKmh;
          _members[idx].lastUpdate = peer.lastSeen;
          _members[idx].isOnline   = true;
        } else {
          _members.add(GroupMember(
            id: peer.memberId, name: peer.name, color: peer.color,
            position: peer.position, speedKmh: peer.speedKmh,
            lastUpdate: peer.lastSeen, isOnline: true,
          ));
        }
      }
      notifyListeners();
    });
  }

  // ── Quitter le groupe ─────────────────────────────────────
  // Le créateur qui quitte éteint le groupe pour tout le monde — spec §8 :
  // "L'extinction du groupe purge tout, immédiatement" (critère de réussite
  // #7). Un invité ne fait que se retirer ; le groupe continue pour les
  // autres. Le distinguo tient à _ownerKey : seul le créateur en reçoit un
  // à la création (joinGroupSession n'en renvoie pas).
  void leaveGroup() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _uplink?.stop();
    _uplink = null;
    _liveGeneration++;
    final sid = _hubSessionId, dk = _deviceKey, mid = _myMemberId, ok = _ownerKey;
    if (sid != null && ok != null) {
      _tracker.endSession(sessionId: sid, ownerKey: ok);
    } else if (sid != null && dk != null && mid != null) {
      _tracker.leaveSession(sessionId: sid, deviceKey: dk, memberId: mid);
    }
    _groupActive = false;
    _sessionId = null;
    _hubSessionId = null;
    _ownerKey = null;
    _deviceKey = null;
    _myMemberId = null;
    _members.clear();
    _rallyPoint = null;
    _sharingMyPosition = true;
    notifyListeners();
  }

  // ── Membres en ligne ─────────────────────────────────────
  int get onlineCount => _members.where((m) => m.isOnline).length;
}
