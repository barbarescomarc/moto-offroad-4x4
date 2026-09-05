import 'dart:async';
import 'dart:math';
import 'location_service.dart';

// ── Détection de chute en trois temps ────────────────────────
//
// Choc, puis un court délai de stabilisation (le temps que le téléphone
// finisse de bouger après l'impact — il n'a aucune raison de garder
// l'orientation d'avant le choc, une chute change justement cette
// orientation), puis jusqu'à la fin de la fenêtre de 20 s où la vitesse
// reste sous le seuil ET l'inclinaison ne varie plus PAR RAPPORT À
// L'ORIENTATION STABILISÉE — les deux doivent tenir sur tout le reste de la
// fenêtre, pas seulement à un instant donné. Un choc sans chute (nid-de-poule)
// laisse le pilote reparti avant la fin de la fenêtre (la vitesse remonte) ;
// une vraie chute immobilise le téléphone dans sa position d'arrivée jusqu'à
// ce que quelqu'un le bouge.
class FallDetector {
  FallDetector({
    required Stream<List<double>> accelerometer,
    required Stream<GpsSnapshot> positions,
    required this.shockThreshold,
    this.stopWindow = const Duration(seconds: 20),
    this.settleDelay = const Duration(seconds: 2),
    this.stopSpeedKmh = 3.0,
    this.tiltMaxDeg = 5.0,
  })  : _accelerometer = accelerometer,
        _positions = positions;

  final Stream<List<double>> _accelerometer;
  final Stream<GpsSnapshot> _positions;
  final double Function() shockThreshold;
  final Duration stopWindow;
  final Duration settleDelay;
  final double stopSpeedKmh;
  final double tiltMaxDeg;

  StreamSubscription<List<double>>? _accelSub;
  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _windowTimer;
  Timer? _settleTimer;
  List<double>? _originVector;
  List<double>? _lastSample;
  bool _watching = false;
  void Function()? _onFallDetected;

  void start({required void Function() onFallDetected}) {
    stop();
    _onFallDetected = onFallDetected;

    _accelSub = _accelerometer.listen((sample) {
      _lastSample = sample;
      final magnitude = _magnitude(sample);

      if (!_watching) {
        // Pas en observation : un choc démarre la fenêtre ET le délai de
        // stabilisation. L'inclinaison n'est pas encore jugée : dans les
        // instants qui suivent un impact, l'orientation bouge forcément,
        // chute ou pas.
        if (magnitude >= shockThreshold()) {
          _watching = true;
          _windowTimer = Timer(stopWindow, () {
            _onFallDetected?.call();
            _resetWatch();
          });
          _settleTimer = Timer(settleDelay, () {
            // Position d'arrivée : le dernier échantillon connu au moment
            // où le délai de stabilisation expire, pas le choc lui-même.
            _originVector = _lastSample;
          });
        }
        return;
      }

      // En observation, mais toujours dans le délai de stabilisation :
      // rien à juger tant que l'origine n'est pas capturée.
      if (_originVector == null) return;

      // Stabilisé : toute inclinaison hors tolérance par rapport à la
      // position d'arrivée annule.
      if (_angleBetweenDeg(_originVector!, sample) > tiltMaxDeg) {
        _resetWatch();
      }
    });

    _positionSub = _positions.listen((snap) {
      if (!_watching) return; // pas en observation, rien à vérifier
      if (snap.speedKmh >= stopSpeedKmh) {
        _resetWatch();
      }
    });
  }

  void _resetWatch() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _originVector = null;
    _watching = false;
  }

  void stop() {
    _accelSub?.cancel();
    _positionSub?.cancel();
    _accelSub = null;
    _positionSub = null;
    _onFallDetected = null;
    _lastSample = null;
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
