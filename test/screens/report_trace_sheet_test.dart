import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/screens/rides/report_trace_sheet.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

// Double du client HTTP : capture l'appel de report() ou lève l'échec voulu,
// jamais de vraie requête réseau.
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice() : super(client: MockClient((_) async => http.Response('', 200)), readToken: () async => 'jeton');

  void Function(String id, String reason, String? detail)? onReport;
  Object? erreurReport;

  @override
  Future<void> report(String id, {required String reason, String? detail}) async {
    if (erreurReport != null) throw erreurReport!;
    onReport?.call(id, reason, detail);
  }
}

// Un bouton « Signaler » minimal, seul point d'entrée vers la feuille —
// exactement le rôle que joue le bouton de SharedTraceDetailScreen.
Widget feuilleDeTest(SharedTracesApiClient api, String traceId) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: OutlinedButton(
              onPressed: () => showReportTraceSheet(context, traceId: traceId, api: api),
              child: const Text('Signaler'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('choisir un motif envoie le signalement au serveur', (tester) async {
    late Map<String, Object?> envoye;
    final api = _ApiFactice()
      ..onReport = (id, reason, detail) {
        envoye = {'id': id, 'reason': reason};
      };
    await tester.pumpWidget(feuilleDeTest(api, 't42'));
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terrain privé'));
    // Une frame entre les deux appuis : sans elle, le bouton Envoyer reste
    // sur son état précédent (désactivé) au moment du second appui — le
    // choix du motif n'a pas encore été reconstruit dans l'arbre.
    await tester.pump();
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(envoye['id'], 't42');
    expect(envoye['reason'], 'terrain_prive');
  });

  testWidgets('sans motif choisi, le bouton Envoyer reste inactif', (tester) async {
    await tester.pumpWidget(feuilleDeTest(_ApiFactice(), 't42'));
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();
    final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Envoyer'));
    expect(bouton.onPressed, isNull);
  });

  testWidgets('un signalement deja envoye affiche le message du serveur', (tester) async {
    final api = _ApiFactice()..erreurReport = const SharedTracesException(409, 'Tu as déjà signalé cette trace.');
    await tester.pumpWidget(feuilleDeTest(api, 't42'));
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dangereux'));
    await tester.pump();
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà signalé'), findsOneWidget);
  });
}
