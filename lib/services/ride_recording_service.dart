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
