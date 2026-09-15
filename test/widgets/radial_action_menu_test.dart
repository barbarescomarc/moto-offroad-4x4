// test/widgets/radial_action_menu_test.dart
//
// Une pastille de menu déployé se vise gantée, à bout de pouce : elle doit
// être plus grosse que le centre, qui n'est que le point de départ du geste.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/app/theme.dart';
import 'package:moto_offroad/widgets/glass_control.dart';
import 'package:moto_offroad/widgets/radial_action_menu.dart';

Future<TestGesture> _deplier(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(RadialActionMenu)),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

Size _taillePastille(WidgetTester tester, IconData icone) => tester.getSize(
      find.ancestor(of: find.byIcon(icone), matching: find.byType(GlassPuck)).first,
    );

void main() {
  Widget menu({double segmentSize = 48}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: RadialActionMenu(
              centerIcon: Icons.my_location,
              centerColor: AppColors.accent,
              onCenterTap: () {},
              radius: 150,
              segmentSize: segmentSize,
              segments: [
                RadialMenuSegment(
                  icon: Icons.radar, color: AppColors.secondary,
                  angleDeg: 270, onSelect: () {},
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('la pastille dépliée est plus grosse que le centre', (tester) async {
    await tester.pumpWidget(menu());
    final gesture = await _deplier(tester);

    expect(_taillePastille(tester, Icons.radar), const Size(48, 48));
    expect(_taillePastille(tester, Icons.my_location), const Size(40, 40),
        reason: 'le centre garde sa taille : on part de lui, on ne le vise pas');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('la pastille reste centrée sur son angle quand elle grossit',
      (tester) async {
    // 270° = plein gauche : le segment doit se poser à un rayon exactement
    // à gauche du centre, quelle que soit sa taille. Sans recentrage, il
    // pendait en bas à droite de l'angle visé.
    await tester.pumpWidget(menu(segmentSize: 60));
    final gesture = await _deplier(tester);

    final centre = tester.getCenter(find.byIcon(Icons.my_location));
    final segment = tester.getCenter(find.byIcon(Icons.radar));
    expect(segment.dx, closeTo(centre.dx - 150, 0.5));
    expect(segment.dy, closeTo(centre.dy, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
