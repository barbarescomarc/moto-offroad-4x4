import 'dart:collection';
import 'dart:math';

// ── Niveau de secousse sur une fenêtre glissante ─────────────
// À 50 Hz, une fenêtre de 100 échantillons couvre environ 2 secondes.
class VibrationMeter {
  VibrationMeter({this.windowSize = 100});

  final int windowSize;
  final Queue<double> _samples = Queue<double>();

  void addSample(double magnitude) {
    _samples.addLast(magnitude);
    while (_samples.length > windowSize) {
      _samples.removeFirst();
    }
  }

  // Écart-type de la fenêtre : indépendant de la gravité, qui n'est
  // qu'une composante constante du signal.
  double get level {
    if (_samples.length < 2) return 0;
    final mean = _samples.reduce((a, b) => a + b) / _samples.length;
    final variance = _samples
        .map((s) => (s - mean) * (s - mean))
        .reduce((a, b) => a + b) / _samples.length;
    return sqrt(variance);
  }

  void reset() => _samples.clear();

  static double magnitudeOf(double x, double y, double z) =>
      sqrt(x * x + y * y + z * z);
}
