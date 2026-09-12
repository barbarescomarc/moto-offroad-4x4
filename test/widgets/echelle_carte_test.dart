import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/widgets/echelle_carte.dart';

void main() {
  Future<void> poserCarte(
    WidgetTester tester, {
    required double zoom,
    LatLng centre = const LatLng(0, 0),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: FlutterMap(
            options: MapOptions(initialCenter: centre, initialZoom: zoom),
            children: const [EchelleCarte()],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('annonce la longueur de la règle et l équivalent d un centimètre',
      (tester) async {
    // À l'équateur, au zoom 14, un pixel logique couvre ~9,55 m : la règle
    // s'arrête au palier 500 m, et le centimètre d'écran (~63 px) vaut ~600 m.
    await poserCarte(tester, zoom: 14);

    expect(find.text('500 m'), findsOneWidget);
    expect(find.text('1 cm ≈ 600 m'), findsOneWidget);
  });

  testWidgets('passe au kilomètre quand on dézoome', (tester) async {
    await poserCarte(tester, zoom: 9);

    expect(find.text('20 km'), findsOneWidget);
  });

  // Le terrain couvert par un pixel rétrécit à mesure qu'on monte en
  // latitude : à zoom égal, l'échelle des Pyrénées et celle du Nord ne sont
  // pas les mêmes, et le calcul doit le refléter.
  testWidgets('tient compte de la latitude', (tester) async {
    await poserCarte(tester, zoom: 14, centre: const LatLng(60, 0));

    expect(find.text('500 m'), findsNothing);
    expect(find.text('200 m'), findsOneWidget);
  });
}
