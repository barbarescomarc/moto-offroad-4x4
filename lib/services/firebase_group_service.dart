import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

// ── Données position membre (envoyées sur Firebase) ──────────
class MemberPosition {
  final String memberId;
  final String name;
  final double lat;
  final double lng;
  final double speedKmh;
  final bool isSharing;
  final int timestamp;

  const MemberPosition({
    required this.memberId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.isSharing,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'name':      name,
    'lat':       lat,
    'lng':       lng,
    'speed':     speedKmh,
    'sharing':   isSharing,
    'timestamp': timestamp,
  };

  factory MemberPosition.fromJson(String id, Map<dynamic, dynamic> json) =>
      MemberPosition(
        memberId:  id,
        name:      json['name'] as String? ?? 'Pilote',
        lat:       (json['lat'] as num?)?.toDouble() ?? 0,
        lng:       (json['lng'] as num?)?.toDouble() ?? 0,
        speedKmh:  (json['speed'] as num?)?.toDouble() ?? 0,
        isSharing: json['sharing'] as bool? ?? true,
        timestamp: json['timestamp'] as int? ?? 0,
      );

  LatLng get position => LatLng(lat, lng);
}

// ── Service Firebase — Mode groupe temps réel ─────────────────
class FirebaseGroupService {
  static final FirebaseGroupService _instance = FirebaseGroupService._();
  factory FirebaseGroupService() => _instance;
  FirebaseGroupService._();

  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseDatabase.instance;

  StreamSubscription<DatabaseEvent>? _groupSub;
  Timer? _positionTimer;
  String? _currentSessionId;
  String? _currentMemberId;

  // Callback pour les mises à jour de positions
  Function(List<MemberPosition>)? onMembersUpdate;

  // ── Connexion anonyme ────────────────────────────────────
  Future<String?> signInAnonymously() async {
    try {
      final cred = await _auth.signInAnonymously();
      return cred.user?.uid;
    } catch (_) {
      return null;
    }
  }

  // ── Créer une session groupe ──────────────────────────────
  Future<String?> createSession(String sessionId, String memberName) async {
    final uid = await signInAnonymously();
    if (uid == null) return null;

    _currentSessionId = sessionId;
    _currentMemberId  = uid;

    // Créer la session sur Firebase
    await _db.ref('sessions/$sessionId').set({
      'createdAt': ServerValue.timestamp,
      'expiresAt': DateTime.now().add(const Duration(hours: 4)).millisecondsSinceEpoch,
    });

    // S'inscrire comme membre
    await _db.ref('sessions/$sessionId/members/$uid').set({
      'name':      memberName,
      'lat':       0,
      'lng':       0,
      'speed':     0,
      'sharing':   true,
      'timestamp': ServerValue.timestamp,
    });

    // Cleanup automatique à la déconnexion
    _db.ref('sessions/$sessionId/members/$uid')
       .onDisconnect()
       .remove();

    // Écouter les autres membres
    _startListening(sessionId);
    return sessionId;
  }

  // ── Rejoindre une session existante ──────────────────────
  Future<bool> joinSession(String sessionId, String memberName) async {
    final uid = await signInAnonymously();
    if (uid == null) return false;

    // Vérifier que la session existe
    final snap = await _db.ref('sessions/$sessionId').get();
    if (!snap.exists) return false;

    _currentSessionId = sessionId;
    _currentMemberId  = uid;

    await _db.ref('sessions/$sessionId/members/$uid').set({
      'name':      memberName,
      'lat':       0,
      'lng':       0,
      'speed':     0,
      'sharing':   true,
      'timestamp': ServerValue.timestamp,
    });

    _db.ref('sessions/$sessionId/members/$uid').onDisconnect().remove();
    _startListening(sessionId);
    return true;
  }

  // ── Envoyer ma position (appelé toutes les 3 secondes) ───
  Future<void> updateMyPosition({
    required double lat,
    required double lng,
    required double speedKmh,
    required bool isSharing,
  }) async {
    if (_currentSessionId == null || _currentMemberId == null) return;

    await _db.ref('sessions/$_currentSessionId/members/$_currentMemberId').update({
      'lat':       lat,
      'lng':       lng,
      'speed':     speedKmh,
      'sharing':   isSharing,
      'timestamp': ServerValue.timestamp,
    });
  }

  // ── Démarrer l'écoute des membres du groupe ───────────────
  void _startListening(String sessionId) {
    _groupSub?.cancel();
    _groupSub = _db.ref('sessions/$sessionId/members').onValue.listen((event) {
      if (!event.snapshot.exists) return;

      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      final members = data.entries
          .where((e) => e.key != _currentMemberId) // exclure soi-même
          .map((e) => MemberPosition.fromJson(
              e.key as String,
              e.value as Map<dynamic, dynamic>))
          .where((m) {
            // Ignorer les positions trop anciennes (> 30 secondes)
            final age = DateTime.now().millisecondsSinceEpoch - m.timestamp;
            return age < 30000;
          })
          .toList();

      onMembersUpdate?.call(members);
    });
  }

  // ── Démarrer l'envoi auto de position ────────────────────
  void startPositionBroadcast({
    required Function() getPosition,  // callback pour obtenir la position actuelle
  }) {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      getPosition();
    });
  }

  // ── Envoyer un point de ralliement ────────────────────────
  Future<void> setRallyPoint(LatLng? point) async {
    if (_currentSessionId == null) return;
    if (point == null) {
      await _db.ref('sessions/$_currentSessionId/rally').remove();
    } else {
      await _db.ref('sessions/$_currentSessionId/rally').set({
        'lat': point.latitude,
        'lng': point.longitude,
        'timestamp': ServerValue.timestamp,
      });
    }
  }

  // ── Partager une trace (URL GPX) ─────────────────────────
  Future<void> shareTrace(String traceName, String? gpxUrl) async {
    if (_currentSessionId == null) return;
    await _db.ref('sessions/$_currentSessionId/sharedTrace').set({
      'name':      traceName,
      'url':       gpxUrl,
      'sharedBy':  _currentMemberId,
      'timestamp': ServerValue.timestamp,
    });
  }

  // ── Quitter la session ────────────────────────────────────
  Future<void> leaveSession() async {
    _positionTimer?.cancel();
    _groupSub?.cancel();

    if (_currentSessionId != null && _currentMemberId != null) {
      await _db.ref('sessions/$_currentSessionId/members/$_currentMemberId').remove();
    }

    _currentSessionId = null;
    _currentMemberId  = null;
  }

  void dispose() {
    _positionTimer?.cancel();
    _groupSub?.cancel();
  }
}
