# Lot E — Auto-réponse aux appels et partage de position

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quand une personne de confiance appelle pendant une sortie, le téléphone répond seul par SMS, propose trois réponses rapides d'une pression, et permet d'envoyer ses coordonnées GPS à coller dans Google Maps.

**Architecture :** La logique de décision est en Dart pur et testable — trois unités sans dépendance (comparaison de numéros, composition du message, politique de réponse). Un pont Kotlin isolé fournit les trois capacités qu'Android seul possède : détecter un appel entrant, envoyer un SMS sans intervention, afficher une notification à boutons. Un service d'orchestration relie les deux.

**Tech Stack :** Flutter 3.10+, Dart 3, `provider`, `shared_preferences`, `geolocator`, Kotlin, `NotificationCompat`, `SmsManager`.

**Spec :** `docs/superpowers/specs/2026-09-03-suivi-securite-personne-de-confiance-design.md` (§9, §10, §11)

## Global Constraints

- Application **Android uniquement**. Aucun code iOS, aucune branche conditionnelle de plateforme au-delà d'un garde-fou `Platform.isAndroid`.
- Aucune nouvelle dépendance Flutter. Tout ce qui manque est écrit en Kotlin.
- Package Android : `app.motooffroad`. Sources Kotlin dans `android/app/src/main/kotlin/app/motooffroad/`.
- Nom du paquet Dart pour les imports de test : `package:moto_offroad/...`
- Tous les réglages suivent le format de `SettingsProvider` : une clé `SharedPreferences`, un champ privé, un accesseur, un mutateur `Future<void>` qui persiste puis appelle `notifyListeners()`.
- Textes d'interface **en français**, sans exception.
- Commentaires de code en français, style de l'existant : séparateurs `// ── Titre ──`.
- Le lot E ne contacte **aucun serveur**. Aucun appel réseau n'est ajouté.
- Suite de tests actuelle : 82 tests au vert. Aucun ne doit casser.
- Commande de test : `flutter test`. Analyse : `flutter analyze` doit rester sans nouvelle alerte.

## Correction apportée à la spec

La spec §9.1 et §11 annonce l'ajout de la seule permission `READ_PHONE_STATE`.
C'est insuffisant : **depuis Android 9 (API 28), `EXTRA_INCOMING_NUMBER` est
toujours vide sans la permission `READ_CALL_LOG`**. Sans le numéro de
l'appelant, il est impossible de savoir si c'est un contact de confiance qui
appelle, ce qui vide la fonction de sa substance.

Ce plan ajoute donc **`READ_PHONE_STATE` et `READ_CALL_LOG`**. Les deux sont
des permissions restreintes au Play Store, sans conséquence ici puisque la
distribution passe par un APK GitHub — même raisonnement que `SEND_SMS` en
spec §12.

Conséquence sur le comportement : si l'utilisateur refuse `READ_CALL_LOG`, le
numéro arrive vide. La politique de réponse traite ce cas explicitement en ne
répondant pas (Task 5), plutôt qu'en envoyant la position à un inconnu.

---

## File Structure

| Fichier | Responsabilité |
|---------|----------------|
| `lib/services/phone_number_matcher.dart` | Normaliser et comparer deux numéros de téléphone |
| `lib/models/quick_reply.dart` | Modèle d'une réponse rapide |
| `lib/providers/quick_reply_provider.dart` | Les trois réponses rapides, persistées |
| `lib/services/auto_reply_composer.dart` | Assembler le texte du SMS, avec ou sans position |
| `lib/services/auto_reply_policy.dart` | Décider s'il faut répondre à cet appel |
| `lib/services/call_bridge.dart` | Façade Dart des canaux natifs |
| `lib/services/auto_reply_service.dart` | Orchestration : écoute, décide, compose, envoie |
| `lib/screens/settings/call_settings_screen.dart` | Réglages « Appels et position » |
| `lib/screens/solo/send_position_screen.dart` | Envoi manuel des coordonnées |
| `android/.../CallBridge.kt` | Canaux, détection d'appel, envoi SMS |
| `android/.../QuickReplyNotification.kt` | Bandeau à trois boutons |
| `android/.../QuickReplyReceiver.kt` | Réception des pressions sur les boutons |

Modifiés : `lib/providers/settings_provider.dart`, `lib/screens/settings/settings_screen.dart`, `lib/app/router.dart`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`, `android/.../MainActivity.kt`.

---

### Task 1: Comparaison de numéros de téléphone

Un contact enregistré `+33 6 12 34 56 78` doit correspondre à un appel entrant
`0612345678`. La comparaison porte sur les **9 derniers chiffres**, ce qui
absorbe indicatif international et zéro initial sans table de préfixes.

**Files:**
- Create: `lib/services/phone_number_matcher.dart`
- Test: `test/services/phone_number_matcher_test.dart`

**Interfaces:**
- Consumes: rien
- Produces: `PhoneNumberMatcher.normalize(String) → String`, `PhoneNumberMatcher.matches(String, String) → bool`

- [ ] **Step 1: Écrire les tests qui échouent**

```dart
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
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/services/phone_number_matcher_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'moto_offroad/services/phone_number_matcher.dart'`

- [ ] **Step 3: Écrire l'implémentation minimale**

```dart
// ── Comparaison de numéros de téléphone ──────────────────────
//
// Un contact peut être enregistré en écriture internationale (+33 6 …) et
// appeler en écriture nationale (06 …). Comparer les 9 derniers chiffres
// rend les deux équivalentes sans avoir à connaître les indicatifs pays.
class PhoneNumberMatcher {
  static const int _significantDigits = 9;

