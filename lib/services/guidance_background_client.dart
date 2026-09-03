import 'background_service_coordinator.dart';

class GuidanceBackgroundClient {
  GuidanceBackgroundClient({BackgroundServiceCoordinator? coordinator})
      : _coordinator = coordinator ?? BackgroundServiceCoordinator.instance;

  static const _clientId = 'guidance';
  final BackgroundServiceCoordinator _coordinator;

  Future<void> start(String text) => _coordinator.requestActive(_clientId, text);
  Future<void> update(String text) => _coordinator.requestActive(_clientId, text);
  Future<void> stop() => _coordinator.release(_clientId);
}
