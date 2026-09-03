import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/background_service_coordinator.dart';

class _FakeControl implements ForegroundServiceControl {
  bool running = false;
  String? lastTitle;
  String? lastText;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<bool> start({required String title, required String text}) async {
    startCalls++;
    running = true;
    lastTitle = title;
    lastText = text;
    return true;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    lastTitle = title;
    lastText = text;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }
}

void main() {
  test('démarre le service au premier client actif', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');

    expect(control.startCalls, 1);
    expect(control.lastText, 'Enregistrement en cours');
  });

  test('compose le texte de notification pour deux clients actifs', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');
    await coordinator.requestActive('guidance', 'Guidage actif');

    expect(control.lastText, contains('Enregistrement en cours'));
    expect(control.lastText, contains('Guidage actif'));
    expect(control.startCalls, 1); // pas redémarré, juste mis à jour
  });

  test('arrête le service seulement quand le dernier client se retire', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);

    await coordinator.requestActive('recording', 'Enregistrement en cours');
    await coordinator.requestActive('guidance', 'Guidage actif');
    await coordinator.release('recording');

    expect(control.stopCalls, 0);
    expect(control.lastText, 'Guidage actif');

    await coordinator.release('guidance');
    expect(control.stopCalls, 1);
  });

  test('release d\'un client absent ne fait rien', () async {
    final control = _FakeControl();
    final coordinator = BackgroundServiceCoordinator(control: control);
    await coordinator.release('guidance');
    expect(control.stopCalls, 0);
  });
}
