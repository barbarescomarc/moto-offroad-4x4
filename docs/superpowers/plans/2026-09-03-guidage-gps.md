# Guidage GPS (offroad, route, trace GPX) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un guidage GPS activable — routage calculé (profil Offroad/Route avec évitements fins) ou guidage sur une trace GPX déjà importée (alerte de déviation ou virage par virage), avec annonces voix+visuel et arrière-plan écran éteint.

**Architecture:** Une couche de modèles/services purs et testables (`RouteResult`, `route_geometry`, `gpx_route_deriver`, `RoutingService`) alimente un provider d'état (`GuidanceProvider`) branché sur `LocationService` existant. Le service de premier plan Android est mutualisé entre l'enregistrement de sortie et le guidage via un petit coordinateur de clients. L'UI se raccroche aux quatre points d'entrée déjà présents (recherche, carte, favoris nouveaux, groupe préparé) et à un nouveau bandeau d'instruction.

**Tech Stack:** Flutter 3.44 / Dart, `provider`, `latlong2`, `http`, `shared_preferences`, nouveau : `flutter_tts`. Backend de routage : API Directions OpenRouteService (gratuite).

**Spec:** `docs/superpowers/specs/2026-09-03-guidage-gps-design.md`

## Global Constraints

- Plateforme Android uniquement (le projet n'a pas de dossier `ios`) — cohérent avec le reste du code.
- `lib/config/api_keys.dart` est gitignored : jamais ajouté à un `git add` / commit.
- Toute dépendance réseau optionnelle doit échouer proprement (bandeau d'erreur, pas de plantage) — voir §8 de la spec.
- Les deux modes de guidage sur trace GPX (alerte / virage par virage) doivent fonctionner **sans réseau**.
- Suivre les conventions déjà en place : services avec `http.Client?` injectable (`weather_service.dart`, `update_checker.dart`), providers avec dépendances injectables optionnelles (`RecordingProvider`), persistance `shared_preferences` avec clés `_kXxx` (`SettingsProvider`, `QuickReplyProvider`), tests avec `SharedPreferences.setMockInitialValues({})` et `package:http/testing.dart` `MockClient`.
- Chaque tâche se termine par un commit. Ne jamais commiter `lib/config/api_keys.dart`.

---

## Task 1: Dépendances et clé API

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/config/api_keys.dart` (gitignored — modifié localement, jamais commité)

**Interfaces:**
- Produces: `ApiKeys.openRouteServiceApiKey` (`String`), `ApiKeys.isOrsConfigured` (`bool getter`), dépendance `flutter_tts` disponible pour les tâches 5 et 7.

- [ ] **Step 1: Ajouter `flutter_tts` à `pubspec.yaml`**

Dans la section `dependencies`, sous le bloc `# ── UI ──`, ajouter :

```yaml
  # ── Guidage ──────────────────────────────────────────
  flutter_tts: ^4.0.0          # Synthèse vocale (guidage)
```

- [ ] **Step 2: `flutter pub get`**

Run: `flutter pub get`
Expected: résolution réussie, `flutter_tts` apparaît dans `pubspec.lock`.

- [ ] **Step 3: Ajouter la clé OpenRouteService à `lib/config/api_keys.dart`**

Ajouter une nouvelle entrée dans le guide en tête de fichier (après le bloc IGN, avant Google Places) :

```
//  4bis. OPENROUTESERVICE (GUIDAGE GPS)
//     → https://openrouteservice.org/dev/#/signup
//     → Créer un compte → Dashboard → Request a token (standard, gratuit)
//     → 2000 requêtes/jour, 40/minute
```

Puis, dans la classe `ApiKeys`, après le bloc IGN Géoportail :

```dart
  // ── OpenRouteService ── REMPLACER PAR VOTRE CLÉ ──────────
  // Obtenir sur : https://openrouteservice.org/dev/#/signup
  static const String openRouteServiceApiKey = 'VOTRE_CLE_ORS_ICI';
```

Et dans le bloc de vérification :

```dart
  static bool get isOrsConfigured => openRouteServiceApiKey != 'VOTRE_CLE_ORS_ICI';
```

- [ ] **Step 4: Vérifier que le projet analyse toujours proprement**

Run: `flutter analyze`
Expected: aucune nouvelle erreur (les warnings `withOpacity` préexistants sont attendus).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: ajoute flutter_tts pour le guidage GPS"
```

(`lib/config/api_keys.dart` reste hors git — ne pas l'ajouter.)

---

## Task 2: Modèles `RouteResult` / `RouteStep`

**Files:**
- Create: `lib/models/route_result.dart`
- Test: `test/models/route_result_test.dart`

**Interfaces:**
- Produces: `enum ManeuverType`, `class RouteStep`, `class RouteResult` (avec `totalDistanceKm`, `totalDuration`) — contrat commun consommé par les tâches 4, 5, 10, 11.

- [ ] **Step 1: Écrire le test**

```dart
// test/models/route_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';

void main() {
  test('totalDistanceKm convertit les mètres en kilomètres', () {
    const r = RouteResult(
      polyline: [],
      steps: [],
      totalDistanceMeters: 4200,
      totalDurationSeconds: 600,
    );
    expect(r.totalDistanceKm, closeTo(4.2, 0.001));
  });

  test('totalDuration convertit les secondes en Duration', () {
    const r = RouteResult(
      polyline: [],
      steps: [],
      totalDistanceMeters: 0,
      totalDurationSeconds: 125,
    );
    expect(r.totalDuration, const Duration(seconds: 125));
  });

  test('RouteStep porte instruction, distance, manœuvre et position', () {
    const step = RouteStep(
      instruction: 'Tournez à gauche',
      distanceMeters: 150,
      maneuver: ManeuverType.turnLeft,
      location: LatLng(44.0, 6.0),
    );
    expect(step.instruction, 'Tournez à gauche');
    expect(step.maneuver, ManeuverType.turnLeft);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `flutter test test/models/route_result_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:moto_offroad/models/route_result.dart'`

- [ ] **Step 3: Implémenter**

```dart
// lib/models/route_result.dart
import 'package:latlong2/latlong.dart';

enum ManeuverType {
  straight,
  turnLeft,
  turnRight,
  sharpLeft,
  sharpRight,
  uturn,
  arrive,
  depart,
}

class RouteStep {
  final String instruction;
  final double distanceMeters;
  final ManeuverType maneuver;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuver,
    required this.location,
  });
}

// Contrat commun à un itinéraire calculé (OpenRouteService) et à un
// itinéraire dérivé d'une trace GPX : le reste du guidage ne sait pas
// d'où vient la donnée.
class RouteResult {
  final List<LatLng> polyline;
  final List<RouteStep> steps;
  final double totalDistanceMeters;
  final double totalDurationSeconds;

  const RouteResult({
    required this.polyline,
    required this.steps,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000;
  Duration get totalDuration => Duration(seconds: totalDurationSeconds.round());
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `flutter test test/models/route_result_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/models/route_result.dart test/models/route_result_test.dart
git commit -m "feat: modeles RouteResult/RouteStep, contrat commun du guidage"
```

---

## Task 3: Géométrie de route — `lib/utils/route_geometry.dart`

**Files:**
- Create: `lib/utils/route_geometry.dart`
- Test: `test/utils/route_geometry_test.dart`

**Interfaces:**
- Consumes: rien (fonctions pures, `latlong2` seulement).
- Produces: `nearestPointOnPolyline(LatLng, List<LatLng>) → NearestPointResult`, `distanceToPolyline(LatLng, List<LatLng>) → double`, `bearingDeltaDeg(double, double) → double` — consommés par les tâches 4 et 10.

- [ ] **Step 1: Écrire les tests**

```dart
// test/utils/route_geometry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/utils/route_geometry.dart';

void main() {
  group('distanceToPolyline', () {
    test('un point sur le segment est à distance ~0', () {
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final onSegment = const LatLng(44.005, 6.0);
      expect(distanceToPolyline(onSegment, polyline), lessThan(1));
    });

    test('un point décalé perpendiculairement donne la distance attendue', () {
      // Segment nord-sud à longitude 6.0. Un point à +0.001° de longitude
      // au même point milieu est décalé d'environ 111.32 km × cos(lat) × 0.001.
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final offset = const LatLng(44.005, 6.001);
      final expectedMeters = 111320 * 0.001; // ≈ 111 m à l'équateur, ordre de grandeur ici aussi
      expect(distanceToPolyline(offset, polyline), closeTo(expectedMeters, expectedMeters * 0.05));
    });

    test('un point au-delà d\'une extrémité donne la distance au point le plus proche', () {
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final beyondEnd = const LatLng(44.02, 6.0);
      const calc = Distance();
      final expected = calc(beyondEnd, const LatLng(44.01, 6.0));
      expect(distanceToPolyline(beyondEnd, polyline), closeTo(expected, 1));
    });

    test('polyligne vide → distance infinie', () {
      expect(distanceToPolyline(const LatLng(44.0, 6.0), []), double.infinity);
    });
  });

  group('bearingDeltaDeg', () {
    test('aucun changement de cap → delta 0', () {
      expect(bearingDeltaDeg(90, 90), 0);
    });

    test('virage à droite de 45° → delta positif', () {
      expect(bearingDeltaDeg(0, 45), 45);
    });

    test('virage à gauche de 45° → delta négatif', () {
      expect(bearingDeltaDeg(45, 0), -45);
    });

    test('passage par le nord (350° → 10°) reste un petit delta positif', () {
      expect(bearingDeltaDeg(350, 10), 20);
    });
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/utils/route_geometry_test.dart`
Expected: FAIL — fichier `route_geometry.dart` introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/utils/route_geometry.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';

class NearestPointResult {
  final LatLng point;
  final double distanceMeters;
  // Index i tel que le point le plus proche se trouve sur le segment [i, i+1].
  final int segmentIndex;

  const NearestPointResult({
    required this.point,
    required this.distanceMeters,
    required this.segmentIndex,
  });
}

const _metersPerDegLat = 111320.0;
double _metersPerDegLon(double latDeg) => 111320.0 * cos(latDeg * pi / 180);

// Projette [position] sur chaque segment de [polyline] en mètres locaux
// (approximation équirectangulaire, suffisante à l'échelle d'un guidage
// routier/offroad) et retient la projection la plus proche.
NearestPointResult nearestPointOnPolyline(LatLng position, List<LatLng> polyline) {
  if (polyline.isEmpty) {
    return NearestPointResult(point: position, distanceMeters: double.infinity, segmentIndex: -1);
  }
  if (polyline.length == 1) {
    const calc = Distance();
    return NearestPointResult(
      point: polyline.first,
      distanceMeters: calc(position, polyline.first),
      segmentIndex: 0,
    );
  }

  const calc = Distance();
  NearestPointResult? best;

  for (var i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final latRef = (a.latitude + b.latitude) / 2;
    final mLon = _metersPerDegLon(latRef);

    final bx = (b.longitude - a.longitude) * mLon;
    final by = (b.latitude - a.latitude) * _metersPerDegLat;
    final px = (position.longitude - a.longitude) * mLon;
    final py = (position.latitude - a.latitude) * _metersPerDegLat;

    final abLen2 = bx * bx + by * by;
    var t = abLen2 == 0 ? 0.0 : ((px * bx + py * by) / abLen2);
    t = t.clamp(0.0, 1.0);

    final projX = t * bx;
    final projY = t * by;
    final projected = LatLng(
      a.latitude + projY / _metersPerDegLat,
      a.longitude + projX / mLon,
    );

    final d = calc(position, projected);
    if (best == null || d < best.distanceMeters) {
      best = NearestPointResult(point: projected, distanceMeters: d, segmentIndex: i);
    }
  }
  return best!;
}

double distanceToPolyline(LatLng position, List<LatLng> polyline) =>
    nearestPointOnPolyline(position, polyline).distanceMeters;

// Delta de cap signé, normalisé dans [-180, 180]. Positif = vers la droite.
double bearingDeltaDeg(double fromDeg, double toDeg) {
  var delta = (toDeg - fromDeg) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/utils/route_geometry_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/utils/route_geometry.dart test/utils/route_geometry_test.dart
git commit -m "feat: geometrie de route - distance a la polyligne et delta de cap"
```

---

## Task 4: Dérivation d'itinéraire depuis une trace GPX

**Files:**
- Create: `lib/services/gpx_route_deriver.dart`
- Test: `test/services/gpx_route_deriver_test.dart`

**Interfaces:**
- Consumes: `RouteResult`/`RouteStep`/`ManeuverType` (Task 2), `bearingDeltaDeg` (Task 3), `TraceModel`/`TracePoint` (`lib/models/trace.dart`, existant).
- Produces: `GpxRouteDeriver.deriveForAlert(TraceModel) → RouteResult`, `GpxRouteDeriver.deriveTurnByTurn(TraceModel) → RouteResult` — consommés par la tâche 10.

- [ ] **Step 1: Écrire les tests**

```dart
// test/services/gpx_route_deriver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/services/gpx_route_deriver.dart';

TraceModel _traceFrom(List<LatLng> points) => TraceModel(
      id: 't1',
      name: 'test',
      points: points.map((p) => TracePoint(position: p)).toList(),
    );

void main() {
  group('deriveForAlert', () {
    test('reprend la polyligne telle quelle, sans étape', () {
      final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
      final result = GpxRouteDeriver.deriveForAlert(trace);
      expect(result.polyline.length, 2);
      expect(result.steps, isEmpty);
    });
  });

  group('deriveTurnByTurn', () {
    test('une ligne droite ne génère aucun virage', () {
      // 5 points alignés, espacés de ~1.1 km chacun (0.01° de latitude).
      final trace = _traceFrom([
        const LatLng(44.00, 6.0),
        const LatLng(44.01, 6.0),
        const LatLng(44.02, 6.0),
        const LatLng(44.03, 6.0),
        const LatLng(44.04, 6.0),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      // Seule l'étape d'arrivée est attendue.
      expect(result.steps.length, 1);
      expect(result.steps.single.maneuver, ManeuverType.arrive);
    });

    test('un tracé en L génère un virage classé à droite', () {
      // Direction plein nord puis plein est : virage à droite.
      final trace = _traceFrom([
        const LatLng(44.00, 6.00),
        const LatLng(44.01, 6.00),
        const LatLng(44.02, 6.00),
        const LatLng(44.02, 6.01),
        const LatLng(44.02, 6.02),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns.length, 1);
      expect(
        turns.single.maneuver,
        anyOf(ManeuverType.turnRight, ManeuverType.sharpRight),
      );
    });

    test('un tracé en L inversé génère un virage classé à gauche', () {
      final trace = _traceFrom([
        const LatLng(44.00, 6.00),
        const LatLng(44.01, 6.00),
        const LatLng(44.02, 6.00),
        const LatLng(44.02, 5.99),
        const LatLng(44.02, 5.98),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns.length, 1);
      expect(
        turns.single.maneuver,
        anyOf(ManeuverType.turnLeft, ManeuverType.sharpLeft),
      );
    });

    test('des points rapprochés (bruit GPS) ne créent pas de faux virage', () {
      // Ligne droite mais avec des points tous les 2-3 mètres environ
      // (0.00002°) — bien en dessous du seuil d'échantillonnage.
      final trace = _traceFrom(List.generate(
        200,
        (i) => LatLng(44.0 + i * 0.00002, 6.0 + (i.isEven ? 0.0000005 : -0.0000005)),
      ));
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns, isEmpty);
    });

    test('une trace de moins de 3 points ne génère aucun virage', () {
      final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      expect(result.steps, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/services/gpx_route_deriver_test.dart`
Expected: FAIL — fichier `gpx_route_deriver.dart` introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/services/gpx_route_deriver.dart
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/trace.dart';
import '../utils/route_geometry.dart';

// Transforme une trace GPX déjà importée en RouteResult, sans appel réseau —
// utilisé par les deux modes de guidage sur trace GPX (alerte de déviation
// et virage par virage).
class GpxRouteDeriver {
  // Changement de cap (°) au-delà duquel un point est considéré comme un virage.
  static const double turnThresholdDeg = 25;
  // Changement de cap (°) au-delà duquel le virage est qualifié de serré.
  static const double sharpTurnThresholdDeg = 70;
  // Distance minimale (m) entre deux points comparés — lisse le bruit GPS
  // des traces enregistrées à haute fréquence.
  static const double minSegmentMeters = 15;

  static const _calc = Distance();

  static RouteResult deriveForAlert(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    return RouteResult(
      polyline: points,
      steps: const [],
      totalDistanceMeters: trace.distanceMeters,
      totalDurationSeconds: 0,
    );
  }

  static RouteResult deriveTurnByTurn(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    if (points.length < 3) {
      return RouteResult(
        polyline: points,
        steps: const [],
        totalDistanceMeters: trace.distanceMeters,
        totalDurationSeconds: 0,
      );
    }

    final anchors = _sampleAnchors(points);
    final steps = <RouteStep>[];

    if (anchors.length >= 3) {
      for (var i = 1; i < anchors.length - 1; i++) {
        final prev = points[anchors[i - 1]];
        final curr = points[anchors[i]];
        final next = points[anchors[i + 1]];

        final bearingIn = _calc.bearing(prev, curr);
        final bearingOut = _calc.bearing(curr, next);
        final delta = bearingDeltaDeg(bearingIn, bearingOut);

        if (delta.abs() < turnThresholdDeg) continue;

        final maneuver = _maneuverFor(delta);
        steps.add(RouteStep(
          instruction: _instructionFor(maneuver),
          distanceMeters: _calc(points[anchors[i - 1]], curr),
          maneuver: maneuver,
          location: curr,
        ));
      }
    }

    steps.add(RouteStep(
      instruction: 'Destination atteinte',
      distanceMeters: _calc(points[anchors.last], points.last),
      maneuver: ManeuverType.arrive,
      location: points.last,
    ));

    return RouteResult(
      polyline: points,
      steps: steps,
      totalDistanceMeters: trace.distanceMeters,
      totalDurationSeconds: 0,
    );
  }

  static List<int> _sampleAnchors(List<LatLng> points) {
    final anchors = <int>[0];
    var lastIdx = 0;
    for (var i = 1; i < points.length; i++) {
      if (_calc(points[lastIdx], points[i]) >= minSegmentMeters) {
        anchors.add(i);
        lastIdx = i;
      }
    }
    if (anchors.last != points.length - 1) anchors.add(points.length - 1);
    return anchors;
  }

  static ManeuverType _maneuverFor(double deltaDeg) {
    final abs = deltaDeg.abs();
    if (abs >= 150) return ManeuverType.uturn;
    if (deltaDeg > 0) {
      return abs >= sharpTurnThresholdDeg ? ManeuverType.sharpRight : ManeuverType.turnRight;
    }
    return abs >= sharpTurnThresholdDeg ? ManeuverType.sharpLeft : ManeuverType.turnLeft;
  }

  static String _instructionFor(ManeuverType m) {
    switch (m) {
      case ManeuverType.turnLeft:   return 'Tournez à gauche';
      case ManeuverType.turnRight:  return 'Tournez à droite';
      case ManeuverType.sharpLeft:  return 'Virage serré à gauche';
      case ManeuverType.sharpRight: return 'Virage serré à droite';
      case ManeuverType.uturn:      return 'Faites demi-tour';
      case ManeuverType.arrive:     return 'Destination atteinte';
      case ManeuverType.depart:     return 'Départ';
      case ManeuverType.straight:   return 'Continuez tout droit';
    }
  }
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/services/gpx_route_deriver_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/gpx_route_deriver.dart test/services/gpx_route_deriver_test.dart
git commit -m "feat: derivation d'itineraire hors-ligne depuis une trace GPX"
```

---

## Task 5: `RoutingService` — appel OpenRouteService

**Files:**
- Create: `lib/services/routing_service.dart`
- Test: `test/services/routing_service_test.dart`

**Interfaces:**
- Consumes: `RouteResult`/`RouteStep`/`ManeuverType` (Task 2), `ApiKeys.openRouteServiceApiKey` (Task 1).
- Produces: `enum RoutingProfile { drivingCar, cyclingMountain }`, `enum AvoidFeature { highways, tollways, ferries }`, `class RoutingException`, `RoutingService.fetchRoute({origin, destination, profile, avoid}) → Future<RouteResult>` (lève `RoutingException` en cas d'échec) — consommés par les tâches 10, 15, 17.

- [ ] **Step 1: Écrire les tests**

```dart
// test/services/routing_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/services/routing_service.dart';

const _sampleOrsResponse = '''
{
  "features": [
    {
      "geometry": {
        "coordinates": [[6.0, 44.0], [6.005, 44.005], [6.01, 44.01]]
      },
      "properties": {
        "summary": {"distance": 1500.0, "duration": 300.0},
        "segments": [
          {
            "distance": 1500.0,
            "duration": 300.0,
            "steps": [
              {"distance": 800.0, "duration": 150.0, "type": 11, "instruction": "Partez", "way_points": [0, 1]},
              {"distance": 700.0, "duration": 150.0, "type": 1, "instruction": "Tournez à droite", "way_points": [1, 2]},
              {"distance": 0.0, "duration": 0.0, "type": 10, "instruction": "Arrivée", "way_points": [2, 2]}
            ]
          }
        ]
      }
    }
  ]
}
''';

void main() {
  group('fetchRoute', () {
    test('parse une réponse ORS valide en RouteResult', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('driving-car'));
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      final result = await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.drivingCar,
      );

      expect(result.polyline.length, 3);
      expect(result.polyline.first, const LatLng(44.0, 6.0));
      expect(result.steps.length, 3);
      expect(result.steps[1].maneuver, ManeuverType.turnRight);
      expect(result.totalDistanceMeters, 1500.0);
    });

    test('envoie les avoid_features demandés', () async {
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.drivingCar,
        avoid: {AvoidFeature.highways, AvoidFeature.tollways},
      );

      final avoidFeatures = (sentBody['options'] as Map<String, dynamic>)['avoid_features'] as List;
      expect(avoidFeatures, containsAll(['highways', 'tollways']));
    });

    test('utilise le profil cycling-mountain en offroad', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('cycling-mountain'));
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.cyclingMountain,
      );
    });

    test('lève RoutingException sur erreur réseau', () async {
      final client = MockClient((request) async => throw Exception('pas de réseau'));
      final service = RoutingService(client: client);

      expect(
        () => service.fetchRoute(
          origin: const LatLng(44.0, 6.0),
          destination: const LatLng(44.01, 6.01),
          profile: RoutingProfile.drivingCar,
        ),
        throwsA(isA<RoutingException>()),
      );
    });

    test('lève RoutingException sur code 429 (quota dépassé)', () async {
      final client = MockClient((request) async => http.Response('{}', 429));
      final service = RoutingService(client: client);

      expect(
        () => service.fetchRoute(
          origin: const LatLng(44.0, 6.0),
          destination: const LatLng(44.01, 6.01),
          profile: RoutingProfile.drivingCar,
        ),
        throwsA(isA<RoutingException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/services/routing_service_test.dart`
Expected: FAIL — fichier `routing_service.dart` introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/services/routing_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../models/route_result.dart';

enum RoutingProfile { drivingCar, cyclingMountain }

extension RoutingProfileExt on RoutingProfile {
  String get orsId {
    switch (this) {
      case RoutingProfile.drivingCar:      return 'driving-car';
      case RoutingProfile.cyclingMountain: return 'cycling-mountain';
    }
  }
}

enum AvoidFeature { highways, tollways, ferries }

extension AvoidFeatureExt on AvoidFeature {
  String get orsId {
    switch (this) {
      case AvoidFeature.highways: return 'highways';
      case AvoidFeature.tollways: return 'tollways';
      case AvoidFeature.ferries:  return 'ferries';
    }
  }
}

class RoutingException implements Exception {
  final String message;
  const RoutingException(this.message);
  @override
  String toString() => message;
}

class RoutingService {
  final http.Client _client;
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    final uri = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/${profile.orsId}/geojson');

    final body = <String, dynamic>{
      'coordinates': [
        [origin.longitude, origin.latitude],
        [destination.longitude, destination.latitude],
      ],
      'instructions': true,
      'language': 'fr',
      if (avoid.isNotEmpty)
        'options': {'avoid_features': avoid.map((a) => a.orsId).toList()},
    };

    http.Response resp;
    try {
      resp = await _client
          .post(
            uri,
            headers: {
              'Authorization': ApiKeys.openRouteServiceApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const RoutingException(
          "Impossible de calculer l'itinéraire — vérifie ta connexion");
    }

    if (resp.statusCode == 429) {
      throw const RoutingException('Service de guidage indisponible, réessaie plus tard');
    }
    if (resp.statusCode != 200) {
      throw const RoutingException("Impossible de calculer l'itinéraire");
    }

    return _parse(resp.body);
  }

  RouteResult _parse(String rawBody) {
    final json = jsonDecode(rawBody) as Map<String, dynamic>;
    final feature = (json['features'] as List<dynamic>).first as Map<String, dynamic>;

    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;
    final polyline = coords
        .map((c) => LatLng((c as List)[1] as double, (c[0] as num).toDouble()))
        .toList();

    final properties = feature['properties'] as Map<String, dynamic>;
    final summary = properties['summary'] as Map<String, dynamic>;
    final segments = properties['segments'] as List<dynamic>;

    final steps = <RouteStep>[];
    for (final segment in segments) {
      final segSteps = (segment as Map<String, dynamic>)['steps'] as List<dynamic>;
      for (final s in segSteps) {
        final step = s as Map<String, dynamic>;
        final wayPoints = step['way_points'] as List<dynamic>;
        final pointIndex = (wayPoints.first as num).toInt().clamp(0, polyline.length - 1);
        steps.add(RouteStep(
          instruction:    step['instruction'] as String,
          distanceMeters: (step['distance'] as num).toDouble(),
          maneuver:       _maneuverFromOrsType((step['type'] as num).toInt()),
          location:       polyline[pointIndex],
        ));
      }
    }

    return RouteResult(
      polyline: polyline,
      steps: steps,
      totalDistanceMeters:  (summary['distance'] as num).toDouble(),
      totalDurationSeconds: (summary['duration'] as num).toDouble(),
    );
  }

  // Codes de manœuvre ORS — slight/keep sont regroupés avec le virage
  // correspondant pour rester sur l'ensemble d'instructions déjà utilisé
  // par le mode GPX (voir gpx_route_deriver.dart).
  ManeuverType _maneuverFromOrsType(int type) {
    switch (type) {
      case 0: case 4: case 12: return ManeuverType.turnLeft;
      case 1: case 5: case 13: return ManeuverType.turnRight;
      case 2:  return ManeuverType.sharpLeft;
      case 3:  return ManeuverType.sharpRight;
      case 9:  return ManeuverType.uturn;
      case 10: return ManeuverType.arrive;
      case 11: return ManeuverType.depart;
      default: return ManeuverType.straight;
    }
  }
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/services/routing_service_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/routing_service.dart test/services/routing_service_test.dart
git commit -m "feat: RoutingService - appel Directions OpenRouteService"
```

---

## Task 6: Favoris — modèle et provider

**Files:**
- Create: `lib/models/favorite_place.dart`
- Create: `lib/providers/favorites_provider.dart`
- Test: `test/providers/favorites_provider_test.dart`

**Interfaces:**
- Consumes: rien de nouveau (`shared_preferences`, `uuid`, `latlong2`, déjà des dépendances du projet).
- Produces: `class FavoritePlace {id, name, position}`, `FavoritesProvider.places`, `.load()`, `.add(name, position)`, `.remove(id)` — consommés par les tâches 12, 13, 17.

- [ ] **Step 1: Écrire les tests**

```dart
// test/providers/favorites_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/favorites_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aucun favori par défaut', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    expect(p.places, isEmpty);
  });

  test('ajouter un favori le rend disponible et le persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    await p.add('Garage', const LatLng(44.0, 6.0));

    expect(p.places, hasLength(1));
    expect(p.places.single.name, 'Garage');

    final reloaded = FavoritesProvider();
    await reloaded.load();
    expect(reloaded.places, hasLength(1));
    expect(reloaded.places.single.name, 'Garage');
  });

  test('supprimer un favori le retire de la liste et de la persistance', () async {
    SharedPreferences.setMockInitialValues({});
    final p = FavoritesProvider();
    await p.load();
    await p.add('Garage', const LatLng(44.0, 6.0));
    final id = p.places.single.id;

    await p.remove(id);
    expect(p.places, isEmpty);

    final reloaded = FavoritesProvider();
    await reloaded.load();
    expect(reloaded.places, isEmpty);
  });

  test('une sauvegarde corrompue ne fait pas planter le chargement', () async {
    SharedPreferences.setMockInitialValues({'favorite_places': 'pas du json valide'});
    final p = FavoritesProvider();
    await p.load();
    expect(p.places, isEmpty);
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/providers/favorites_provider_test.dart`
Expected: FAIL — fichiers introuvables.

- [ ] **Step 3: Implémenter le modèle**

```dart
// lib/models/favorite_place.dart
import 'package:latlong2/latlong.dart';

class FavoritePlace {
  final String id;
  final String name;
  final LatLng position;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
    'id':   id,
    'name': name,
    'lat':  position.latitude,
    'lon':  position.longitude,
  };

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
    id:   j['id'] as String,
    name: j['name'] as String,
    position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
  );
}
```

- [ ] **Step 4: Implémenter le provider**

```dart
// lib/providers/favorites_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/favorite_place.dart';

class FavoritesProvider extends ChangeNotifier {
  static const _kFavorites = 'favorite_places';
  final _uuid = const Uuid();

  List<FavoritePlace> _places = [];
  List<FavoritePlace> get places => List.unmodifiable(_places);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _places = _decode(prefs.getString(_kFavorites));
    notifyListeners();
  }

  List<FavoritePlace> _decode(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => FavoritePlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavorites, jsonEncode(_places.map((p) => p.toJson()).toList()));
  }

  Future<void> add(String name, LatLng position) async {
    _places.add(FavoritePlace(id: _uuid.v4(), name: name, position: position));
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _places.removeWhere((p) => p.id == id);
    await _save();
    notifyListeners();
  }
}
```

- [ ] **Step 5: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/providers/favorites_provider_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/models/favorite_place.dart lib/providers/favorites_provider.dart test/providers/favorites_provider_test.dart
git commit -m "feat: favoris - modele et provider persistant"
```

---

## Task 7: Voix du guidage — `GuidanceVoiceService`

**Files:**
- Create: `lib/services/guidance_voice_service.dart`
- Test: `test/services/guidance_voice_service_test.dart`

**Interfaces:**
- Consumes: `flutter_tts` (Task 1).
- Produces: `abstract class TtsEngine`, `class FlutterTtsEngine`, `class GuidanceVoiceService {isMuted, setMuted(bool), announce(String)}` — consommés par la tâche 10.

- [ ] **Step 1: Écrire les tests**

```dart
// test/services/guidance_voice_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/guidance_voice_service.dart';

class _FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  bool stopped = false;
  String? language;

  @override
  Future<void> setLanguage(String lang) async => language = lang;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  test('configure le français au démarrage', () {
    final engine = _FakeTtsEngine();
    GuidanceVoiceService(engine: engine);
    expect(engine.language, 'fr-FR');
  });

  test('announce parle quand le service n\'est pas muet', () async {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    await voice.announce('Tournez à gauche');
    expect(engine.spoken, ['Tournez à gauche']);
  });

  test('announce ne parle pas quand le service est muet', () async {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    voice.setMuted(true);
    await voice.announce('Tournez à gauche');
    expect(engine.spoken, isEmpty);
  });

  test('couper le son arrête une annonce en cours', () {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    voice.setMuted(true);
    expect(engine.stopped, isTrue);
  });

  test('isMuted reflète le dernier setMuted', () {
    final engine = _FakeTtsEngine();
    final voice = GuidanceVoiceService(engine: engine);
    expect(voice.isMuted, isFalse);
    voice.setMuted(true);
    expect(voice.isMuted, isTrue);
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/services/guidance_voice_service_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/services/guidance_voice_service.dart
import 'package:flutter_tts/flutter_tts.dart';

// Abstraction fine autour de flutter_tts, pour rester testable sans le
// canal de méthode de la plateforme.
abstract class TtsEngine {
  Future<void> setLanguage(String lang);
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> setLanguage(String lang) => _tts.setLanguage(lang);

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

class GuidanceVoiceService {
  GuidanceVoiceService({TtsEngine? engine}) : _engine = engine ?? FlutterTtsEngine() {
    _engine.setLanguage('fr-FR');
  }

  final TtsEngine _engine;
  bool _muted = false;
  bool get isMuted => _muted;

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) _engine.stop();
  }

  Future<void> announce(String text) async {
    if (_muted) return;
    await _engine.speak(text);
  }
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/services/guidance_voice_service_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/guidance_voice_service.dart test/services/guidance_voice_service_test.dart
git commit -m "feat: GuidanceVoiceService - annonces vocales FR mutables"
```

---

## Task 8: Service d'arrière-plan partagé

**Files:**
- Create: `lib/services/background_service_coordinator.dart`
- Create: `lib/services/guidance_background_client.dart`
- Modify: `lib/services/ride_recording_service.dart`
- Test: `test/services/background_service_coordinator_test.dart`

**Interfaces:**
- Consumes: `flutter_foreground_task` (déjà une dépendance).
- Produces: `abstract class ForegroundServiceControl`, `class BackgroundServiceCoordinator {instance, requestActive(id, text), release(id)}`, `class GuidanceBackgroundClient {start(text), update(text), stop()}` — consommés par la tâche 10. `RideRecordingService` garde exactement la même API publique (`start`, `stop`, `updateNotification`, `requestPermissions`, `isRunning`).

- [ ] **Step 1: Écrire les tests**

```dart
// test/services/background_service_coordinator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/background_service_coordinator.dart';

class _FakeControl implements ForegroundServiceControl {
  bool running = false;
  String? lastTitle;
  String? lastText;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<bool> start({required String title, required String text}) async {
    startCalls++;
    running = true;
    lastTitle = title;
    lastText = text;
    return true;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    lastTitle = title;
    lastText = text;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }
}

void main() {
  test('démarre le service au premier client actif', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');

    expect(control.startCalls, 1);
    expect(control.lastText, 'Enregistrement en cours');
  });

  test('compose le texte de notification pour deux clients actifs', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');
    await coordinator.requestActive('guidance', 'Guidage actif');

    expect(control.lastText, contains('Enregistrement en cours'));
    expect(control.lastText, contains('Guidage actif'));
    expect(control.startCalls, 1); // pas redémarré, juste mis à jour
  });

  test('arrête le service seulement quand le dernier client se retire', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');
    await coordinator.requestActive('guidance', 'Guidage actif');
    await coordinator.release('recording');

    expect(control.stopCalls, 0);
    expect(control.lastText, 'Guidage actif');

    await coordinator.release('guidance');
    expect(control.stopCalls, 1);
  });

  test('release d\'un client absent ne fait rien', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);
    await coordinator.release('guidance');
    expect(control.stopCalls, 0);
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/services/background_service_coordinator_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter le coordinateur**

```dart
// lib/services/background_service_coordinator.dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Abstraction du service de premier plan Android, pour rendre le
// coordinateur testable sans le canal de méthode de flutter_foreground_task.
abstract class ForegroundServiceControl {
  Future<bool> isRunning();
  Future<bool> start({required String title, required String text});
  Future<void> update({required String title, required String text});
  Future<void> stop();
}

class FlutterForegroundServiceControl implements ForegroundServiceControl {
  static const _channelId = 'moto_offroad_background';
  bool _initialized = false;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          _channelId,
        channelName:        'Activité en arrière-plan',
        channelDescription:
            "Maintient l'enregistrement et/ou le guidage actifs écran éteint.",
        channelImportance: NotificationChannelImportance.LOW,
        priority:          NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction:   ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<bool> start({required String title, required String text}) async {
    _init();
    if (await isRunning()) return true;
    final result =
        await FlutterForegroundTask.startService(notificationTitle: title, notificationText: text);
    return result is ServiceRequestSuccess;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    if (!await isRunning()) return;
    await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
  }

  @override
  Future<void> stop() async {
    if (await isRunning()) await FlutterForegroundTask.stopService();
  }
}

// Un client nommé du service partagé (ex: "recording", "guidance") —
// démarre le service au premier enregistrement, l'arrête au dernier
// retrait, compose le texte de notification à partir des clients actifs.
class BackgroundServiceCoordinator {
  BackgroundServiceCoordinator({ForegroundServiceControl? control})
      : _control = control ?? FlutterForegroundServiceControl();

  static final BackgroundServiceCoordinator instance = BackgroundServiceCoordinator();

  final ForegroundServiceControl _control;
  final Map<String, String> _activeClients = {};

  Future<void> requestActive(String clientId, String text) async {
    _activeClients[clientId] = text;
    await _sync();
  }

  Future<void> release(String clientId) async {
    if (!_activeClients.containsKey(clientId)) return;
    _activeClients.remove(clientId);
    await _sync();
  }

  Future<void> _sync() async {
    if (_activeClients.isEmpty) {
      await _control.stop();
      return;
    }
    final text = _activeClients.values.join(' · ');
    if (await _control.isRunning()) {
      await _control.update(title: 'Moto Offroad', text: text);
    } else {
      await _control.start(title: 'Moto Offroad', text: text);
    }
  }
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/services/background_service_coordinator_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Créer le client de guidage**

```dart
// lib/services/guidance_background_client.dart
import 'background_service_coordinator.dart';

class GuidanceBackgroundClient {
  GuidanceBackgroundClient({BackgroundServiceCoordinator? coordinator})
      : _coordinator = coordinator ?? BackgroundServiceCoordinator.instance;

  static const _clientId = 'guidance';
  final BackgroundServiceCoordinator _coordinator;

  Future<void> start(String text) => _coordinator.requestActive(_clientId, text);
  Future<void> update(String text) => _coordinator.requestActive(_clientId, text);
  Future<void> stop() => _coordinator.release(_clientId);
}
```

- [ ] **Step 6: Faire passer `RideRecordingService` par le coordinateur**

Remplacer le contenu de `lib/services/ride_recording_service.dart` (garder `requestPermissions` inchangé) :

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'background_service_coordinator.dart';

// ── Client "enregistrement" du service d'arrière-plan partagé ────────────
// L'API publique (start/stop/updateNotification/requestPermissions/
// isRunning) ne change pas : seul le fonctionnement interne passe par le
// coordinateur, partagé avec le guidage (voir background_service_coordinator.dart).
class RideRecordingService {
  static final RideRecordingService _instance = RideRecordingService._();
  factory RideRecordingService() => _instance;
  RideRecordingService._();

  static const String _clientId = 'recording';
  final BackgroundServiceCoordinator _coordinator = BackgroundServiceCoordinator.instance;

  // ── Permissions : notification puis optimisation batterie ─
  Future<bool> requestPermissions() async {
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      final asked = await FlutterForegroundTask.requestNotificationPermission();
      if (asked != NotificationPermission.granted) return false;
    }

    // Sans cette exemption, Xiaomi, Huawei, Oppo et certains Samsung tuent le
    // service malgré la notification. Refus non bloquant : on enregistre
    // quand même, en acceptant le risque.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<bool> start({required String title, required String text}) async {
    await _coordinator.requestActive(_clientId, text);
    return true;
  }

  Future<void> updateNotification({required String title, required String text}) async {
    await _coordinator.requestActive(_clientId, text);
  }

  Future<void> stop() async {
    await _coordinator.release(_clientId);
  }
}
```

- [ ] **Step 7: Vérifier qu'aucune régression n'apparaît sur l'existant**

Run: `flutter test test/providers/recording_provider_test.dart`
Expected: PASS — `RecordingProvider` n'appelle `RideRecordingService` que si on lui en injecte un (`_service?.start(...)`), les tests existants n'en injectent pas et ne sont donc pas affectés par ce refactor.

Run: `flutter analyze`
Expected: aucune nouvelle erreur.

- [ ] **Step 8: Commit**

```bash
git add lib/services/background_service_coordinator.dart lib/services/guidance_background_client.dart lib/services/ride_recording_service.dart test/services/background_service_coordinator_test.dart
git commit -m "refactor: service d'arriere-plan partage entre enregistrement et guidage"
```

---

## Task 9: Réglages du guidage dans `SettingsProvider`

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Modify: `test/providers/settings_provider_test.dart`

**Interfaces:**
- Produces: `SettingsProvider.guidanceAvoidHighways/Tolls/Ferries` (`bool`), `.guidanceVoiceMuted` (`bool`), et les setters correspondants — consommés par les tâches 10, 16.

- [ ] **Step 1: Ajouter les tests**

Ajouter à `test/providers/settings_provider_test.dart` (dans `void main()`) :

```dart
  test('les réglages de guidage par défaut sont désactivés', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    expect(s.guidanceAvoidHighways, isFalse);
    expect(s.guidanceAvoidTolls, isFalse);
    expect(s.guidanceAvoidFerries, isFalse);
    expect(s.guidanceVoiceMuted, isFalse);
  });

  test('les réglages de guidage survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await s.load();
    await s.setGuidanceAvoidHighways(true);
    await s.setGuidanceAvoidTolls(true);
    await s.setGuidanceAvoidFerries(true);
    await s.setGuidanceVoiceMuted(true);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.guidanceAvoidHighways, isTrue);
    expect(reloaded.guidanceAvoidTolls, isTrue);
    expect(reloaded.guidanceAvoidFerries, isTrue);
    expect(reloaded.guidanceVoiceMuted, isTrue);
  });
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: FAIL — méthodes/getters inexistants.

- [ ] **Step 3: Ajouter les clés, champs et getters**

Dans `lib/providers/settings_provider.dart`, avec les autres clés :

```dart
  static const _kGuidanceAvoidHighways = 'guidance_avoid_highways';
  static const _kGuidanceAvoidTolls    = 'guidance_avoid_tolls';
  static const _kGuidanceAvoidFerries  = 'guidance_avoid_ferries';
  static const _kGuidanceVoiceMuted    = 'guidance_voice_muted';
```

Avec les autres champs :

```dart
  bool _guidanceAvoidHighways = false;
  bool _guidanceAvoidTolls    = false;
  bool _guidanceAvoidFerries  = false;
  bool _guidanceVoiceMuted    = false;
```

Avec les autres getters :

```dart
  bool get guidanceAvoidHighways => _guidanceAvoidHighways;
  bool get guidanceAvoidTolls    => _guidanceAvoidTolls;
  bool get guidanceAvoidFerries  => _guidanceAvoidFerries;
  bool get guidanceVoiceMuted    => _guidanceVoiceMuted;
```

- [ ] **Step 4: Charger dans `load()` et ajouter les setters**

Dans `load()`, avec les autres lectures :

```dart
    _guidanceAvoidHighways = prefs.getBool(_kGuidanceAvoidHighways) ?? false;
    _guidanceAvoidTolls    = prefs.getBool(_kGuidanceAvoidTolls)    ?? false;
    _guidanceAvoidFerries  = prefs.getBool(_kGuidanceAvoidFerries)  ?? false;
    _guidanceVoiceMuted    = prefs.getBool(_kGuidanceVoiceMuted)    ?? false;
```

Avec les autres setters (même pattern que `setAutoPauseEnabled`) :

```dart
  Future<void> setGuidanceAvoidHighways(bool v) async {
    _guidanceAvoidHighways = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidHighways, v);
    notifyListeners();
  }

  Future<void> setGuidanceAvoidTolls(bool v) async {
    _guidanceAvoidTolls = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidTolls, v);
    notifyListeners();
  }

  Future<void> setGuidanceAvoidFerries(bool v) async {
    _guidanceAvoidFerries = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceAvoidFerries, v);
    notifyListeners();
  }

  Future<void> setGuidanceVoiceMuted(bool v) async {
    _guidanceVoiceMuted = v;
    (await SharedPreferences.getInstance()).setBool(_kGuidanceVoiceMuted, v);
    notifyListeners();
  }
```

- [ ] **Step 5: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: PASS (tous les tests existants + les 2 nouveaux)

- [ ] **Step 6: Commit**

```bash
git add lib/providers/settings_provider.dart test/providers/settings_provider_test.dart
git commit -m "feat: reglages persistes pour le guidage (evitements, voix)"
```

---

## Task 10: `GuidanceProvider` — le cœur du guidage

**Files:**
- Create: `lib/providers/guidance_provider.dart`
- Test: `test/providers/guidance_provider_test.dart`

**Interfaces:**
- Consumes: `RouteResult`/`RouteStep`/`ManeuverType` (Task 2), `distanceToPolyline`/`nearestPointOnPolyline` (Task 3), `GpxRouteDeriver` (Task 4), `RoutingService`/`RoutingProfile`/`AvoidFeature`/`RoutingException` (Task 5), `GuidanceVoiceService`/`TtsEngine` (Task 7), `GuidanceBackgroundClient`/`BackgroundServiceCoordinator` (Task 8), `TraceModel` (existant), `GpsSnapshot`/`LocationService` (existant, `lib/services/location_service.dart`).
- Produces: `enum GuidanceMode {destination, gpxAlert, gpxTurnByTurn}`, `GuidanceProvider` avec `isActive`, `mode`, `route`, `currentStep`, `isOffRoute`, `gpsSignalLost`, `isMuted`, `error`, `distanceToNextStepMeters`, `remainingDistanceMeters`, `startToDestination(...)`, `startOnTrace(trace, mode)`, `stop()`, `toggleMute()` — consommés par les tâches 11, 13, 14, 15, 17.

- [ ] **Step 1: Écrire les tests**

```dart
// test/providers/guidance_provider_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/services/background_service_coordinator.dart';
import 'package:moto_offroad/services/guidance_background_client.dart';
import 'package:moto_offroad/services/guidance_voice_service.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/routing_service.dart';

final _t0 = DateTime(2026, 9, 3, 10, 0, 0);

GpsSnapshot _gps(LatLng pos, {int s = 0}) => GpsSnapshot(
  position:       pos,
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       20,
  headingDeg:     0,
  timestamp:      _t0.add(Duration(seconds: s)),
);

class _FakeRoutingService extends RoutingService {
  int calls = 0;
  RouteResult Function()? nextResult;
  bool shouldThrow = false;

  @override
  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    calls++;
    if (shouldThrow) throw const RoutingException('pas de réseau');
    return nextResult!();
  }
}

class _FakeControl implements ForegroundServiceControl {
  @override
  Future<bool> isRunning() async => true;
  @override
  Future<bool> start({required String title, required String text}) async => true;
  @override
  Future<void> update({required String title, required String text}) async {}
  @override
  Future<void> stop() async {}
}

class _FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  @override
  Future<void> setLanguage(String lang) async {}
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

RouteResult _straightRoute() => RouteResult(
  polyline: [const LatLng(44.0, 6.0), const LatLng(44.0, 6.01)],
  steps: [
    const RouteStep(
      instruction: 'Tournez à droite',
      distanceMeters: 500,
      maneuver: ManeuverType.turnRight,
      location: LatLng(44.0, 6.005),
    ),
    const RouteStep(
      instruction: 'Destination atteinte',
      distanceMeters: 500,
      maneuver: ManeuverType.arrive,
      location: LatLng(44.0, 6.01),
    ),
  ],
  totalDistanceMeters: 1000,
  totalDurationSeconds: 120,
);

TraceModel _traceFrom(List<LatLng> points) => TraceModel(
  id: 't1', name: 'test',
  points: points.map((p) => TracePoint(position: p)).toList(),
);

void main() {
  late StreamController<GpsSnapshot> positionController;
  late _FakeRoutingService routing;
  late _FakeTtsEngine ttsEngine;
  late GuidanceProvider guidance;

  setUp(() {
    positionController = StreamController<GpsSnapshot>.broadcast();
    routing = _FakeRoutingService();
    ttsEngine = _FakeTtsEngine();
    guidance = GuidanceProvider(
      routingService: routing,
      voiceService: GuidanceVoiceService(engine: ttsEngine),
      backgroundClient: GuidanceBackgroundClient(
        coordinator: BackgroundServiceCoordinator(control: _FakeControl()),
      ),
      positionStream: positionController.stream,
    );
  });

  tearDown(() => positionController.close());

  test('startToDestination active le guidage et récupère la route', () async {
    routing.nextResult = _straightRoute;
    final ok = await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    expect(ok, isTrue);
    expect(guidance.isActive, isTrue);
    expect(guidance.mode, GuidanceMode.destination);
    expect(guidance.currentStep?.instruction, 'Tournez à droite');
  });

  test('échec réseau au démarrage n\'active pas le guidage et remplit error', () async {
    routing.shouldThrow = true;
    final ok = await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    expect(ok, isFalse);
    expect(guidance.isActive, isFalse);
    expect(guidance.error, isNotNull);
  });

  test('approcher du point de manœuvre avance à l\'étape suivante et annonce', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.currentStep?.maneuver, ManeuverType.arrive);
    expect(ttsEngine.spoken, contains('Tournez à droite'));
  });

  test('atteindre la dernière étape arrête le guidage', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(const LatLng(44.0, 6.01)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isActive, isFalse);
  });

  test('un seul relevé hors trace ne déclenche pas de déviation (filtre le bruit)', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.002, 6.0))); // ~220m à côté
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isOffRoute, isFalse);
    expect(routing.calls, 1); // uniquement l'appel initial
  });

  test('une déviation soutenue en mode destination redemande un itinéraire', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.002, 6.0), s: 1));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(const LatLng(44.002, 6.0), s: 2));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isOffRoute, isTrue);
    expect(routing.calls, 2); // appel initial + recalcul
  });

  test('startOnTrace en mode alerte ne fait aucun appel réseau', () {
    final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
    guidance.startOnTrace(trace, GuidanceMode.gpxAlert);

    expect(guidance.isActive, isTrue);
    expect(guidance.mode, GuidanceMode.gpxAlert);
    expect(routing.calls, 0);
  });

  test('mute empêche les annonces vocales', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    guidance.toggleMute();

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);

    expect(ttsEngine.spoken, isEmpty);
  });

  test('stop désactive le guidage', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    guidance.stop();
    expect(guidance.isActive, isFalse);
    expect(guidance.route, isNull);
  });
}
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

