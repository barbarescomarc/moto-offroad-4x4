import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'location_service.dart';

class SessionCreated {
  final String sessionId;
  final String ownerKey;
  final String deviceKey;
  final String memberId;
  final String? watchToken;
  final String? joinCode;

  const SessionCreated({
    required this.sessionId,
    required this.ownerKey,
    required this.deviceKey,
    required this.memberId,
    this.watchToken,
    this.joinCode,
  });
}

class SessionJoined {
  final String sessionId;
  final String deviceKey;
  final String memberId;
  final String color;

  const SessionJoined({
    required this.sessionId,
    required this.deviceKey,
    required this.memberId,
    required this.color,
  });
}

class PeerPosition {
  final String memberId;
  final String name;
  final String color;
  final LatLng? position;
  final double? speedKmh;
  final DateTime lastSeen;

  const PeerPosition({
    required this.memberId,
    required this.name,
    required this.color,
    required this.position,
    required this.speedKmh,
    required this.lastSeen,
  });
}

// Une alerte en cours sur la sortie, telle que les autres riders ont besoin
// de la lire : qui, quoi, depuis quand, et surtout où aller.
class AlerteGroupe {
  const AlerteGroupe({
    required this.memberId,
    required this.name,
    required this.kind,
    required this.raisedAt,
    required this.position,
  });

  final String memberId;
  final String name;

  /// `'sos'` (déclenché à la main) ou `'fall'` (chute détectée).
  final String kind;
  final DateTime raisedAt;

  /// Dernière position connue de celui qui a déclenché. Nulle s'il n'avait
  /// pas encore envoyé de point : l'alerte dit alors qu'il s'est passé
  /// quelque chose sans dire où, ce que l'interface doit avouer.
  final LatLng? position;

  bool get estSos => kind == 'sos';

  @override
  bool operator ==(Object other) =>
      other is AlerteGroupe &&
      other.memberId == memberId &&
      other.kind == kind &&
      other.raisedAt == raisedAt &&
      other.position == position;

  @override
  int get hashCode => Object.hash(memberId, kind, raisedAt, position);
}

// Résultat du polling /peers : la liste des pairs, le point de ralliement
// partagé par le groupe (posé par n'importe quel membre), et l'alerte en
// cours s'il y en a une.
class PeersResult {
  final List<PeerPosition> peers;
  final LatLng? rally;
  final AlerteGroupe? alerte;
  final bool ok; // false si la requete a echoue — les appelants ne doivent alors rien elaguer

  const PeersResult({
    required this.peers,
    required this.rally,
    required this.ok,
    this.alerte,
  });
}

