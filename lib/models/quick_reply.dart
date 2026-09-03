// ── Réponse rapide proposée pendant un appel entrant ─────────
class QuickReply {
  final String id;
  final String text;
  final bool attachPosition;

  const QuickReply({
    required this.id,
    required this.text,
    required this.attachPosition,
  });

  QuickReply copyWith({String? text, bool? attachPosition}) => QuickReply(
    id:             id,
    text:           text ?? this.text,
    attachPosition: attachPosition ?? this.attachPosition,
  );

  Map<String, dynamic> toJson() => {
    'id':       id,
    'text':     text,
    'position': attachPosition,
  };

  factory QuickReply.fromJson(Map<String, dynamic> j) => QuickReply(
    id:             j['id'] as String,
    text:           j['text'] as String,
    attachPosition: j['position'] as bool? ?? false,
  );
}
