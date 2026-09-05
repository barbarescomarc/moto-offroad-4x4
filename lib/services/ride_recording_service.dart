import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'background_service_coordinator.dart';

// ── Client "enregistrement" du service d'arrière-plan partagé ────────────
// L'API publique (start/stop/updateNotification/requestPermissions/
// isRunning) ne change pas : seul le fonctionnement interne passe par le
// coordinateur, partagé avec le guidage (voir background_service_coordinator.dart).
class RideRecordingService {
  static final RideRecordingService _instance = RideRecordingService._();
  factory RideRecordingService() => _instance;
  RideRecordingService._({BackgroundServiceCoordinator? coordinator})
      : _coordinator = coordinator ?? BackgroundServiceCoordinator.instance;

  @visibleForTesting
  factory RideRecordingService.withCoordinator(BackgroundServiceCoordinator coordinator) =>
      RideRecordingService._(coordinator: coordinator);

  static const String _clientId = 'recording';
  final BackgroundServiceCoordinator _coordinator;

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

  // Le coordinateur garde un titre générique au niveau du système ("Moto
  // Offroad") et compose la notification à partir du texte de chaque client :
  // ce qui distingue l'enregistrement doit donc voyager dans ce texte, titre
  // compris — sinon "Enregistrement en cours" est reçu puis jeté.
  static String _compose(String title, String text) =>
      text.isEmpty ? title : '$title · $text';

  Future<bool> start({required String title, required String text}) async {
    await _coordinator.requestActive(_clientId, _compose(title, text));
    return true;
  }

  Future<void> updateNotification({required String title, required String text}) async {
    await _coordinator.requestActive(_clientId, _compose(title, text));
  }

  Future<void> stop() async {
    await _coordinator.release(_clientId);
  }
}
