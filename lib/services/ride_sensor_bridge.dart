import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../providers/recording_provider.dart';
import 'location_service.dart';

// ── Pont entre les capteurs réels et le provider ─────────────
// Isolé du provider pour que la logique d'enregistrement reste testable
// sans matériel.
class RideSensorBridge {
  static final RideSensorBridge _instance = RideSensorBridge._();
  factory RideSensorBridge() => _instance;
  RideSensorBridge._();

  StreamSubscription? _gpsSub;
  StreamSubscription? _accelSub;

  void attach(RecordingProvider provider) {
    detach();
    _gpsSub = LocationService().stream.listen(provider.onGpsSample);
    _accelSub = accelerometerEventStream().listen(
      (e) => provider.onAccelerometer(e.x, e.y, e.z),
    );
  }

  void detach() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gpsSub = null;
    _accelSub = null;
  }
}
