import 'package:flutter/services.dart';

// ── Événements remontés par le natif ─────────────────────────
enum CallEventType { incoming, quickReply }

class CallEvent {
  final CallEventType type;
  final String number;
  final int index; // rang de la réponse rapide pressée, -1 sinon

  const CallEvent({required this.type, required this.number, this.index = -1});
}

// ── Façade des canaux natifs Android ─────────────────────────
//
// Trois capacités qu'Android seul fournit : détecter un appel entrant, envoyer
// un SMS sans intervention de l'utilisateur, afficher un bandeau à boutons.
//
// Sur iOS aucun handler natif n'est enregistré (Apple interdit ces trois
// capacités aux applications tierces) : chaque appel y lève une
// MissingPluginException, qui n'est pas une PlatformException. Elle est
// attrapée ici pour qu'un canal indisponible se comporte comme un canal en
// échec — sans quoi une chute sur iOS interromprait la chaîne d'alerte avant
// d'atteindre le canal serveur.
class CallBridge {
  static const _methods = MethodChannel('app.motooffroad/call');
  static const _events = EventChannel('app.motooffroad/call_events');
  static const int maxBannerLabels = 3;

  static final CallBridge _instance = CallBridge._();
  factory CallBridge() => _instance;
  CallBridge._();

  Stream<CallEvent>? _stream;

  Stream<CallEvent> get events {
    _stream ??= _events.receiveBroadcastStream().map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return CallEvent(
        type: map['type'] == 'quick_reply'
            ? CallEventType.quickReply
            : CallEventType.incoming,
        number: map['number'] as String? ?? '',
        index: map['index'] as int? ?? -1,
      );
    });
    return _stream!;
  }

  Future<bool> sendSms(String phone, String text) async {
    try {
      return await _methods.invokeMethod<bool>('sendSms', {
            'phone': phone,
            'text': text,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> showBanner(List<String> labels, String number) async {
    try {
      await _methods.invokeMethod<void>('showBanner', {
        'labels': labels.take(maxBannerLabels).toList(),
        'number': number,
      });
    } on PlatformException {
      // Le bandeau est un confort : son échec ne doit pas empêcher
      // l'auto-réponse, qui est la fonction de sécurité.
    } on MissingPluginException {
      // Idem.
    }
  }

  Future<void> hideBanner() async {
    try {
      await _methods.invokeMethod<void>('hideBanner');
    } on PlatformException {
      // Idem : sans conséquence sur la sécurité.
    } on MissingPluginException {
      // Idem.
    }
  }

  Future<bool> hasPermissions() async {
    try {
      return await _methods.invokeMethod<bool>('hasPermissions') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
