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