Run: `flutter test test/providers/guidance_provider_test.dart`
Expected: FAIL — fichier `guidance_provider.dart` introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/providers/guidance_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/trace.dart';
import '../services/gpx_route_deriver.dart';
import '../services/guidance_background_client.dart';
import '../services/guidance_voice_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../utils/route_geometry.dart';

enum GuidanceMode { destination, gpxAlert, gpxTurnByTurn }

class GuidanceProvider extends ChangeNotifier {
  GuidanceProvider({
    RoutingService? routingService,
    GuidanceVoiceService? voiceService,
    GuidanceBackgroundClient? backgroundClient,
    Stream<GpsSnapshot>? positionStream,
  })  : _routing = routingService ?? RoutingService(),
        _voice = voiceService ?? GuidanceVoiceService(),
        _background = backgroundClient ?? GuidanceBackgroundClient(),
        _positionStream = positionStream ?? LocationService().stream;

  // Rayon (m) d'arrivée sur une manœuvre — au-delà, l'étape suivante démarre.
  static const double _stepArrivalRadiusMeters = 30;
  // Distances (m) de pré-annonce vocale avant une manœuvre.
  static const List<double> _announceThresholds = [300, 100];
  // Écarts (m) à la trace au-delà desquels on considère une déviation.
  static const double _offRouteThresholdRoute = 40;
  static const double _offRouteThresholdOffroad = 60;
  // Relevés consécutifs hors trace requis avant d'agir — filtre le bruit GPS.
  static const int _offRouteStreakThreshold = 2;
  // Fréquence minimale entre deux recalculs après déviation.
  static const Duration _rerouteCooldown = Duration(seconds: 20);
  // Silence GPS au-delà duquel le guidage se signale en perte de signal.
  static const Duration _gpsTimeout = Duration(seconds: 15);