  /// Retire tout ce qui n'est pas un chiffre, puis ne garde que la fin
  /// significative du numéro.
  static String normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= _significantDigits) return digits;
    return digits.substring(digits.length - _significantDigits);
  }

  /// Vrai si les deux numéros désignent la même ligne. Un numéro vide —
  /// appel masqué, ou permission READ_CALL_LOG refusée — ne correspond à rien.
  static bool matches(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `flutter test test/services/phone_number_matcher_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Commit**

```bash
git add lib/services/phone_number_matcher.dart test/services/phone_number_matcher_test.dart
git commit -m "feat: comparaison de numeros sur les 9 derniers chiffres"
```

---

### Task 2: Modèle et persistance des réponses rapides

Trois réponses fixes, modifiables mais ni ajoutables ni supprimables : Android
n'affiche que trois boutons d'action dans une notification (spec §9.2). Une
liste de taille variable exposerait une interface que la plateforme ne peut pas
rendre.

**Files:**
- Create: `lib/models/quick_reply.dart`
- Create: `lib/providers/quick_reply_provider.dart`
- Test: `test/providers/quick_reply_provider_test.dart`

**Interfaces:**
- Consumes: rien
- Produces:
  - `QuickReply({required String id, required String text, required bool attachPosition})`, `copyWith({String? text, bool? attachPosition})`, `toJson()`, `QuickReply.fromJson(Map<String, dynamic>)`
  - `QuickReplyProvider.replies → List<QuickReply>` (toujours 3 éléments), `load() → Future<void>`, `updateReply(String id, {String? text, bool? attachPosition}) → Future<void>`, `resetToDefaults() → Future<void>`, `QuickReplyProvider.defaults → List<QuickReply>`, `QuickReplyProvider.maxReplies == 3`

- [ ] **Step 1: Écrire les tests qui échouent**

```dart
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
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/providers/quick_reply_provider_test.dart`
Expected: FAIL — paquet `quick_reply_provider.dart` introuvable

- [ ] **Step 3: Écrire le modèle**

```dart
// lib/models/quick_reply.dart

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
```

- [ ] **Step 4: Écrire le provider**

```dart
// lib/providers/quick_reply_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_reply.dart';

// ── Les trois réponses rapides du bandeau d'appel ────────────
//
// Le nombre est fixe : Android n'affiche que trois boutons d'action dans une
// notification. Les textes et l'ajout de la position sont modifiables.
class QuickReplyProvider extends ChangeNotifier {
  static const _kReplies = 'quick_replies';
  static const int maxReplies = 3;

  static List<QuickReply> get defaults => const [
    QuickReply(id: 'r1', text: 'Je roule, je ne peux pas répondre', attachPosition: false),
    QuickReply(id: 'r2', text: 'Je roule, je suis ici',            attachPosition: true),
    QuickReply(id: 'r3', text: "Tout va bien, j'arrive",           attachPosition: false),
  ];

  List<QuickReply> _replies = List.of(defaults);
  List<QuickReply> get replies => List.unmodifiable(_replies);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kReplies);
    _replies = _decode(raw);
    notifyListeners();
  }

  // Une sauvegarde corrompue ou incomplète ne doit pas priver le pilote de ses
  // réponses : chaque identifiant manquant reprend sa valeur par défaut.
  List<QuickReply> _decode(String? raw) {
    if (raw == null) return List.of(defaults);
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => QuickReply.fromJson(e as Map<String, dynamic>))
          .toList();
      return defaults
          .map((d) => list.firstWhere((r) => r.id == d.id, orElse: () => d))
          .toList();
    } catch (_) {
      return List.of(defaults);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kReplies,
      jsonEncode(_replies.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> updateReply(String id, {String? text, bool? attachPosition}) async {
    final index = _replies.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final fallback = defaults.firstWhere((d) => d.id == id).text;
    final cleaned = text?.trim();
    _replies[index] = _replies[index].copyWith(
      text:           cleaned == null ? null : (cleaned.isEmpty ? fallback : cleaned),
      attachPosition: attachPosition,
    );
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _replies = List.of(defaults);
    await _save();
    notifyListeners();
  }
}
```

- [ ] **Step 5: Lancer les tests et vérifier qu'ils passent**

Run: `flutter test test/providers/quick_reply_provider_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 6: Commit**

```bash
git add lib/models/quick_reply.dart lib/providers/quick_reply_provider.dart test/providers/quick_reply_provider_test.dart
git commit -m "feat: trois reponses rapides persistees pour le bandeau d appel"
```

---

### Task 3: Réglages d'auto-réponse

Quatre réglages de la spec §10, dans `SettingsProvider` existant.

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Test: `test/providers/settings_provider_test.dart`

**Interfaces:**
- Consumes: rien
- Produces sur `SettingsProvider` : `autoReplyEnabled → bool` (défaut `true`), `autoReplyAttachPosition → bool` (défaut `true`), `autoReplyAllCallers → bool` (défaut `false`), `autoReplyMessage → String` (défaut `'Je roule, je ne peux pas répondre'`), et les mutateurs `setAutoReplyEnabled`, `setAutoReplyAttachPosition`, `setAutoReplyAllCallers`, `setAutoReplyMessage`, tous `Future<void>`.

- [ ] **Step 1: Ajouter les tests qui échouent**

Ajouter à la fin du `main()` de `test/providers/settings_provider_test.dart` :

```dart
  test('les réglages d auto-réponse ont les valeurs par défaut du spec', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.autoReplyEnabled, isTrue);
    expect(s.autoReplyAttachPosition, isTrue);
    expect(s.autoReplyAllCallers, isFalse);
    expect(s.autoReplyMessage, 'Je roule, je ne peux pas répondre');
  });

  test('les réglages d auto-réponse survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoReplyEnabled(false);
    await s.setAutoReplyAttachPosition(false);
    await s.setAutoReplyAllCallers(true);
    await s.setAutoReplyMessage('Je pilote, rappelle plus tard');

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.autoReplyEnabled, isFalse);
    expect(reloaded.autoReplyAttachPosition, isFalse);
    expect(reloaded.autoReplyAllCallers, isTrue);
    expect(reloaded.autoReplyMessage, 'Je pilote, rappelle plus tard');
  });

  test('un message d auto-réponse vide retombe sur la valeur par défaut', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setAutoReplyMessage('   ');
    expect(s.autoReplyMessage, 'Je roule, je ne peux pas répondre');
  });
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: FAIL — `The getter 'autoReplyEnabled' isn't defined for the class 'SettingsProvider'`

- [ ] **Step 3: Ajouter les clés et le champ par défaut**

Dans `lib/providers/settings_provider.dart`, après la ligne `static const _kScreenOn = 'map_keep_screen_on';` :

```dart
  static const _kAutoReply     = 'call_auto_reply';
  static const _kAutoReplyPos  = 'call_auto_reply_position';
  static const _kAutoReplyAll  = 'call_auto_reply_all';
  static const _kAutoReplyText = 'call_auto_reply_text';

  // Message envoyé seul, sans que le pilote ait à toucher l'écran.
  static const String defaultAutoReplyMessage = 'Je roule, je ne peux pas répondre';
```

- [ ] **Step 4: Ajouter les champs et accesseurs**

Après `bool _keepScreenOnMap = true;` :

```dart
  bool _autoReplyEnabled        = true;
  bool _autoReplyAttachPosition = true;
  bool _autoReplyAllCallers     = false;
  String _autoReplyMessage      = defaultAutoReplyMessage;
```

Après `bool get keepScreenOnMap => _keepScreenOnMap;` :

```dart
  bool   get autoReplyEnabled        => _autoReplyEnabled;
  bool   get autoReplyAttachPosition => _autoReplyAttachPosition;
  bool   get autoReplyAllCallers     => _autoReplyAllCallers;
  String get autoReplyMessage        => _autoReplyMessage;
```

- [ ] **Step 5: Charger les valeurs**

Dans `load()`, après `_keepScreenOnMap = prefs.getBool(_kScreenOn) ?? true;` :

```dart
    _autoReplyEnabled        = prefs.getBool(_kAutoReply)    ?? true;
    _autoReplyAttachPosition = prefs.getBool(_kAutoReplyPos) ?? true;
    _autoReplyAllCallers     = prefs.getBool(_kAutoReplyAll) ?? false;
    _autoReplyMessage        = prefs.getString(_kAutoReplyText) ?? defaultAutoReplyMessage;
```

- [ ] **Step 6: Ajouter les mutateurs**

À la fin de la classe, avant l'accolade fermante :

```dart
  // ── Réglages d'auto-réponse aux appels ───────────────────
  Future<void> setAutoReplyEnabled(bool v) async {
    _autoReplyEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReply, v);
    notifyListeners();
  }

  Future<void> setAutoReplyAttachPosition(bool v) async {
    _autoReplyAttachPosition = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReplyPos, v);
    notifyListeners();
  }

  Future<void> setAutoReplyAllCallers(bool v) async {
    _autoReplyAllCallers = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoReplyAll, v);
    notifyListeners();
  }

  Future<void> setAutoReplyMessage(String v) async {
    final cleaned = v.trim();
    _autoReplyMessage = cleaned.isEmpty ? defaultAutoReplyMessage : cleaned;
    (await SharedPreferences.getInstance()).setString(_kAutoReplyText, _autoReplyMessage);
    notifyListeners();
  }
```

- [ ] **Step 7: Lancer les tests et vérifier qu'ils passent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: PASS — les tests existants plus les 3 nouveaux

- [ ] **Step 8: Commit**

```bash
git add lib/providers/settings_provider.dart test/providers/settings_provider_test.dart
git commit -m "feat: reglages d auto-reponse aux appels"
```

---

### Task 4: Composition du message

Assemble le texte envoyé. Le cas critique est l'absence de position : le
message doit partir quand même, sans coordonnées. Un SMS de sécurité qui
n'arrive pas parce que le GPS n'a pas encore accroché est un échec.

**Files:**
- Create: `lib/services/auto_reply_composer.dart`
- Test: `test/services/auto_reply_composer_test.dart`

**Interfaces:**
- Consumes: `GpsSnapshot` de `lib/services/location_service.dart` — champs utilisés : `sosText`, `googleMapsUrl`
- Produces: `AutoReplyComposer.compose({required String message, required bool attachPosition, GpsSnapshot? snapshot}) → String`

- [ ] **Step 1: Écrire les tests qui échouent**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/auto_reply_composer.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snapshot() => GpsSnapshot(
  position:       const LatLng(45.123456, 6.654321),
  accuracyMeters: 8,
  altitudeMeters: 1840,
  speedKmh:       0,
  headingDeg:     0,
  timestamp:      DateTime.utc(2026, 9, 3, 14, 30),
);

void main() {
  test('sans position, le message part seul', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule', attachPosition: false, snapshot: _snapshot(),
    );
    expect(text, 'Je roule');
  });

  test('avec position, coordonnées et lien Google Maps sont joints', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: _snapshot(),
    );
    expect(text, startsWith('Je roule, je suis ici'));
    expect(text, contains('45.123456'));
    expect(text, contains('https://maps.google.com/?q=45.123456,6.654321'));
  });

  test('position demandée mais GPS indisponible : le message part quand même', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: null,
    );
    expect(text, startsWith('Je roule, je suis ici'));
    expect(text, contains('position indisponible'));
    expect(text, isNot(contains('maps.google.com')));
  });

  test('le message reste sous la limite de 5 SMS concaténés', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: _snapshot(),
    );
    expect(text.length, lessThan(600));
  });
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/services/auto_reply_composer_test.dart`
Expected: FAIL — paquet `auto_reply_composer.dart` introuvable

- [ ] **Step 3: Écrire l'implémentation**

```dart
import 'location_service.dart';