class TrackerApiClient {
  TrackerApiClient({http.Client? client, String? baseUrl, Future<String?> Function()? readToken})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org',
        _readToken = readToken;

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function()? _readToken;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  // Rattachement, pas authentification : le serveur accepte ces routes sans
  // jeton, et une panne du stockage sécurisé ne doit jamais empêcher une
  // alerte de partir.
  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    final readToken = _readToken;
    if (readToken == null) return headers;
    try {
      final token = await readToken();
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    } catch (_) {}
    return headers;
  }

  Future<SessionCreated?> createSoloSession({
    required String name,
    required int immobileAfterSec,
    required String pilotEmail,
    required List<String> contactEmails,
    int? deadmanAfterSec,
  }) {
    final body = <String, dynamic>{
      'kind': 'solo', 'name': name, 'immobileAfterSec': immobileAfterSec,
      'pilotEmail': pilotEmail, 'contactEmails': contactEmails,
    };
    if (deadmanAfterSec != null) body['deadmanAfterSec'] = deadmanAfterSec;
    return _createSession(body);
  }

  Future<SessionCreated?> createGroupSession({required String name}) =>
      _createSession({'kind': 'group', 'name': name});

  Future<SessionCreated?> _createSession(Map<String, dynamic> body) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      if (res.statusCode ~/ 100 != 2) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return SessionCreated(
        sessionId: j['sessionId'] as String,
        ownerKey:  j['ownerKey']  as String,
        deviceKey: j['deviceKey'] as String,
        memberId:  j['memberId']  as String,
        watchToken: j['watchToken'] as String?,
        joinCode:   j['joinCode']   as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SessionJoined?> joinGroupSession({required String joinCode, required String name}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/join/$joinCode'),
        headers: await _headers(),
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode ~/ 100 != 2) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return SessionJoined(
        sessionId: j['sessionId'] as String,
        deviceKey: j['deviceKey'] as String,
        memberId:  j['memberId']  as String,
        color:     j['color']     as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendPositions({
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required List<GpsSnapshot> points,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/positions'),
        headers: await _headers(),
        body: jsonEncode({
          'deviceKey': deviceKey,
          'memberId': memberId,
          'points': points.map((p) => {
            'lat': p.position.latitude,
            'lng': p.position.longitude,
            'speedKmh': p.speedKmh,
            'heading': p.headingDeg,
            'recordedAt': p.timestamp.millisecondsSinceEpoch,
          }).toList(),
        }),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<PeersResult> fetchPeers({
    required String sessionId,
    required String deviceKey,
    required String memberId,
  }) async {
    try {
      final res = await _client.get(
        _uri('/api/sessions/$sessionId/peers', {'deviceKey': deviceKey, 'memberId': memberId}),
      );
      if (res.statusCode ~/ 100 != 2) return const PeersResult(peers: [], rally: null, ok: false);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final peers = (j['peers'] as List<dynamic>).map((raw) {
        final m = raw as Map<String, dynamic>;
        final lat = m['lat'] as num?;
        final lng = m['lng'] as num?;
        return PeerPosition(
          memberId: m['memberId'] as String,
          name:     m['name'] as String,
          color:    m['color'] as String,
          position: lat != null && lng != null ? LatLng(lat.toDouble(), lng.toDouble()) : null,
          speedKmh: (m['speedKmh'] as num?)?.toDouble(),
          lastSeen: DateTime.fromMillisecondsSinceEpoch(m['lastSeen'] as int),
        );
      }).toList();
      final rallyRaw = j['rally'] as Map<String, dynamic>?;
      final rallyLat = rallyRaw?['lat'] as num?;
      final rallyLng = rallyRaw?['lng'] as num?;
      final rally = rallyLat != null && rallyLng != null
          ? LatLng(rallyLat.toDouble(), rallyLng.toDouble())
          : null;
      return PeersResult(peers: peers, rally: rally, ok: true, alerte: _alerte(j));
    } catch (_) {
      return const PeersResult(peers: [], rally: null, ok: false);
    }
  }

  AlerteGroupe? _alerte(Map<String, dynamic> j) {
    final raw = j['alerte'] as Map<String, dynamic>?;
    if (raw == null) return null;
    final lat = raw['lat'] as num?;
    final lng = raw['lng'] as num?;
    return AlerteGroupe(
      memberId: raw['memberId'] as String? ?? '',
      name:     raw['name'] as String? ?? 'Un rider',
      kind:     raw['kind'] as String? ?? 'sos',
      raisedAt: DateTime.fromMillisecondsSinceEpoch((raw['raisedAt'] as num?)?.toInt() ?? 0),
      position: lat != null && lng != null ? LatLng(lat.toDouble(), lng.toDouble()) : null,
    );
  }

  Future<LatLng?> setRally({
    required String sessionId,
    required String deviceKey,
    required LatLng point,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/rally'),
        headers: await _headers(),
        body: jsonEncode({'deviceKey': deviceKey, 'lat': point.latitude, 'lng': point.longitude}),
      );
      return res.statusCode ~/ 100 == 2 ? point : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> clearRally({required String sessionId, required String deviceKey}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/rally'),
        headers: await _headers(),
        body: jsonEncode({'deviceKey': deviceKey, 'clear': true}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveSession({
    required String sessionId,
    required String deviceKey,
    required String memberId,
  }) async {
    try {
      final res = await _client.delete(
        _uri('/api/sessions/$sessionId/members/$memberId'),
        headers: await _headers(),
        body: jsonEncode({'deviceKey': deviceKey}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> endSession({required String sessionId, required String ownerKey}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/end'),
        headers: await _headers(),
        body: jsonEncode({'ownerKey': ownerKey}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> subscribeNewsletter({required String email, required String source}) async {
    try {
      final res = await _client.post(
        _uri('/api/newsletter/subscribe'),
        headers: await _headers(),
        body: jsonEncode({'email': email, 'source': source}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unsubscribeNewsletter({required String email}) async {
    try {
      final res = await _client.post(
        _uri('/api/newsletter/unsubscribe'),
        headers: await _headers(),
        body: jsonEncode({'email': email}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendAlert({
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required String kind,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/alert'),
        headers: await _headers(),
        body: jsonEncode({'deviceKey': deviceKey, 'memberId': memberId, 'kind': kind}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  /// Retire une alerte déclenchée par erreur. Le serveur ne l'accepte que de
  /// celui qui l'a déclenchée : les autres ne savent pas s'il va bien.
  Future<bool> clearAlert({
    required String sessionId,
    required String deviceKey,
    required String memberId,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/alert/clear'),
        headers: await _headers(),
        body: jsonEncode({'deviceKey': deviceKey, 'memberId': memberId}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }
}
