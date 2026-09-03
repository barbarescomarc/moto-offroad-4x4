import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/phone_number_matcher.dart';

void main() {
  test('normalize ne garde que les 9 derniers chiffres', () {
    expect(PhoneNumberMatcher.normalize('+33 6 12 34 56 78'), '612345678');
    expect(PhoneNumberMatcher.normalize('06.12.34.56.78'), '612345678');
    expect(PhoneNumberMatcher.normalize('0033612345678'), '612345678');
  });

  test('les écritures française et internationale correspondent', () {
    expect(PhoneNumberMatcher.matches('+33612345678', '0612345678'), isTrue);
    expect(PhoneNumberMatcher.matches('06 12 34 56 78', '+33 6 12 34 56 78'), isTrue);
  });

  test('deux numéros différents ne correspondent pas', () {
    expect(PhoneNumberMatcher.matches('+33612345678', '0698765432'), isFalse);
  });

  test('un numéro vide ou masqué ne correspond à rien', () {
    expect(PhoneNumberMatcher.matches('', '0612345678'), isFalse);
    expect(PhoneNumberMatcher.matches('0612345678', ''), isFalse);
    expect(PhoneNumberMatcher.normalize(''), '');
  });

  test('un numéro court est comparé sur toute sa longueur', () {
    expect(PhoneNumberMatcher.normalize('112'), '112');
    expect(PhoneNumberMatcher.matches('112', '112'), isTrue);
    expect(PhoneNumberMatcher.matches('112', '3112'), isFalse);
  });
}