// ── Composition du SMS d'auto-réponse ────────────────────────
class AutoReplyComposer {
  /// Assemble le texte envoyé au correspondant.
  ///
  /// Si la position est demandée mais indisponible — GPS pas encore accroché,
  /// tunnel, permission refusée — le message part malgré tout en le signalant.
  /// Un SMS de sécurité muet serait pire qu'un SMS incomplet.
  static String compose({
    required String message,
    required bool attachPosition,
    GpsSnapshot? snapshot,
  }) {
    if (!attachPosition) return message;

    if (snapshot == null) {
      return '$message\n\n(position indisponible pour le moment)';
    }

    return '$message\n\n'
        'Je suis ici :\n'
        '${snapshot.sosText}\n\n'
        '${snapshot.googleMapsUrl}';
  }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `flutter test test/services/auto_reply_composer_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: Commit**

```bash
git add lib/services/auto_reply_composer.dart test/services/auto_reply_composer_test.dart
git commit -m "feat: composition du SMS d auto-reponse avec position optionnelle"
```

---

### Task 5: Politique de réponse

Le cœur de la fonction : décider s'il faut répondre. C'est ici que vivent les
deux garde-fous du spec §9.1 — ne rien envoyer hors sortie, ne répondre qu'aux
contacts de confiance.

**Files:**
- Create: `lib/services/auto_reply_policy.dart`
- Test: `test/services/auto_reply_policy_test.dart`

**Interfaces:**
- Consumes: `PhoneNumberMatcher.matches` (Task 1)
- Produces: `AutoReplyPolicy({required bool enabled, required bool allCallers, required bool riding, required List<String> trustedPhones})` et `shouldReply(String callerNumber) → bool`

- [ ] **Step 1: Écrire les tests qui échouent**

```dart
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
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/services/auto_reply_policy_test.dart`
Expected: FAIL — paquet `auto_reply_policy.dart` introuvable

- [ ] **Step 3: Écrire l'implémentation**

```dart
import 'phone_number_matcher.dart';

// ── Faut-il répondre à cet appel ? ───────────────────────────
//
// Deux garde-fous encadrent la fonction (spec §9.1) :
//   — elle ne s'active que pendant une sortie, sinon le téléphone posé sur une
//     table répondrait « je roule » à tout le monde ;
//   — elle ne répond qu'aux contacts de confiance, sinon la position GPS
//     partirait vers des démarcheurs.
class AutoReplyPolicy {
  final bool enabled;
  final bool allCallers;
  final bool riding;
  final List<String> trustedPhones;

