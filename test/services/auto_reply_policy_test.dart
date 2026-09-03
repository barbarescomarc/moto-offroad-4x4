import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/auto_reply_policy.dart';

AutoReplyPolicy _policy({
  bool enabled = true,
  bool allCallers = false,
  bool riding = true,
  List<String> trusted = const ['+33612345678'],
}) => AutoReplyPolicy(
  enabled: enabled, allCallers: allCallers, riding: riding, trustedPhones: trusted,
);

void main() {
  test('un contact de confiance qui appelle pendant une sortie reçoit une réponse', () {
    expect(_policy().shouldReply('0612345678'), isTrue);
  });

  test('rien ne part si la fonction est désactivée', () {
    expect(_policy(enabled: false).shouldReply('0612345678'), isFalse);
  });

  test('rien ne part si le pilote ne roule pas', () {
    expect(_policy(riding: false).shouldReply('0612345678'), isFalse);
  });

  test('un inconnu ne reçoit rien par défaut', () {
    expect(_policy().shouldReply('0698765432'), isFalse);
  });

  test('un inconnu reçoit une réponse si tous les appelants sont autorisés', () {
    expect(_policy(allCallers: true).shouldReply('0698765432'), isTrue);
  });

  test('un numéro masqué ne reçoit jamais rien, même en mode tous appelants', () {
    expect(_policy(allCallers: true).shouldReply(''), isFalse);
  });

  test('sans contact de confiance enregistré, rien ne part hors mode tous appelants', () {
    expect(_policy(trusted: const []).shouldReply('0612345678'), isFalse);
  });

  test('le pilote qui ne roule pas ne répond à personne, même en mode tous appelants', () {
    expect(_policy(allCallers: true, riding: false).shouldReply('0698765432'), isFalse);
  });
}
