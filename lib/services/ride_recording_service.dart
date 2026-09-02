import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ── Service d'arrière-plan ───────────────────────────────────
// Ne fait que deux choses : maintenir le processus vivant pendant
// l'enregistrement, et afficher une notification à jour. Toute la logique
// d'enregistrement vit dans l'isolat principal (RecordingProvider).
class RideRecordingService {
  static final RideRecordingService _instance = RideRecordingService._();
  factory RideRecordingService() => _instance;
  RideRecordingService._();

  static const String _channelId = 'moto_offroad_recording';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:         _channelId,
        channelName:       'Enregistrement de sortie',
        channelDescription:
            'Maintient l\'enregistrement actif quand l\'écran est éteint.',
        channelImportance: NotificationChannelImportance.LOW,
        priority:          NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 8.17.0 : plus de champ `interval`, la cadence passe par eventAction.
        eventAction:       ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot:     false,
        allowWakeLock:     true,
        allowWifiLock:     false,
      ),
    );
    _initialized = true;
  }

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
    await init();
    if (await isRunning) return true;
    final result = await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText:  text,
    );
    return result is ServiceRequestSuccess;
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!await isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText:  text,
    );
  }

  Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
  }
}