  final RoutingService _routing;
  final GuidanceVoiceService _voice;
  final GuidanceBackgroundClient _background;
  final Stream<GpsSnapshot> _positionStream;

  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _gpsTimeoutTimer;

  GuidanceMode? _mode;
  RouteResult? _route;
  int _currentStepIndex = 0;
  LatLng? _lastPosition;
  bool _isOffRoute = false;
  int _offRouteStreak = 0;
  DateTime? _lastRerouteAttempt;
  bool _gpsSignalLost = false;
  String? _error;
  final Set<double> _announcedThresholds = {};

  // Contexte conservé pour un recalcul silencieux en mode destination.
  LatLng? _destination;
  RoutingProfile? _profile;
  Set<AvoidFeature> _avoid = const {};

  GuidanceMode? get mode => _mode;
  bool get isActive => _mode != null;
  RouteResult? get route => _route;
  bool get isOffRoute => _isOffRoute;
  bool get gpsSignalLost => _gpsSignalLost;
  bool get isMuted => _voice.isMuted;
  String? get error => _error;

  RouteStep? get currentStep {
    final r = _route;
    if (r == null || _currentStepIndex >= r.steps.length) return null;
    return r.steps[_currentStepIndex];
  }

  double get distanceToNextStepMeters {
    final step = currentStep;
    final pos = _lastPosition;
    if (step == null || pos == null) return 0;
    return const Distance()(pos, step.location);
  }

