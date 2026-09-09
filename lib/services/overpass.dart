// lib/services/overpass.dart
//
// Réglages partagés par les trois services qui interrogent Overpass : radars
// fixes, limitations de vitesse, stations-service et réparateurs moto.

/// Point d'accès public de l'API Overpass.
const String overpassEndpoint = 'https://overpass-api.de/api/interpreter';

/// Agent utilisateur envoyé à Overpass.
///
/// **Ne pas retirer.** Overpass répond `406 Not Acceptable` à l'agent par
/// défaut de Dart (`Dart/3.x (dart:io)`), celui que `package:http` envoie sur
/// Android. Sans cet en-tête, aucune requête n'aboutit depuis un appareil
/// réel — et l'échec passe inaperçu partout où l'appelant avale ses erreurs.
///
/// Constaté le 9 septembre 2026 sur appareil : 406 avec l'agent Dart, 200
/// avec celui-ci.
const String overpassUserAgent = 'MotoOffroad/1.7 (app.motooffroad)';