  const AutoReplyPolicy({
    required this.enabled,
    required this.allCallers,
    required this.riding,
    required this.trustedPhones,
  });

  bool shouldReply(String callerNumber) {
    if (!enabled || !riding) return false;

    // Numéro masqué, ou permission READ_CALL_LOG refusée : aucun destinataire
    // possible, et aucun moyen de savoir à qui on parlerait.
    if (PhoneNumberMatcher.normalize(callerNumber).isEmpty) return false;

    if (allCallers) return true;
    return trustedPhones.any((p) => PhoneNumberMatcher.matches(p, callerNumber));
  }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `flutter test test/services/auto_reply_policy_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 5: Commit**

```bash
git add lib/services/auto_reply_policy.dart test/services/auto_reply_policy_test.dart
git commit -m "feat: politique de decision de l auto-reponse aux appels"
```

---

### Task 6: Pont natif Android

Les trois capacités qu'Android seul fournit. `url_launcher` ne convient pas
pour le SMS : il ouvre l'application de messagerie et attend une pression, ce
qui exclut toute réponse automatique. `SmsManager` est donc appelé directement.

**Files:**
- Create: `android/app/src/main/kotlin/app/motooffroad/CallBridge.kt`
- Create: `lib/services/call_bridge.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/app/motooffroad/MainActivity.kt`
- Test: `test/services/call_bridge_test.dart`

**Interfaces:**
- Consumes: rien
- Produces:
  - `CallEventType` — énumération `{ incoming, quickReply }`
  - `CallEvent({required CallEventType type, required String number, int index = -1})`
  - `CallBridge()` (singleton via `factory`), `events → Stream<CallEvent>`, `sendSms(String phone, String text) → Future<bool>`, `showBanner(List<String> labels, String number) → Future<void>`, `hideBanner() → Future<void>`, `hasPermissions() → Future<bool>`, `requestPermissions() → Future<bool>`
  - Noms de canaux : `app.motooffroad/call` (méthodes), `app.motooffroad/call_events` (événements)

- [ ] **Step 1: Écrire le test qui échoue**

Le test simule le côté natif en interceptant le `MethodChannel`, ce qui
valide la façade Dart sans appareil.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/call_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.motooffroad/call');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'sendSms') return true;
      if (call.method == 'hasPermissions') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sendSms transmet le numéro et le texte au natif', () async {
    final ok = await CallBridge().sendSms('+33612345678', 'Je roule');
    expect(ok, isTrue);
    expect(calls.single.method, 'sendSms');
    expect(calls.single.arguments['phone'], '+33612345678');
    expect(calls.single.arguments['text'], 'Je roule');
  });

  test('showBanner transmet au plus trois libellés', () async {
    await CallBridge().showBanner(['a', 'b', 'c', 'd'], '0612345678');
    expect(calls.single.method, 'showBanner');
    expect((calls.single.arguments['labels'] as List).length, 3);
    expect(calls.single.arguments['number'], '0612345678');
  });

  test('hasPermissions interroge le natif', () async {
    expect(await CallBridge().hasPermissions(), isTrue);
    expect(calls.single.method, 'hasPermissions');
  });

  test('un echec natif sur sendSms renvoie false au lieu de lever', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'SMS_FAILED');
    });
    expect(await CallBridge().sendSms('0612345678', 'Je roule'), isFalse);
  });
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/services/call_bridge_test.dart`
Expected: FAIL — paquet `call_bridge.dart` introuvable

- [ ] **Step 3: Écrire la façade Dart**

```dart
// lib/services/call_bridge.dart
import 'dart:io';
import 'package:flutter/services.dart';

// ── Événements remontés par le natif ─────────────────────────
enum CallEventType { incoming, quickReply }

class CallEvent {
  final CallEventType type;
  final String number;
  final int index;   // rang de la réponse rapide pressée, -1 sinon

  const CallEvent({required this.type, required this.number, this.index = -1});
}

// ── Façade des canaux natifs Android ─────────────────────────
//
// Trois capacités qu'Android seul fournit : détecter un appel entrant, envoyer
// un SMS sans intervention de l'utilisateur, afficher un bandeau à boutons.
class CallBridge {
  static const _methods = MethodChannel('app.motooffroad/call');
  static const _events  = EventChannel('app.motooffroad/call_events');
  static const int maxBannerLabels = 3;

  static final CallBridge _instance = CallBridge._();
  factory CallBridge() => _instance;
  CallBridge._();

  Stream<CallEvent>? _stream;

  Stream<CallEvent> get events {
    _stream ??= _events.receiveBroadcastStream().map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return CallEvent(
        type:   map['type'] == 'quick_reply'
                    ? CallEventType.quickReply
                    : CallEventType.incoming,
        number: map['number'] as String? ?? '',
        index:  map['index'] as int? ?? -1,
      );
    });
    return _stream!;
  }

  Future<bool> sendSms(String phone, String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('sendSms', {
        'phone': phone,
        'text':  text,
      }) ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> showBanner(List<String> labels, String number) async {
    if (!Platform.isAndroid) return;
    try {
      await _methods.invokeMethod<void>('showBanner', {
        'labels': labels.take(maxBannerLabels).toList(),
        'number': number,
      });
    } on PlatformException {
      // Le bandeau est un confort : son échec ne doit pas empêcher
      // l'auto-réponse, qui est la fonction de sécurité.
    }
  }

  Future<void> hideBanner() async {
    if (!Platform.isAndroid) return;
    try {
      await _methods.invokeMethod<void>('hideBanner');
    } on PlatformException {
      // Idem : sans conséquence sur la sécurité.
    }
  }

  Future<bool> hasPermissions() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('hasPermissions') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `flutter test test/services/call_bridge_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: Ajouter les permissions au manifeste**

Dans `android/app/src/main/AndroidManifest.xml`, après le bloc `<!-- SMS d'urgence -->` :

```xml
    <!-- Auto-réponse aux appels : READ_CALL_LOG est indispensable, sans elle
         Android 9+ ne communique pas le numéro de l'appelant -->
    <uses-permission android:name="android.permission.READ_PHONE_STATE"/>
    <uses-permission android:name="android.permission.READ_CALL_LOG"/>
```

- [ ] **Step 6: Écrire le pont Kotlin**

```kotlin
// android/app/src/main/kotlin/app/motooffroad/CallBridge.kt
package app.motooffroad

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ── Pont natif : appels entrants, SMS, bandeau ───────────────
class CallBridge(private val activity: Activity) : EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "app.motooffroad/call"
        const val EVENT_CHANNEL = "app.motooffroad/call_events"
        private const val PERMISSION_REQUEST = 4201

        private val REQUIRED = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.SEND_SMS
        )

        // Le récepteur des boutons du bandeau passe par ici.
        var sink: EventChannel.EventSink? = null
    }

    private var callReceiver: BroadcastReceiver? = null
    private var lastState: String? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        registerCallReceiver()
    }

    override fun onCancel(arguments: Any?) {
        unregisterCallReceiver()
        sink = null
    }

    // ── Détection d'appel entrant ────────────────────────────
    private fun registerCallReceiver() {
        if (callReceiver != null) return
        callReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val state = intent?.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return

                // Android émet plusieurs fois le même état ; on ne réagit qu'au
                // passage effectif vers RINGING.
                if (state == lastState) return
                lastState = state

                if (state != TelephonyManager.EXTRA_STATE_RINGING) {
                    QuickReplyNotification.hide(activity)
                    return
                }

                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                sink?.success(mapOf("type" to "incoming", "number" to number, "index" to -1))
            }
        }
        activity.registerReceiver(callReceiver, IntentFilter("android.intent.action.PHONE_STATE"))
    }

    private fun unregisterCallReceiver() {
        callReceiver?.let { activity.unregisterReceiver(it) }
        callReceiver = null
    }

    // ── Méthodes appelées depuis Dart ────────────────────────
    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sendSms" -> {
                val phone = call.argument<String>("phone") ?: ""
                val text = call.argument<String>("text") ?: ""
                result.success(sendSms(phone, text))
            }
            "showBanner" -> {
                val labels = call.argument<List<String>>("labels") ?: emptyList()
                val number = call.argument<String>("number") ?: ""
                QuickReplyNotification.show(activity, labels, number)
                result.success(null)
            }
            "hideBanner" -> {
                QuickReplyNotification.hide(activity)
                result.success(null)
            }
            "hasPermissions" -> result.success(hasPermissions())
            "requestPermissions" -> {
                ActivityCompat.requestPermissions(activity, REQUIRED, PERMISSION_REQUEST)
                result.success(hasPermissions())
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermissions(): Boolean = REQUIRED.all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    // Un message long est découpé par l'opérateur : sendMultipartTextMessage
    // évite la troncature quand la position est jointe.
    private fun sendSms(phone: String, text: String): Boolean {
        if (phone.isBlank() || !hasPermissions()) return false
        return try {
            val manager = if (android.os.Build.VERSION.SDK_INT >= 31) {
                activity.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = manager.divideMessage(text)
            manager.sendMultipartTextMessage(phone, null, parts, null, null)
            true
        } catch (e: Exception) {
            false
        }
    }
}
```

- [ ] **Step 7: Écrire le bandeau de notification**

```kotlin
// android/app/src/main/kotlin/app/motooffroad/QuickReplyNotification.kt
package app.motooffroad

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

// ── Bandeau de réponses rapides pendant un appel ─────────────
//
// Une notification prioritaire plutôt qu'une fenêtre SYSTEM_ALERT_WINDOW : pas
// de permission spéciale à accorder, et aucune surcouche constructeur ne la
// révoque. Android n'affiche que trois boutons d'action (spec §9.2).
object QuickReplyNotification {
    private const val CHANNEL_ID = "quick_reply"
    private const val NOTIFICATION_ID = 4202
    const val ACTION_TAP = "app.motooffroad.QUICK_REPLY_TAP"
    const val EXTRA_INDEX = "index"
    const val EXTRA_NUMBER = "number"

    fun show(context: Context, labels: List<String>, number: String) {
        ensureChannel(context)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setContentTitle("Appel entrant")
            .setContentText("Répondre par SMS sans décrocher")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setOngoing(false)

        labels.take(3).forEachIndexed { index, label ->
            val intent = Intent(context, QuickReplyReceiver::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_INDEX, index)
                putExtra(EXTRA_NUMBER, number)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, label, pending)
        }

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS refusée : l'auto-réponse fonctionne toujours.
        }
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Réponses rapides aux appels",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Bandeau proposant de répondre par SMS pendant un appel"
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
```

```kotlin
// android/app/src/main/kotlin/app/motooffroad/QuickReplyReceiver.kt
package app.motooffroad

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// ── Pression sur un bouton du bandeau ────────────────────────
class QuickReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != QuickReplyNotification.ACTION_TAP) return

        val index = intent.getIntExtra(QuickReplyNotification.EXTRA_INDEX, -1)
        val number = intent.getStringExtra(QuickReplyNotification.EXTRA_NUMBER) ?: ""

        CallBridge.sink?.success(
            mapOf("type" to "quick_reply", "number" to number, "index" to index)
        )
        QuickReplyNotification.hide(context)
    }
}
```

Déclarer le récepteur dans `AndroidManifest.xml`, à l'intérieur de
`<application>` :

```xml
        <receiver
            android:name=".QuickReplyReceiver"
            android:exported="false"/>
```

- [ ] **Step 8: Brancher le pont dans MainActivity**

```kotlin
// android/app/src/main/kotlin/app/motooffroad/MainActivity.kt
package app.motooffroad

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callBridge: CallBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = CallBridge(this)
        callBridge = bridge

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CallBridge.METHOD_CHANNEL)
            .setMethodCallHandler { call, result -> bridge.handle(call, result) }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CallBridge.EVENT_CHANNEL)
            .setStreamHandler(bridge)
    }

    override fun onDestroy() {
        callBridge?.onCancel(null)
        callBridge = null
        super.onDestroy()
    }
}
```

- [ ] **Step 9: Vérifier que la compilation Android passe**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 10: Lancer toute la suite**

Run: `flutter test`
Expected: PASS — 82 tests existants plus les nouveaux

- [ ] **Step 11: Commit**

```bash
git add android/app/src/main/kotlin/app/motooffroad/ android/app/src/main/AndroidManifest.xml lib/services/call_bridge.dart test/services/call_bridge_test.dart
git commit -m "feat: pont natif appels entrants, SMS automatique et bandeau"
```

---

### Task 7: Service d'orchestration

Relie le pont, la politique, le composeur et l'envoi. C'est le seul endroit qui
connaît tous les autres ; chacun des autres ignore son existence.

**Files:**
- Create: `lib/services/auto_reply_service.dart`
- Modify: `lib/main.dart`
- Test: `test/services/auto_reply_service_test.dart`

**Interfaces:**
- Consumes: `CallBridge` (Task 6), `AutoReplyPolicy` (Task 5), `AutoReplyComposer` (Task 4), `QuickReplyProvider` (Task 2), `SettingsProvider` (Task 3), `SoloProvider.contacts`, `RecordingProvider.isRecording`, `LocationService`
- Produces: `AutoReplyService({required CallBridge bridge, required AutoReplyPolicy Function() policyBuilder, required String Function() messageBuilder, required bool Function() attachPositionBuilder, required List<QuickReply> Function() repliesBuilder, required Future<GpsSnapshot?> Function() positionProvider})`, `start() → void`, `stop() → void`

- [ ] **Step 1: Écrire les tests qui échouent**

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/quick_reply.dart';
import 'package:moto_offroad/providers/quick_reply_provider.dart';
import 'package:moto_offroad/services/auto_reply_policy.dart';
import 'package:moto_offroad/services/auto_reply_service.dart';
import 'package:moto_offroad/services/call_bridge.dart';
import 'package:moto_offroad/services/location_service.dart';

// Double du pont : enregistre ce qui aurait été envoyé au natif.
class FakeCallBridge implements CallBridge {
  final _controller = StreamController<CallEvent>.broadcast();
  final sentSms = <List<String>>[];
  final banners = <List<String>>[];
  bool bannerHidden = false;

