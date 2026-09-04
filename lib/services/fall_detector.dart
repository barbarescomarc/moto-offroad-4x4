import 'dart:async';
import 'dart:math';
import 'location_service.dart';

// ── Détection de chute en trois temps ────────────────────────
//
// Choc, puis 20 secondes où la vitesse reste sous le seuil ET l'inclinaison
// ne varie pas — les deux doivent tenir sur toute la fenêtre, pas
// seulement à un instant donné. Un saut produit un choc mais le pilote
// repart (la vitesse remonte) ; une chute sans gravité fait bouger le
// téléphone pendant qu'on se relève (l'inclinaison varie). Les deux sont
// ainsi écartées sans confondre avec une vraie chute.
class FallDetector {
  FallDetector({
    required Stream<List<double>> accelerometer,
    required Stream<GpsSnapshot> positions,
    required this.shockThreshold,
    this.stopWindow = const Duration(seconds: 20),
    this.stopSpeedKmh = 3.0,
    this.tiltMaxDeg = 5.0,
  })  : _accelerometer = accelerometer,
        _positions = positions;

  final Stream<List<double>> _accelerometer;
  final Stream<GpsSnapshot> _positions;
  final double Function() shockThreshold;
  final Duration stopWindow;
  final double stopSpeedKmh;
  final double tiltMaxDeg;

  StreamSubscription<List<double>>? _accelSub;
  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _windowTimer;
  List<double>? _originVector;
  List<double>? _lastSample;
  void Function()? _onFallDetected;

  void start({required void Function() onFallDetected}) {
    stop();
    _onFallDetected = onFallDetected;

    _accelSub = _accelerometer.listen((sample) {
      final magnitude = _magnitude(sample);
      final previousSample = _lastSample;
      _lastSample = sample;

      if (_originVector == null) {
        // Pas en observation : un choc démarre la fenêtre. L'orientation de
        // référence est celle d'AVANT le choc (le dernier échantillon connu),
        // pas le choc lui-même — le choc est justement le moment où
        // l'orientation change brutalement, donc s'en servir comme référence
        // ferait toujours passer l'instant suivant pour une inclinaison.
        if (magnitude >= shockThreshold()) {
          _originVector = previousSample ?? sample;
          _windowTimer?.cancel();
          _windowTimer = Timer(stopWindow, () {
            _onFallDetected?.call();
            _resetWatch();
          });
        }
        return;
      }

      // En observation : toute inclinaison hors tolérance annule.
      if (_angleBetweenDeg(_originVector!, sample) > tiltMaxDeg) {
        _resetWatch();
      }
    });

    _positionSub = _positions.listen((snap) {
      if (_originVector == null) return; // pas en observation, rien à vérifier
      if (snap.speedKmh >= stopSpeedKmh) {
        _resetWatch();
      }
    });
  }

  void _resetWatch() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _originVector = null;
  }

  void stop() {
    _accelSub?.cancel();
    _positionSub?.cancel();
    _accelSub = null;
    _positionSub = null;
    _onFallDetected = null;
    _resetWatch();
  }

  static double _magnitude(List<double> v) => sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

  static double _angleBetweenDeg(List<double> a, List<double> b) {
    final dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    final magA = _magnitude(a);
    final magB = _magnitude(b);
    if (magA == 0 || magB == 0) return 0;
    final cosAngle = (dot / (magA * magB)).clamp(-1.0, 1.0);
    return acos(cosAngle) * 180 / pi;
  }
}
