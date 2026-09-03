import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/quick_reply_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les trois réponses par défaut sont celles du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final p = QuickReplyProvider();
    await p.load();

    expect(p.replies.length, 3);
    expect(p.replies[0].text, 'Je roule, je ne peux pas répondre');
    expect(p.replies[0].attachPosition, isFalse);
    expect(p.replies[1].text, 'Je roule, je suis ici');
    expect(p.replies[1].attachPosition, isTrue);
    expect(p.replies[2].text, "Tout va bien, j'arrive");
    expect(p.replies[2].attachPosition, isFalse);
  });

  test('une modification survit à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final p = QuickReplyProvider();
    await p.load();
    await p.updateReply(p.replies[0].id, text: 'Je pilote', attachPosition: true);

    final reloaded = QuickReplyProvider();
    await reloaded.load();
    expect(reloaded.replies[0].text, 'Je pilote');
    expect(reloaded.replies[0].attachPosition, isTrue);
  });

  test('un texte vide retombe sur la valeur par défaut', () async {
    SharedPreferences.setMockInitialValues({});
    final p = QuickReplyProvider();
    await p.load();
    await p.updateReply(p.replies[2].id, text: '   ');
    expect(p.replies[2].text, "Tout va bien, j'arrive");
  });

  test('la remise à zéro restaure les trois réponses du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final p = QuickReplyProvider();
    await p.load();
    await p.updateReply(p.replies[1].id, text: 'Autre chose', attachPosition: false);
    await p.resetToDefaults();

    expect(p.replies[1].text, 'Je roule, je suis ici');
    expect(p.replies[1].attachPosition, isTrue);
  });

  test('la liste garde toujours exactement trois réponses', () async {
    SharedPreferences.setMockInitialValues({'quick_replies': '[]'});
    final p = QuickReplyProvider();
    await p.load();
    expect(p.replies.length, QuickReplyProvider.maxReplies);
  });
}