  double get remainingDistanceMeters {
    final r = _route;
    final pos = _lastPosition;
    if (r == null || pos == null || r.polyline.isEmpty) return 0;
    final nearest = nearestPointOnPolyline(pos, r.polyline);
    const calc = Distance();
    double total = 0;
    for (var i = nearest.segmentIndex + 1; i < r.polyline.length; i++) {
      total += calc(r.polyline[i - 1], r.polyline[i]);
    }
    return total;
  }

  // ── Démarrage : destination calculée ─────────────────────
  Future<bool> startToDestination({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    _error = null;
    try {
      final result = await _routing.fetchRoute(
          origin: origin, destination: destination, profile: profile, avoid: avoid);
      _route = result;
      _mode = GuidanceMode.destination;
      _destination = destination;
      _profile = profile;
      _avoid = avoid;
      _resetProgress();
      _startListening();
      await _background.start('Guidage actif');
      notifyListeners();
      return true;
    } on RoutingException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Démarrage : trace GPX déjà chargée ───────────────────
  void startOnTrace(TraceModel trace, GuidanceMode mode) {
    assert(mode == GuidanceMode.gpxAlert || mode == GuidanceMode.gpxTurnByTurn);
    _error = null;
    _route = mode == GuidanceMode.gpxTurnByTurn
        ? GpxRouteDeriver.deriveTurnByTurn(trace)
        : GpxRouteDeriver.deriveForAlert(trace);
    _mode = mode;
    _destination = null;
    _profile = null;
    _avoid = const {};
    _resetProgress();
    _startListening();
    _background.start('Guidage actif');
    notifyListeners();
  }

  void _resetProgress() {
    _currentStepIndex = 0;
    _isOffRoute = false;
    _offRouteStreak = 0;
    _announcedThresholds.clear();
  }

  void stop() {
    _mode = null;
    _route = null;
    _lastPosition = null;
    _positionSub?.cancel();
    _positionSub = null;
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;
    _gpsSignalLost = false;
    _background.stop();
    notifyListeners();
  }

  void toggleMute() {
    _voice.setMuted(!_voice.isMuted);
    notifyListeners();
  }

  void _startListening() {
    _positionSub?.cancel();
    _positionSub = _positionStream.listen(_onPosition);
    _resetGpsTimeout();
  }

  void _resetGpsTimeout() {
    _gpsTimeoutTimer?.cancel();
    _gpsSignalLost = false;
    _gpsTimeoutTimer = Timer(_gpsTimeout, () {
      _gpsSignalLost = true;
      notifyListeners();
    });
  }

  void _onPosition(GpsSnapshot snap) {
    if (!isActive || _route == null) return;
    _lastPosition = snap.position;
    _resetGpsTimeout();

    _checkStepAdvance(snap.position);
    _checkOffRoute(snap.position);
    notifyListeners();
  }

  void _checkStepAdvance(LatLng position) {
    final step = currentStep;
    if (step == null) return;
    const calc = Distance();
    final d = calc(position, step.location);

    for (final threshold in _announceThresholds) {
      if (d <= threshold && !_announcedThresholds.contains(threshold)) {
        _announcedThresholds.add(threshold);
        _voice.announce('Dans ${threshold.round()} mètres, ${step.instruction}');
      }
    }

    if (d <= _stepArrivalRadiusMeters) {
      _voice.announce(step.instruction);
      _announcedThresholds.clear();
      if (_currentStepIndex >= _route!.steps.length - 1) {
        stop();
      } else {
        _currentStepIndex++;
      }
    }
  }

  void _checkOffRoute(LatLng position) {
    final route = _route;
    if (route == null || route.polyline.isEmpty) return;

    final threshold =
        _mode == GuidanceMode.destination && _profile == RoutingProfile.drivingCar
            ? _offRouteThresholdRoute
            : _offRouteThresholdOffroad;

    final distance = distanceToPolyline(position, route.polyline);
    final offNow = distance > threshold;

    _offRouteStreak = offNow ? _offRouteStreak + 1 : 0;
    final wasOffRoute = _isOffRoute;
    _isOffRoute = _offRouteStreak >= _offRouteStreakThreshold;

    if (!_isOffRoute || wasOffRoute == _isOffRoute) return;

    if (_mode == GuidanceMode.destination) {
      _maybeReroute(position);
    } else if (_mode == GuidanceMode.gpxAlert) {
      _voice.announce('Vous vous éloignez de la trace');
    }
  }

  Future<void> _maybeReroute(LatLng position) async {
    final now = DateTime.now();
    if (_lastRerouteAttempt != null && now.difference(_lastRerouteAttempt!) < _rerouteCooldown) {
      return;
    }
    _lastRerouteAttempt = now;
    final destination = _destination;
    final profile = _profile;
    if (destination == null || profile == null) return;

    try {
      final result = await _routing.fetchRoute(
          origin: position, destination: destination, profile: profile, avoid: _avoid);
      _route = result;
      _resetProgress();
      notifyListeners();
    } on RoutingException {
      // Réseau indisponible : on garde le dernier itinéraire connu, la
      // prochaine déviation retentera après le délai de garde.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _gpsTimeoutTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

Run: `flutter test test/providers/guidance_provider_test.dart`
Expected: PASS (10 tests)

- [ ] **Step 5: Lancer toute la suite pour vérifier l'absence de régression**

Run: `flutter test`
Expected: PASS — tous les tests existants + les nouveaux.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/guidance_provider.dart test/providers/guidance_provider_test.dart
git commit -m "feat: GuidanceProvider - etat du guidage, deviation, recalcul, annonces"
```

---

## Task 11: Bandeau d'instruction — `GuidanceBanner`

**Files:**
- Create: `lib/widgets/guidance_banner.dart`
- Test: `test/widgets/guidance_banner_test.dart`

**Interfaces:**
- Consumes: `GuidanceProvider` (Task 10), `ManeuverType`/`RouteStep` (Task 2), `AppColors` (`lib/app/theme.dart`, existant).
- Produces: `class GuidanceBanner extends StatelessWidget` — consommé par la tâche 17.

- [ ] **Step 1: Écrire le test**

```dart
// test/widgets/guidance_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/widgets/guidance_banner.dart';

TraceModel _straightTrace() => TraceModel(
  id: 't1', name: 'test',
  points: [
    TracePoint(position: const LatLng(44.0, 6.0)),
    TracePoint(position: const LatLng(44.01, 6.0)),
  ],
);

Future<void> _pump(WidgetTester tester, GuidanceProvider guidance) {
  return tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: guidance,
      child: const MaterialApp(home: Scaffold(body: GuidanceBanner())),
    ),
  );
}

void main() {
  testWidgets('n\'affiche rien quand le guidage est inactif', (tester) async {
    final guidance = GuidanceProvider(positionStream: const Stream.empty());
    await _pump(tester, guidance);
    expect(find.byType(GuidanceBanner), findsOneWidget);
    expect(find.text('Suivi de la trace'), findsNothing);
  });

  testWidgets('affiche l\'instruction en mode alerte GPX', (tester) async {
    final guidance = GuidanceProvider(positionStream: const Stream.empty());
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);
    expect(find.text('Suivi de la trace'), findsOneWidget);
  });

  testWidgets('le bouton mute appelle toggleMute', (tester) async {
    final guidance = GuidanceProvider(positionStream: const Stream.empty());
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);

    expect(guidance.isMuted, isFalse);
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();
    expect(guidance.isMuted, isTrue);
  });

  testWidgets('le bouton fermer appelle stop', (tester) async {
    final guidance = GuidanceProvider(positionStream: const Stream.empty());
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(guidance.isActive, isFalse);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `flutter test test/widgets/guidance_banner_test.dart`
Expected: FAIL — fichier `guidance_banner.dart` introuvable.

- [ ] **Step 3: Implémenter**

```dart
// lib/widgets/guidance_banner.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/route_result.dart';
import '../providers/guidance_provider.dart';

class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceProvider>();
    if (!guidance.isActive) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _instructionCard(guidance),
        const SizedBox(height: 6),
        _footer(guidance),
      ],
    );
  }

  Widget _instructionCard(GuidanceProvider guidance) {
    final step = guidance.currentStep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          Icon(_iconFor(step?.maneuver), color: AppColors.orange, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step?.instruction ?? 'Suivi de la trace',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (step != null)
                  Text(
                    '${guidance.distanceToNextStepMeters.round()} m',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (guidance.gpsSignalLost)
            const Icon(Icons.gps_off, color: AppColors.statusRed, size: 20)
          else if (guidance.isOffRoute)
            const Icon(Icons.warning_amber, color: AppColors.statusOrange, size: 20),
        ],
      ),
    );
  }

  Widget _footer(GuidanceProvider guidance) {
    final remainingKm = (guidance.remainingDistanceMeters / 1000).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          Text('$remainingKm km restants', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: Icon(guidance.isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
            onPressed: guidance.toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.statusRed, size: 20),
            onPressed: guidance.stop,
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ManeuverType? m) {
    switch (m) {
      case ManeuverType.turnLeft:   return Icons.turn_left;
      case ManeuverType.turnRight:  return Icons.turn_right;
      case ManeuverType.sharpLeft:  return Icons.turn_sharp_left;
      case ManeuverType.sharpRight: return Icons.turn_sharp_right;
      case ManeuverType.uturn:      return Icons.u_turn_left;
      case ManeuverType.arrive:     return Icons.flag;
      case ManeuverType.depart:     return Icons.navigation;
      case ManeuverType.straight:
      case null:                    return Icons.straight;
    }
  }
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `flutter test test/widgets/guidance_banner_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/guidance_banner.dart test/widgets/guidance_banner_test.dart
git commit -m "feat: bandeau d'instruction du guidage (GuidanceBanner)"
```

---

## Task 12: Écran Favoris

**Files:**
- Create: `lib/screens/favorites/favorites_screen.dart`
- Modify: `lib/app/router.dart`
- Test: `test/screens/favorites_screen_test.dart`

**Interfaces:**
- Consumes: `FavoritesProvider` (Task 6).
- Produces: `class FavoritesScreen extends StatelessWidget` (pop `FavoritePlace` sélectionné), `AppRoutes.favorites` — consommés par la tâche 17.

- [ ] **Step 1: Écrire le test**

```dart
// test/screens/favorites_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/favorites_provider.dart';
import 'package:moto_offroad/screens/favorites/favorites_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('affiche un message quand aucun favori', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final favorites = FavoritesProvider();
    await favorites.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: favorites,
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );

    expect(find.textContaining('Aucun favori'), findsOneWidget);
  });

