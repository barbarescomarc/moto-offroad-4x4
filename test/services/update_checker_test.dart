import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/services/update_checker.dart';

void main() {
  group('compareVersions', () {
    test('deux versions identiques sont égales', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
    });

    test('une version majeure plus haute gagne', () {
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('une version mineure plus haute gagne', () {
      expect(compareVersions('1.3.0', '1.2.9'), greaterThan(0));
    });

    // Le piège : comparées comme du texte, « 1.0.10 » passerait avant
    // « 1.0.9 » et personne ne serait jamais prévenu de la mise à jour.
    test('les correctifs se comparent en nombres, pas en texte', () {
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    });

    test('une version plus ancienne perd', () {
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('le préfixe v est ignoré', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
    });

    test('un numéro de build est ignoré', () {
      expect(compareVersions('1.2.0+7', '1.2.0'), 0);
    });

    test('les segments manquants valent zéro', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.1'), lessThan(0));
    });

    test('un texte illisible ne fait pas planter', () {
      expect(compareVersions('abc', '1.0.0'), lessThan(0));
    });
  });

  group('UpdateChecker.fetchLatest', () {
    test('renvoie la version publiée', () async {
      final client = MockClient((_) async =>
          http.Response('{"tag_name": "v1.4.0"}', 200));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNotNull);
      expect(info!.version, '1.4.0');
      expect(info.url, UpdateChecker.downloadUrl);
    });

    test('ne signale rien si la version installée est à jour', () async {
      final client = MockClient((_) async =>
          http.Response('{"tag_name": "v1.0.0"}', 200));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });

    test('ne signale rien si la version installée est plus récente', () async {
      final client = MockClient((_) async =>
          http.Response('{"tag_name": "v0.9.0"}', 200));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });

    // Pas de réseau au fond d'une vallée : l'application ne doit jamais
    // s'arrêter là-dessus, la mise à jour n'est pas une urgence.
    test('une panne réseau ne remonte pas d erreur', () async {
      final client = MockClient((_) async => throw Exception('pas de réseau'));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });

    test('une réponse HTTP en erreur ne remonte pas d erreur', () async {
      final client = MockClient((_) async => http.Response('', 404));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });

    test('une réponse illisible ne remonte pas d erreur', () async {
      final client =
          MockClient((_) async => http.Response('pas du json', 200));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });

    test('une réponse sans tag_name ne remonte pas d erreur', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final info = await UpdateChecker.fetchLatest(
          currentVersion: '1.0.0', client: client);
      expect(info, isNull);
    });
  });
}