  @override
  Stream<CallEvent> get events => _controller.stream;

  void emit(CallEvent e) => _controller.add(e);

  @override
  Future<bool> sendSms(String phone, String text) async {
    sentSms.add([phone, text]);
    return true;
  }

  @override
  Future<void> showBanner(List<String> labels, String number) async =>
      banners.add(labels);

  @override
  Future<void> hideBanner() async => bannerHidden = true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;
}

GpsSnapshot _snapshot() => GpsSnapshot(
  position:       const LatLng(45.1, 6.6),
  accuracyMeters: 8, altitudeMeters: 1840, speedKmh: 0, headingDeg: 0,
  timestamp:      DateTime.utc(2026, 9, 3),
);

void main() {
  late FakeCallBridge bridge;

  AutoReplyService build({bool riding = true, bool enabled = true}) {
    bridge = FakeCallBridge();
    return AutoReplyService(
      bridge: bridge,
      policyBuilder: () => AutoReplyPolicy(
        enabled: enabled, allCallers: false, riding: riding,
        trustedPhones: const ['+33612345678'],
      ),
      messageBuilder: () => 'Je roule',
      attachPositionBuilder: () => true,
      repliesBuilder: () => QuickReplyProvider.defaults,
      positionProvider: () async => _snapshot(),
    );
  }

  test('un appel d un contact de confiance déclenche le SMS automatique', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.length, 1);
    expect(bridge.sentSms.single[0], '0612345678');
    expect(bridge.sentSms.single[1], startsWith('Je roule'));
    expect(bridge.sentSms.single[1], contains('maps.google.com'));
  });