  testWidgets('affiche la liste et supprime un favori', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final favorites = FavoritesProvider();
    await favorites.load();
    await favorites.add('Garage', const LatLng(44.0, 6.0));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: favorites,
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );

    expect(find.text('Garage'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Garage'), findsNothing);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `flutter test test/screens/favorites_screen_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter l'écran**

```dart
// lib/screens/favorites/favorites_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../models/favorite_place.dart';
import '../../providers/favorites_provider.dart';

// Retourne le favori choisi via Navigator.pop, pour que l'appelant démarre
// le guidage dessus — voir map_screen.dart.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('FAVORIS')),
      body: favorites.places.isEmpty
          ? const Center(
              child: Text(
                'Aucun favori — ajoute un point depuis la carte',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: favorites.places.length,
              itemBuilder: (_, i) {
                final p = favorites.places[i];
                return ListTile(
                  leading: const Icon(Icons.star, color: AppColors.orange),
                  title: Text(p.name, style: const TextStyle(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.statusRed),
                    onPressed: () => favorites.remove(p.id),
                  ),
                  onTap: () => Navigator.of(context).pop<FavoritePlace>(p),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: Ajouter la route**

Dans `lib/app/router.dart`, ajouter l'import et la constante :

```dart
import '../screens/favorites/favorites_screen.dart';
```

```dart
  static const String favorites = '/favorites';
```

Et un `GoRoute` dans la liste des modales (hors shell), à côté de `AppRoutes.solo` :

```dart
    GoRoute(
      path: AppRoutes.favorites,
      pageBuilder: (_, __) =>
          const MaterialPage(fullscreenDialog: true, child: FavoritesScreen()),
    ),
```

- [ ] **Step 5: Lancer le test, vérifier qu'il passe**

Run: `flutter test test/screens/favorites_screen_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/screens/favorites/favorites_screen.dart lib/app/router.dart test/screens/favorites_screen_test.dart
git commit -m "feat: ecran Favoris"
```

---

## Task 13: Appui long sur la carte — Guider ici / Ajouter aux favoris

**Files:**
- Modify: `lib/screens/map/map_screen.dart`

**Interfaces:**
- Consumes: `GuidanceProvider.startToDestination` (Task 10), `FavoritesProvider.add` (Task 6), `MapProvider.navMode`/`NavMode` (existant), `SettingsProvider.guidanceAvoid*` (Task 9), `LocationService().lastSnapshot` (existant).

- [ ] **Step 1: Ajouter `onLongPress` aux `MapOptions`**

Dans `lib/screens/map/map_screen.dart`, modifier le bloc `MapOptions` (autour de la ligne 230) :

```dart
      options: MapOptions(
        initialCenter: mapProv.center,
        initialZoom: mapProv.zoom,
        minZoom: 5,
        maxZoom: 18,
        onMapReady: () => setState(() => _mapReady = true),
        onTap: (_, __) {
          if (mapProv.isFullscreen) mapProv.exitFullscreen();
        },
        onLongPress: (_, point) => _showLongPressSheet(point),
        onMapEvent: (event) => _onMapEvent(event, mapProv, settings),
      ),
```

- [ ] **Step 2: Ajouter la feuille contextuelle et le déclenchement du guidage**

Ajouter ces méthodes dans `_MapScreenState`, à côté de `_openSearchSheet` :

```dart
  void _showLongPressSheet(LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions, color: AppColors.orange),
              title: const Text('Guider ici', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startGuidanceTo(point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_border, color: AppColors.orange),
              title: const Text('Ajouter aux favoris', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptAddFavorite(point);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startGuidanceTo(LatLng destination) async {
    final origin = _locationService.lastSnapshot?.position;
    if (origin == null) return;

    final mapProv = context.read<MapProvider>();
    final settings = context.read<SettingsProvider>();
    final profile = mapProv.isOffroad ? RoutingProfile.cyclingMountain : RoutingProfile.drivingCar;
    final avoid = <AvoidFeature>{
      if (settings.guidanceAvoidHighways) AvoidFeature.highways,
      if (settings.guidanceAvoidTolls) AvoidFeature.tollways,
      if (settings.guidanceAvoidFerries) AvoidFeature.ferries,
    };

    final ok = await context.read<GuidanceProvider>().startToDestination(
      origin: origin, destination: destination, profile: profile, avoid: avoid,
    );

    if (!ok && mounted) {
      final error = context.read<GuidanceProvider>().error ?? "Impossible de calculer l'itinéraire";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _promptAddFavorite(LatLng point) async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Nom du favori', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Ex: Garage'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameCtrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    await context.read<FavoritesProvider>().add(name, point);
  }
```

Ajouter les imports nécessaires en tête de fichier :

```dart
import '../../providers/favorites_provider.dart';
import '../../providers/guidance_provider.dart';
import '../../services/routing_service.dart';
```

- [ ] **Step 3: Vérifier l'analyse statique**

Run: `flutter analyze lib/screens/map/map_screen.dart`
Expected: aucune nouvelle erreur.

- [ ] **Step 4: Test manuel rapide**

Lancer l'app sur l'appareil de test, appui long sur la carte → la feuille « Guider ici / Ajouter aux favoris » apparaît. (Une passe complète, avec vraie clé ORS, est prévue en Task 18.)

- [ ] **Step 5: Commit**

```bash
git add lib/screens/map/map_screen.dart
git commit -m "feat: appui long sur la carte - guider ici / ajouter aux favoris"
```

---

## Task 14: Bouton Guider sur les résultats de recherche

**Files:**
- Modify: `lib/widgets/map_search_bar.dart`
- Modify: `lib/screens/map/map_screen.dart`

**Interfaces:**
- Consumes: `GuidanceProvider.startToDestination` (Task 10).
- Produces: `MapSearchBar.onGuide` (nouveau paramètre `ValueChanged<LatLng>?`).

- [ ] **Step 1: Ajouter le paramètre et le bouton dans `MapSearchBar`**

Dans `lib/widgets/map_search_bar.dart`, ajouter le champ et le paramètre de constructeur :

```dart
  // Appelé quand l'utilisateur choisit de se faire guider vers un résultat,
  // plutôt que de simplement centrer la carte dessus.
  final ValueChanged<LatLng>? onGuide;

  const MapSearchBar({
    super.key,
    required this.mapController,
    this.startVisible = false,
    this.onResultSelected,
    this.onGuide,
  });
```

Modifier `_resultsList()` pour ajouter un bouton Guider à côté de chaque résultat :

```dart
  Widget _resultsList() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color:        AppColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: ListView.separated(
        padding:       EdgeInsets.zero,
        shrinkWrap:    true,
        itemCount:     _results.length,
        separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A3E), height: 1),
        itemBuilder: (_, i) {
          final r = _results[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.place, color: AppColors.orange, size: 16),
            title: Text(
              r.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            trailing: widget.onGuide == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.directions, color: AppColors.orange, size: 18),
                    onPressed: () {
                      widget.onGuide!(r.position);
                      _toggle();
                      widget.onResultSelected?.call();
                    },
                  ),
            onTap: () => _goTo(r),
          );
        },
      ),
    );
  }
