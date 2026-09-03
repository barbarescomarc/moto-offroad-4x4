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

// Résultat du polling /peers : la liste des pairs, et le point de
// ralliement partagé par le groupe (posé par n'importe quel membre).
class PeersResult {
  final List<PeerPosition> peers;
  final LatLng? rally;

  const PeersResult({required this.peers, required this.rally});
}

class TrackerApiClient {
  TrackerApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org';

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  Future<SessionCreated?> createSoloSession({
    required String name,
    required int immobileAfterSec,
  }) => _createSession({'kind': 'solo', 'name': name, 'immobileAfterSec': immobileAfterSec});

  Future<SessionCreated?> createGroupSession({required String name}) =>
      _createSession({'kind': 'group', 'name': name});

  Future<SessionCreated?> _createSession(Map<String, dynamic> body) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions'),
        headers: {'content-type': 'application/json'},
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
        headers: {'content-type': 'application/json'},
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
        headers: {'content-type': 'application/json'},
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
      if (res.statusCode ~/ 100 != 2) return const PeersResult(peers: [], rally: null);
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
      return PeersResult(peers: peers, rally: rally);
    } catch (_) {
      return const PeersResult(peers: [], rally: null);
    }
  }

  Future<LatLng?> setRally({
    required String sessionId,
    required String deviceKey,
    required LatLng point,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/rally'),
        headers: {'content-type': 'application/json'},
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
        headers: {'content-type': 'application/json'},
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
        headers: {'content-type': 'application/json'},
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
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'ownerKey': ownerKey}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }
}
