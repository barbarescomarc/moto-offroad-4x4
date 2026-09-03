import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/background_service_coordinator.dart';
import 'package:moto_offroad/services/guidance_background_client.dart';
import 'package:moto_offroad/services/ride_recording_service.dart';

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

  // Les tests ci-dessus valident la composition du coordinateur avec des
  // chaînes fabriquées ; ceux-ci partent des vrais appelants, seule façon de
  // voir qu'un texte accepté par un service est bien acheminé jusqu'au bout.
  group('acheminement depuis les services appelants', () {
    test('RideRecordingService transmet le titre ET le texte', () async {
      final control = _FakeControl();
      final service = RideRecordingService.withCoordinator(
        BackgroundServiceCoordinator(control: control),
      );

      await service.start(title: 'Enregistrement en cours', text: '12,3 km · 01:23');

      expect(control.lastText, contains('Enregistrement en cours'));
      expect(control.lastText, contains('12,3 km · 01:23'));
    });

    test('RideRecordingService garde le titre lors d\'une mise à jour', () async {
      final control = _FakeControl();
      final service = RideRecordingService.withCoordinator(
        BackgroundServiceCoordinator(control: control),
      );

      await service.start(title: 'Enregistrement en cours', text: '0,0 km · 00:00');
      await service.updateNotification(
          title: 'Enregistrement en cours', text: '12,3 km · 01:23');

      expect(control.lastText, contains('Enregistrement en cours'));
      expect(control.lastText, contains('12,3 km · 01:23'));
    });

    test('GuidanceBackgroundClient transmet son texte tel quel', () async {
      final control = _FakeControl();
      final client = GuidanceBackgroundClient(
        coordinator: BackgroundServiceCoordinator(control: control),
      );

      await client.start('Guidage actif');

      expect(control.lastText, 'Guidage actif');
    });
  });
}