  test('un appel refusé par la politique n envoie rien', () async {
    final service = build(riding: false);
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms, isEmpty);
    expect(bridge.banners, isEmpty);
  });

  test('un appel accepté affiche aussi le bandeau de réponses rapides', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.banners.single.length, 3);
    expect(bridge.banners.single.first, 'Je roule, je ne peux pas répondre');
  });

  test('une pression sur une réponse rapide envoie ce texte-là', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(
      type: CallEventType.quickReply, number: '0612345678', index: 2));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.single[1], "Tout va bien, j'arrive");
    expect(bridge.sentSms.single[1], isNot(contains('maps.google.com')));
  });

  test('après stop, plus rien n est envoyé', () async {
    final service = build();
    service.start();
    service.stop();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms, isEmpty);
  });
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `flutter test test/services/auto_reply_service_test.dart`
Expected: FAIL — paquet `auto_reply_service.dart` introuvable

- [ ] **Step 3: Écrire le service**

```dart
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
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `flutter test test/services/auto_reply_service_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Câbler le service au démarrage**

Dans `lib/main.dart`, ajouter `QuickReplyProvider` à la liste des providers et
démarrer le service une fois l'arbre construit. Le service lit l'état de
`RecordingProvider`, `SoloProvider` et `SettingsProvider` à chaque appel :

