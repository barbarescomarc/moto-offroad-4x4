// test/widgets/rider_position_layer_test.dart
//
// Le marqueur du pilote doit se redessiner tout seul à chaque relevé GPS.
// Tant qu'il était peint depuis une valeur lue dans le build de MapScreen,
// il restait figé là où il était au dernier rafraîchissement de l'écran :
// la carte suivait le pilote (déplacement impératif du contrôleur) mais le
// point, lui, ne bougeait plus — sauf coup de pouce extérieur, comme un
// appui sur Recentrer (constaté en enregistrement de trace le 2026-09-15).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/widgets/rider_position_layer.dart';

GpsSnapshot _releve(double lat, double lng) => GpsSnapshot(
      position: LatLng(lat, lng),
      accuracyMeters: 5,
      altitudeMeters: 300,
      speedKmh: 40,
      headingDeg: 90,
      timestamp: DateTime(2026, 9, 15, 12),
    );

void main() {
  testWidgets('le marqueur suit les releves GPS sans reconstruction du parent',
      (tester) async {
    final positions = ValueNotifier<GpsSnapshot?>(_releve(43.600, 1.440));

    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(43.600, 1.440),
          initialZoom: 14,
        ),
        children: [RiderPositionLayer(positions: positions)],
      ),
    ));

    final avant = tester.getCenter(find.byKey(RiderPositionLayer.marqueurKey));

    // Un nouveau relevé arrive, et rien d'autre ne change dans l'arbre.
    positions.value = _releve(43.610, 1.440);
    await tester.pump();

    final apres = tester.getCenter(find.byKey(RiderPositionLayer.marqueurKey));
    expect(apres.dy, lessThan(avant.dy),  // plus au nord = plus haut à l'écran
        reason: 'le marqueur doit remonter vers le nord avec le nouveau relevé');
  });

  testWidgets('sans relevé GPS, aucun marqueur n est peint', (tester) async {
    final positions = ValueNotifier<GpsSnapshot?>(null);

    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(43.600, 1.440),
          initialZoom: 14,
        ),
        children: [RiderPositionLayer(positions: positions)],
      ),
    ));

    expect(find.byKey(RiderPositionLayer.marqueurKey), findsNothing);
  });
}
