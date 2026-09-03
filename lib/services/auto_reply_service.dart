import 'dart:async';
import '../models/quick_reply.dart';
import 'auto_reply_composer.dart';
import 'auto_reply_policy.dart';
import 'call_bridge.dart';
import 'location_service.dart';

// ── Orchestration de l'auto-réponse aux appels ───────────────
//
// Seul point qui connaît à la fois le pont natif, la politique et le
// composeur. Les constructeurs de dépendances sont passés en fonctions : le
// service lit ainsi l'état courant des réglages à chaque appel, sans garder de
// référence aux providers ni se réabonner à chaque changement.
class AutoReplyService {
  final CallBridge bridge;
  final AutoReplyPolicy Function() policyBuilder;
  final String Function() messageBuilder;
  final bool Function() attachPositionBuilder;
  final List<QuickReply> Function() repliesBuilder;
  final Future<GpsSnapshot?> Function() positionProvider;

  StreamSubscription<CallEvent>? _sub;

  AutoReplyService({
    required this.bridge,
    required this.policyBuilder,
    required this.messageBuilder,
    required this.attachPositionBuilder,
    required this.repliesBuilder,
    required this.positionProvider,
  });

  void start() {
    _sub ??= bridge.events.listen(_onEvent);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onEvent(CallEvent event) async {
    switch (event.type) {
      case CallEventType.incoming:
        await _onIncoming(event.number);
      case CallEventType.quickReply:
        await _onQuickReply(event.number, event.index);
    }
  }

  Future<void> _onIncoming(String number) async {
    if (!policyBuilder().shouldReply(number)) return;

    final text = AutoReplyComposer.compose(
      message:        messageBuilder(),
      attachPosition: attachPositionBuilder(),
      snapshot:       attachPositionBuilder() ? await positionProvider() : null,
    );
    await bridge.sendSms(number, text);
    await bridge.showBanner(
      repliesBuilder().map((r) => r.text).toList(),
      number,
    );
  }

  // Une pression est une action délibérée du pilote : elle n'est pas soumise
  // au filtre des contacts de confiance, seulement à la présence d'un numéro.
  Future<void> _onQuickReply(String number, int index) async {
    final replies = repliesBuilder();
    if (index < 0 || index >= replies.length || number.isEmpty) return;

    final reply = replies[index];
    final text = AutoReplyComposer.compose(
      message:        reply.text,
      attachPosition: reply.attachPosition,
      snapshot:       reply.attachPosition ? await positionProvider() : null,
    );
    await bridge.sendSms(number, text);
    await bridge.hideBanner();
  }
}