```dart
// Auto-réponse aux appels — le service interroge l'état courant à chaque
// appel entrant, il n'a donc pas besoin d'être reconstruit à chaque réglage.
AutoReplyService(
  bridge: CallBridge(),
  policyBuilder: () => AutoReplyPolicy(
    enabled:       settings.autoReplyEnabled,
    allCallers:    settings.autoReplyAllCallers,
    riding:        recording.isRecording || solo.soloActive,
    trustedPhones: solo.contacts.map((c) => c.phone).toList(),
  ),
  messageBuilder:        () => settings.autoReplyMessage,
  attachPositionBuilder: () => settings.autoReplyAttachPosition,
  repliesBuilder:        () => quickReplies.replies,
  positionProvider:      () => LocationService().getCurrentPosition(),
).start();
```

- [ ] **Step 6: Lancer toute la suite et l'analyse**

Run: `flutter test && flutter analyze`
Expected: tests PASS, analyse sans nouvelle alerte

- [ ] **Step 7: Commit**

```bash
git add lib/services/auto_reply_service.dart lib/main.dart test/services/auto_reply_service_test.dart
git commit -m "feat: orchestration de l auto-reponse aux appels entrants"
```

---

### Task 8: Écran de réglages « Appels et position »

**Files:**
- Create: `lib/screens/settings/call_settings_screen.dart`
- Modify: `lib/app/router.dart`
- Modify: `lib/screens/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsProvider` (Task 3), `QuickReplyProvider` (Task 2), `CallBridge.hasPermissions/requestPermissions` (Task 6)
- Produces: route `AppRoutes.callSettings = '/call-settings'`

- [ ] **Step 1: Écrire l'écran**

Le bandeau de permissions est en tête et les interrupteurs sont inertes tant
qu'elles manquent : un réglage qui paraît actif alors que la fonction ne peut
pas s'exécuter donnerait au pilote un faux sentiment de sécurité.

```dart
// lib/screens/settings/call_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../models/quick_reply.dart';
import '../../providers/quick_reply_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/call_bridge.dart';

class CallSettingsScreen extends StatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  State<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<CallSettingsScreen> {
  bool _granted = true;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final granted = await CallBridge().hasPermissions();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _askPermissions() async {
    await CallBridge().requestPermissions();
    await _refreshPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final replies  = context.watch<QuickReplyProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('Appels et position')),
      body: ListView(
        children: [
          if (!_granted) _permissionBanner(),
          _sectionLabel('AUTO-RÉPONSE'),
          SwitchListTile(
            title: const Text('Répondre automatiquement aux appels',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Uniquement pendant un enregistrement ou en mode Solo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyEnabled,
            onChanged: _granted ? settings.setAutoReplyEnabled : null,
          ),
          ListTile(
            enabled: _granted,
            title: const Text('Message envoyé',
              style: TextStyle(color: Colors.white)),
            subtitle: Text(settings.autoReplyMessage,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.edit, color: AppColors.textMuted),
            onTap: _granted
                ? () => _editText(
                      title: 'Message envoyé',
                      initial: settings.autoReplyMessage,
                      onSave: settings.setAutoReplyMessage,
                    )
                : null,
          ),
          SwitchListTile(
            title: const Text('Joindre ma position',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text('Ajoute les coordonnées et le lien Google Maps',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyAttachPosition,
            onChanged: _granted ? settings.setAutoReplyAttachPosition : null,
          ),
          SwitchListTile(
            title: const Text('Répondre à tous les appelants',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Sinon, seuls vos contacts de confiance reçoivent une réponse',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyAllCallers,
            onChanged: _granted ? settings.setAutoReplyAllCallers : null,
          ),
          const Divider(color: Color(0xFF2A2A3E)),
          _sectionLabel('RÉPONSES RAPIDES (3 maximum)'),
          ...replies.replies.map((r) => _replyTile(r, replies)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: replies.resetToDefaults,
              child: const Text('Rétablir les réponses par défaut'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionBanner() => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.red.withOpacity(.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.red),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Permissions manquantes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          "Sans l'accès au téléphone, au journal d'appels et aux SMS, "
          "l'auto-réponse ne peut pas fonctionner.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _askPermissions,
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );

  Widget _replyTile(QuickReply reply, QuickReplyProvider provider) => ListTile(
    title: Text(reply.text, style: const TextStyle(color: Colors.white)),
    subtitle: Text(
      reply.attachPosition ? 'Position jointe' : 'Sans position',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    trailing: Switch(
      value: reply.attachPosition,
      onChanged: (v) => provider.updateReply(reply.id, attachPosition: v),
    ),
    onTap: () => _editText(
      title: 'Réponse rapide',
      initial: reply.text,
      onSave: (v) => provider.updateReply(reply.id, text: v),
    ),
  );

  Future<void> _editText({
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 160,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) await onSave(saved);
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: const TextStyle(
      color: AppColors.textMuted, fontSize: 12,
      fontWeight: FontWeight.w700, letterSpacing: 1)),
  );
}
```

Vérifier que `AppColors.bgDark`, `AppColors.textMuted`, `AppColors.textSecondary`
et `AppColors.red` existent bien dans `lib/app/theme.dart` ; ils sont utilisés
tels quels par `settings_screen.dart` et `solo_screen.dart`.

- [ ] **Step 2: Déclarer la route**

Dans `lib/app/router.dart`, ajouter à `AppRoutes` :

```dart
  static const String callSettings = '/call-settings';
```

et la route, à côté de celle de `calibration` :

```dart
    GoRoute(
      path: AppRoutes.callSettings,
      pageBuilder: (_, __) => const MaterialPage(
        fullscreenDialog: true, child: CallSettingsScreen()),
    ),
```

- [ ] **Step 3: Ajouter l'entrée dans les réglages**

Dans `_recordingSection` de `lib/screens/settings/settings_screen.dart`, après
le dernier `ListTile` de la section :

```dart
        ListTile(
          leading: const Icon(Icons.phone_callback, color: AppColors.textMuted),
          title: const Text('Appels et position',
            style: TextStyle(color: Colors.white)),
          subtitle: const Text('Auto-réponse SMS, réponses rapides',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          onTap: () => context.push(AppRoutes.callSettings),
        ),
```

- [ ] **Step 4: Vérifier la compilation et l'analyse**