```

- [ ] **Step 2: Brancher `onGuide` dans `map_screen.dart`**

Dans `_openSearchSheet()`, passer le callback :

```dart
        child: MapSearchBar(
          mapController: _mapController,
          startVisible: true,
          onResultSelected: () => Navigator.of(context).pop(),
          onGuide: _startGuidanceTo,
        ),
```

(`_startGuidanceTo` a été ajouté à la Task 13.)

- [ ] **Step 3: Vérifier l'analyse statique**

Run: `flutter analyze lib/widgets/map_search_bar.dart lib/screens/map/map_screen.dart`
Expected: aucune nouvelle erreur.

- [ ] **Step 4: Test manuel rapide**

Rechercher une adresse, vérifier que l'icône « itinéraire » apparaît sur chaque résultat et déclenche le guidage.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/map_search_bar.dart lib/screens/map/map_screen.dart
git commit -m "feat: bouton Guider sur les resultats de recherche"
```

---

## Task 15: Démarrer le guidage sur une trace GPX

**Files:**
- Modify: `lib/screens/map/map_screen.dart`

**Interfaces:**
- Consumes: `GuidanceProvider.startOnTrace` (Task 10), `TraceProvider.hasTrace/activeTrace` (existant).

- [ ] **Step 1: Ajouter un bouton conditionnel et la feuille de choix**

