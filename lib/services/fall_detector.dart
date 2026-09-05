import 'dart:async';
import 'dart:math';
import 'location_service.dart';
import 'vibration_meter.dart';

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
//
// Repli sans GPS : si aucune position n'a jamais été reçue depuis le
// démarrage de la détection (permission refusée, écran carte jamais ouvert —
// PAS juste « pendant cette fenêtre » : un vrai arrêt fait aussi taire le
// flux GPS, `_hasGps` doit donc rester vrai une fois vu, pas se réinitialiser
// à chaque chute), le silence ne suffit plus à lui seul — trois signaux
// accéléromètre doivent converger :
// un choc nettement plus fort que d'habitude, une orientation d'arrivée
// vraiment différente de celle de la conduite (pas seulement figée), et des
// vibrations retombées au niveau du ralenti moteur plutôt que celui, plus
// élevé, de la conduite.
class FallDetector {
  FallDetector({
    required Stream<List<double>> accelerometer,
    required Stream<GpsSnapshot> positions,
    required this.shockThreshold,
    this.stopWindow = const Duration(seconds: 20),
    this.settleDelay = const Duration(seconds: 2),
    this.stopSpeedKmh = 3.0,
    this.tiltMaxDeg = 5.0,
    this.noGpsShockMultiplier = 2.0,
    this.noGpsTiltFromRidingDeg = 20.0,
    this.idleVibrationLevel,
    this.idleVibrationMultiplier = 1.5,
    this.vibrationWindowSize = 100,
  })  : _accelerometer = accelerometer,
        _positions = positions,
        _vibrationMeter = VibrationMeter(windowSize: vibrationWindowSize);

  final Stream<List<double>> _accelerometer;
  final Stream<GpsSnapshot> _positions;
  final double Function() shockThreshold;
  final Duration stopWindow;
  final Duration settleDelay;
  final double stopSpeedKmh;
  final double tiltMaxDeg;
  final double noGpsShockMultiplier;
  final double noGpsTiltFromRidingDeg;
  final double Function()? idleVibrationLevel;
  final double idleVibrationMultiplier;
  final int vibrationWindowSize;

  final VibrationMeter _vibrationMeter;

  StreamSubscription<List<double>>? _accelSub;
  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _windowTimer;
  Timer? _settleTimer;
  List<double>? _originVector;
  List<double>? _lastSample;
  List<double>? _preShockSample;
  double? _shockMagnitude;
  bool _watching = false;
  bool _hasGps = false;
  void Function()? _onFallDetected;

  void start({required void Function() onFallDetected}) {
    stop();
    _onFallDetected = onFallDetected;

    _accelSub = _accelerometer.listen((sample) {
      final previousSample = _lastSample;
      _lastSample = sample;
      final magnitude = _magnitude(sample);
      _vibrationMeter.addSample(magnitude);

      if (!_watching) {
        // Pas en observation : un choc démarre la fenêtre ET le délai de
        // stabilisation. L'inclinaison n'est pas encore jugée : dans les
        // instants qui suivent un impact, l'orientation bouge forcément,
        // chute ou pas. On retient aussi l'orientation ET la magnitude
        // du choc, pour le repli sans GPS ci-dessous.
        if (magnitude >= shockThreshold()) {
          _preShockSample = previousSample ?? sample;
          _shockMagnitude = magnitude;
          _watching = true;
          _windowTimer = Timer(stopWindow, () {
            if (_shouldFire()) _onFallDetected?.call();
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
      _hasGps = true;
      if (!_watching) return; // pas en observation, rien à vérifier
      if (snap.speedKmh >= stopSpeedKmh) {
        _resetWatch();
      }
    });
  }

  // Le GPS confirme normalement l'arrêt (comportement inchangé). Sans
  // aucune position reçue pendant toute la fenêtre, les trois signaux
  // accéléromètre doivent tous converger avant de déclencher.
  bool _shouldFire() {
    if (_hasGps) return true;

    final shock = _shockMagnitude;
    final origin = _originVector;
    final preShock = _preShockSample;
    if (shock == null || origin == null || preShock == null) return false;

    final bigEnough = shock >= shockThreshold() * noGpsShockMultiplier;
    final tiltChangedFromRiding = _angleBetweenDeg(preShock, origin) > noGpsTiltFromRidingDeg;
    final idleLevel = idleVibrationLevel;
    final lowVibration = idleLevel == null || _vibrationMeter.level <= idleLevel() * idleVibrationMultiplier;

    return bigEnough && tiltChangedFromRiding && lowVibration;
  }

  void _resetWatch() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _originVector = null;
    _preShockSample = null;
    _shockMagnitude = null;
    _watching = false;
  }

  void stop() {
    _accelSub?.cancel();
    _positionSub?.cancel();
    _accelSub = null;
    _positionSub = null;
    _onFallDetected = null;
    _lastSample = null;
    _hasGps = false;
    _vibrationMeter.reset();
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