Run: `flutter analyze && flutter test`
Expected: aucune nouvelle alerte, tests au vert

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings/call_settings_screen.dart lib/app/router.dart lib/screens/settings/settings_screen.dart
git commit -m "feat: ecran de reglages appels et position"
```

---

### Task 9: Écran « Envoyer ma position »

Répond au besoin du spec §9.3 : si la personne de confiance n'ouvre pas la page
web de suivi, elle reçoit tout de même un point à coller dans Google Maps.

**Files:**
- Create: `lib/screens/solo/send_position_screen.dart`
- Modify: `lib/app/router.dart`
- Modify: `lib/screens/solo/solo_screen.dart`

**Interfaces:**
- Consumes: `SoloProvider.contacts`, `LocationService().getCurrentPosition()`, `GpsSnapshot.sosText`, `GpsSnapshot.googleMapsUrl`, `CallBridge().sendSms` (Task 6), `SosService().shareGeneric()`
- Produces: route `AppRoutes.sendPosition = '/send-position'`

- [ ] **Step 1: Écrire l'écran**

```dart
// lib/screens/solo/send_position_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../providers/solo_provider.dart';
import '../../services/call_bridge.dart';
import '../../services/location_service.dart';
import '../../services/sos_service.dart';

class SendPositionScreen extends StatefulWidget {
  const SendPositionScreen({super.key});

  @override
  State<SendPositionScreen> createState() => _SendPositionScreenState();
}

class _SendPositionScreenState extends State<SendPositionScreen> {
  GpsSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _loading = true);
    final snap = await LocationService().getCurrentPosition();
    if (mounted) setState(() { _snapshot = snap; _loading = false; });
  }

  String get _message =>
      'Je suis ici :\n${_snapshot!.sosText}\n\n${_snapshot!.googleMapsUrl}';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendTo(TrustedContact contact) async {
    final ok = await CallBridge().sendSms(contact.phone, _message);
    _toast(ok
        ? 'Position envoyée à ${contact.name}'
        : "Échec de l'envoi à ${contact.name}");
  }

  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0A),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: const Text('Envoyer ma position'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _positionCard(),
            const SizedBox(height: 16),
            if (_snapshot != null) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _snapshot!.googleMapsUrl));
                  _toast('Lien copié');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier le lien Google Maps'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => SosService().shareGeneric(),
                icon: const Icon(Icons.share),
                label: const Text('Partager autrement'),
              ),
              const SizedBox(height: 24),
              const Text('ENVOYER PAR SMS',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              if (solo.contacts.isEmpty) _noContacts()
              else ...solo.contacts.map((c) => ListTile(
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(c.phone,
                  style: const TextStyle(color: AppColors.textSecondary)),
                trailing: ElevatedButton(
                  onPressed: () => _sendTo(c),
                  child: const Text('Envoyer'),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _positionCard() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_snapshot == null) {
      return Column(
        children: [
          const Text('Position indisponible — vérifiez que le GPS est actif',
            style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _locate, child: const Text('Réessayer')),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_snapshot!.sosText,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 8),
          Text('Mesurée à ${_snapshot!.timestamp.toLocal()}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _noContacts() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Aucun contact de confiance enregistré',
        style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: () => context.push(AppRoutes.solo),
        child: const Text('Ajouter un contact'),
      ),
    ],
  );
}
```

- [ ] **Step 2: Déclarer la route**

Dans `lib/app/router.dart`, ajouter à `AppRoutes` :

```dart
  static const String sendPosition = '/send-position';
```

et la route à côté de celle de `solo` :

```dart
    GoRoute(
      path: AppRoutes.sendPosition,
      pageBuilder: (_, __) => const MaterialPage(
        fullscreenDialog: true, child: SendPositionScreen()),
    ),
```

- [ ] **Step 3: Ajouter l'accès depuis SoloScreen**

Dans `lib/screens/solo/solo_screen.dart`, après la section des contacts de
confiance, un bouton pleine largeur :

```dart
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.sendPosition),
                icon: const Icon(Icons.my_location),
                label: const Text('Envoyer ma position'),
              ),
```

Importer `package:go_router/go_router.dart` et `../../app/router.dart` si ce
n'est pas déjà fait.

- [ ] **Step 4: Vérifier la compilation et l'analyse**

Run: `flutter analyze && flutter test`
Expected: aucune nouvelle alerte, tests au vert

- [ ] **Step 5: Construire l'APK de test**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add lib/screens/solo/send_position_screen.dart lib/app/router.dart lib/screens/solo/solo_screen.dart
git commit -m "feat: ecran d envoi manuel de la position aux contacts"
```

---

## Vérification sur appareil

Les tests automatisés ne couvrent pas ce qui dépend de la radio du téléphone.
À faire une fois l'APK installé, avec un second téléphone :

- [ ] Accorder les permissions Téléphone, Journal d'appels et SMS au premier lancement de l'écran « Appels et position »
- [ ] Enregistrer le second téléphone comme contact de confiance
- [ ] Démarrer un enregistrement, appeler depuis le second téléphone : le SMS d'auto-réponse arrive, position jointe
- [ ] Le bandeau apparaît pendant la sonnerie ; une pression sur la deuxième réponse envoie le texte avec la position
- [ ] Appeler depuis un numéro non enregistré : rien n'est envoyé
- [ ] Arrêter l'enregistrement, rappeler depuis le contact de confiance : rien n'est envoyé
- [ ] **Écran verrouillé** : vérifier si les boutons du bandeau agissent en une pression ou exigent un déverrouillage. Comportement non garanti par Android (spec §12) — noter le résultat sur le téléphone cible
- [ ] Vérifier la lisibilité des libellés des trois boutons, et leur utilisabilité **avec des gants**. Si les boutons sont trop petits, c'est le déclencheur de la bascule vers `SYSTEM_ALERT_WINDOW` prévue en spec §9.2

## Critères de réussite du lot

Extraits de la spec §14, points 8 et 9 partiels :

1. Un appel d'un contact de confiance pendant une sortie déclenche l'auto-réponse SMS.
2. Le bandeau permet d'envoyer une des trois réponses d'une pression.
3. Hors sortie, ou depuis un numéro inconnu, rien n'est envoyé.
4. L'onglet « Envoyer ma position » transmet des coordonnées collables dans Google Maps.
5. Chaque fonction est désactivable indépendamment, et les réglages survivent au redémarrage.
6. `flutter test` et `flutter analyze` restent au vert.