Dans le `Column` des contrôles flottants (à côté de `RadialActionMenu`, autour de la ligne 445), ajouter :

```dart
        if (traceProv.hasTrace) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showGpxGuidanceChooser(traceProv.activeTrace!),
            child: const GlassPuck(icon: Icons.alt_route, color: AppColors.orange),
          ),
        ],
```

(`traceProv` est déjà disponible dans `build()` via `context.watch<TraceProvider>()` — vérifier l'import existant.)

Ajouter la méthode :

```dart
  void _showGpxGuidanceChooser(TraceModel trace) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Guidage sur la trace', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active, color: AppColors.orange),
              title: const Text('Alerte de déviation', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Suis la trace, prévient si tu t\'en éloignes.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<GuidanceProvider>().startOnTrace(trace, GuidanceMode.gpxAlert);
              },
            ),
            ListTile(
              leading: const Icon(Icons.turn_right, color: AppColors.orange),
              title: const Text('Guidage virage par virage', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Instructions dérivées de la trace.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<GuidanceProvider>().startOnTrace(trace, GuidanceMode.gpxTurnByTurn);
              },
            ),
          ],
        ),
      ),
    );
  }
```

`GuidanceMode` est déjà résolu par l'import de `guidance_provider.dart` ajouté en Task 13. `TraceModel` n'est pas encore importé dans ce fichier — ajouter en tête de fichier :

```dart
import '../../models/trace.dart';
```

- [ ] **Step 2: Vérifier l'analyse statique**

Run: `flutter analyze lib/screens/map/map_screen.dart`
Expected: aucune nouvelle erreur.

- [ ] **Step 3: Test manuel rapide**

Importer un GPX, vérifier que le bouton de guidage apparaît et ouvre le choix Alerte / Virage par virage, et que chaque mode démarre.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/map/map_screen.dart
git commit -m "feat: demarrer le guidage sur une trace GPX (alerte ou virage par virage)"
```

---

## Task 16: Réglages du guidage dans l'écran Réglages

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsProvider.guidanceAvoid*/guidanceVoiceMuted` et setters (Task 9).

- [ ] **Step 1: Ajouter la section**

Ajouter une méthode dans `_SettingsScreenState`, à côté de `_recordingSection` :

```dart
  Widget _guidanceSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('GUIDAGE GPS'),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Éviter les autoroutes'),
          subtitle: const Text('En mode Route.'),
          value: settings.guidanceAvoidHighways,
          onChanged: settings.setGuidanceAvoidHighways,
        ),
        SwitchListTile(
          title: const Text('Éviter les péages'),
          value: settings.guidanceAvoidTolls,
          onChanged: settings.setGuidanceAvoidTolls,
        ),
        SwitchListTile(
          title: const Text('Éviter les ferries'),
          value: settings.guidanceAvoidFerries,
          onChanged: settings.setGuidanceAvoidFerries,
        ),
        SwitchListTile(
          title: const Text('Couper la voix du guidage'),
          subtitle: const Text('Les instructions restent visibles à l\'écran.'),
          value: settings.guidanceVoiceMuted,
          onChanged: settings.setGuidanceVoiceMuted,
        ),
      ],
    );
  }
```

- [ ] **Step 2: L'appeler depuis `build()`**

Dans `build()`, ajouter après `_recordingSection` :

```dart
            GlassPanel(child: _recordingSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _guidanceSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _appSection()),
```

- [ ] **Step 3: Vérifier l'analyse statique**

Run: `flutter analyze lib/screens/settings/settings_screen.dart`
Expected: aucune nouvelle erreur.

- [ ] **Step 4: Test manuel rapide**

Ouvrir Réglages, vérifier que la section « GUIDAGE GPS » apparaît et que les switches persistent après redémarrage de l'app.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat: reglages du guidage dans l'ecran Reglages"
```

---

## Task 17: Câblage final — providers, bandeau, entrée Groupe désactivée

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/map/map_screen.dart`
- Modify: `lib/screens/group/group_screen.dart`

**Interfaces:**
- Consumes: tout ce qui précède.

- [ ] **Step 1: Enregistrer les nouveaux providers dans `main.dart`**

Dans le `MultiProvider` de `MotoOffroadApp.build()`, ajouter après le provider `QuickReplyProvider` :

```dart
        ChangeNotifierProvider(create: (_) {
          final f = FavoritesProvider();
          f.load();
          return f;
        }),
        ChangeNotifierProvider(create: (_) => GuidanceProvider()),
```

Ajouter les imports :

```dart
import 'providers/favorites_provider.dart';
import 'providers/guidance_provider.dart';
```

- [ ] **Step 2: Afficher le bandeau sur la carte**

`map_screen.dart` a deux mises en page (`_buildPortrait()` autour de la ligne 127, `_buildLandscape()` ligne 184), chacune avec son propre `Stack` — le bandeau doit apparaître dans les deux.

En portrait, `_buildHeader()` (ligne 361) retourne un `Container` unique contenant la `Row` titre/switch/boutons, posé via `Positioned(top: 0, left: 0, right: 0, child: _buildHeader())`. Plutôt que de deviner une hauteur en pixels pour positionner le bandeau séparément, faire de `_buildHeader()` une colonne qui porte le bandeau juste sous cette `Row` — la hauteur s'ajuste alors automatiquement au contenu. Modifier la fin de `_buildHeader()` :

```dart
      child: Row(
        children: [
          // Nom trace
          Expanded(
```

reste inchangée jusqu'à la fermeture de ce `Container` ; envelopper l'appel existant dans une nouvelle structure. Concrètement, remplacer la ligne de retour de la méthode :

```dart
  Widget _buildHeader() {
    final traceProv = context.watch<TraceProvider>();
    return Container(
```

par :

```dart
  Widget _buildHeader() {
    final traceProv = context.watch<TraceProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeaderBar(traceProv),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: GuidanceBanner(),
        ),
      ],
    );
  }

  Widget _buildHeaderBar(TraceProvider traceProv) {
    return Container(
```

et fermer `_buildHeaderBar` avec la même accolade finale que `_buildHeader()` avait déjà (le corps du `Container` — padding, dégradé, `Row` — ne change pas).

En paysage, dans le `Stack` du bloc `Expanded(flex: 65, ...)` de `_buildLandscape()`, remplacer :

```dart
            child: Stack(children: [
              Positioned.fill(child: _buildMap()),
              _buildSideControls(),
              _buildSoloBadge(),
```

par :

```dart
            child: Stack(children: [
              Positioned.fill(child: _buildMap()),
              const Positioned(top: 8, left: 8, right: 8, child: GuidanceBanner()),
              _buildSideControls(),
              _buildSoloBadge(),
```

Ajouter l'import en tête de fichier :

```dart
import '../../widgets/guidance_banner.dart';
```

Le `top: AppSizes.statsBarHeight` du placement portrait est une valeur de départ raisonnable — l'ajuster visuellement si le bandeau chevauche le header lors de la vérification manuelle (Task 18).

- [ ] **Step 3: Préparer l'entrée « Guider vers ce rider » dans le mode Groupe**

Dans `lib/screens/group/group_screen.dart`, la méthode `_memberTile(GroupMember m)` (ligne 262) affiche un `Row` se terminant par le point de statut en ligne/hors ligne. Remplacer ce `Row` :

```dart
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: color,
            child: Text(m.name.isNotEmpty ? m.name[0] : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(
                m.isSharing
                    ? (m.speedKmh != null ? '${m.speedKmh!.toStringAsFixed(0)} km/h' : 'En ligne')
                    : 'Position masquée',
                style: TextStyle(fontSize: 11,
                  color: m.isSharing ? AppColors.statusGreen : AppColors.textMuted)),
            ],
          )),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.isOnline ? AppColors.statusGreen : AppColors.textMuted,
            ),
          ),
        ],
      ),
```

par :

```dart
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: color,
            child: Text(m.name.isNotEmpty ? m.name[0] : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(
                m.isSharing
                    ? (m.speedKmh != null ? '${m.speedKmh!.toStringAsFixed(0)} km/h' : 'En ligne')
                    : 'Position masquée',
                style: TextStyle(fontSize: 11,
                  color: m.isSharing ? AppColors.statusGreen : AppColors.textMuted)),
            ],
          )),
          // Désactivé tant que le hub de positions Hetzner (lot A/D de la
          // spec suivi-sécurité) n'existe pas — la position d'un membre du
          // groupe n'est pas encore une vraie destination guidable.
          IconButton(
            icon: const Icon(Icons.directions, color: Colors.white24, size: 20),
            tooltip: 'Nécessite le hub de positions du groupe (à venir)',
            onPressed: null,
          ),
          const SizedBox(width: 4),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.isOnline ? AppColors.statusGreen : AppColors.textMuted,
            ),
          ),
        ],
      ),
```

- [ ] **Step 4: Vérifier l'ensemble**

Run: `flutter analyze`
Expected: aucune nouvelle erreur (seuls les warnings `withOpacity` préexistants).

Run: `flutter test`
Expected: PASS — toute la suite, sans régression.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/screens/map/map_screen.dart lib/screens/group/group_screen.dart
git commit -m "feat: cablage du guidage GPS (providers, bandeau, entree groupe preparee)"
```

---

## Task 18: Vérification manuelle sur appareil réel

**Files:** aucun — validation uniquement.

**Interfaces:** aucune nouvelle.

- [ ] **Step 1: Configurer une vraie clé ORS**

Remplacer `VOTRE_CLE_ORS_ICI` dans `lib/config/api_keys.dart` par une clé créée sur openrouteservice.org (gratuite).

- [ ] **Step 2: Build et install**

Run: `flutter build apk --debug`
Run: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: Parcourir la checklist fonctionnelle**

- [ ] Recherche d'adresse → bouton Guider → guidage démarre, instructions cohérentes
- [ ] Appui long sur la carte → « Guider ici » → guidage démarre
- [ ] Appui long → « Ajouter aux favoris » → apparaît dans l'écran Favoris → « Guider » démarre le guidage
- [ ] Basculer Offroad/Route change effectivement le tracé proposé (chemins vs route)
- [ ] Réglages → activer « Éviter les autoroutes » → un itinéraire recalculé les évite
- [ ] Importer un GPX → bouton de guidage → mode Alerte de déviation → s'écarter de la trace déclenche l'alerte
- [ ] Même GPX → mode Virage par virage → instructions annoncées à l'approche des virages
- [ ] Couper le son (bandeau et réglages) → plus d'annonce vocale, bandeau visuel toujours à jour
- [ ] Éteindre l'écran pendant un guidage actif → la voix continue, la notification affiche « Guidage actif »
- [ ] Démarrer un enregistrement de sortie en même temps que le guidage → une seule notification, texte combiné, pas de crash
- [ ] Couper le réseau (mode avion) avant de démarrer un guidage destination → bandeau d'erreur, pas de plantage
- [ ] Couper le réseau pendant un guidage destination actif, puis dévier → pas de plantage, l'ancien itinéraire reste suivi
- [ ] Mode Groupe → l'entrée « Guider vers ce rider » est visible mais désactivée, avec message explicatif
- [ ] Aucune régression sur l'enregistrement de sortie existant (démarrage, pause, arrêt, notification)

- [ ] **Step 4: Consigner le résultat**

Si tout est vert, informer l'utilisateur que la fonctionnalité est prête. Sinon, lister précisément les points en échec avant de considérer la fonctionnalité terminée.
