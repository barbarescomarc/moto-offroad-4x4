import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../services/vibration_calibration.dart';
import '../../services/vibration_meter.dart';

enum _Phase { intro, still, idle, done }

class VibrationCalibrationScreen extends StatefulWidget {
  const VibrationCalibrationScreen({super.key});

  @override
  State<VibrationCalibrationScreen> createState() =>
      _VibrationCalibrationScreenState();
}

class _VibrationCalibrationScreenState
    extends State<VibrationCalibrationScreen> {
  static const Duration _measureDuration = Duration(seconds: 10);

  final _meter = VibrationMeter(windowSize: 500);
  StreamSubscription? _sub;
  Timer? _timer;

  _Phase _phase = _Phase.intro;
  int _remaining = 0;
  double? _stillLevel;
  double? _idleLevel;

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream().listen((e) {
      _meter.addSample(VibrationMeter.magnitudeOf(e.x, e.y, e.z));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _measure(_Phase phase) {
    _meter.reset();
    setState(() {
      _phase = phase;
      _remaining = _measureDuration.inSeconds;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      setState(() => _remaining--);
      if (_remaining > 0) return;
      t.cancel();
      final level = _meter.level;
      if (phase == _Phase.still) {
        setState(() => _stillLevel = level);
      } else {
        setState(() {
          _idleLevel = level;
          _phase = _Phase.done;
        });
        await VibrationCalibration(stillLevel: _stillLevel, idleLevel: level)
            .save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CALIBRER LES VIBRATIONS')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_phase) {
          _Phase.intro => _intro(),
          _Phase.still => _countdown(
              'Moteur coupé, téléphone en place.\nNe touchez à rien.'),
          _Phase.idle => _countdown(
              'Démarrez le moteur et laissez-le tourner au ralenti.'),
          _Phase.done => _result(),
        },
      ),
    );
  }

  Widget _intro() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'La calibration apprend à l\'application ce que « immobile » veut '
            'dire pour votre moto et pour la position de votre téléphone.\n\n'
            'Deux mesures de 10 secondes : moteur coupé, puis moteur au '
            'ralenti. Installez le téléphone comme quand vous roulez.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => _measure(_Phase.still),
            child: const Text('Commencer'),
          ),
        ],
      );

  Widget _countdown(String instruction) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          Text('$_remaining',
              style: const TextStyle(
                  fontSize: 64, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (_phase == _Phase.still && _stillLevel != null)
            const Text('Mesure 1 terminée'),
        ],
      );

  Widget _result() {
    final cal =
        VibrationCalibration(stillLevel: _stillLevel, idleLevel: _idleLevel);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Immobile : ${_stillLevel!.toStringAsFixed(3)}'),
        Text('Ralenti : ${_idleLevel!.toStringAsFixed(3)}'),
        const SizedBox(height: 12),
        Text('Seuil retenu : ${cal.threshold.toStringAsFixed(3)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 20),
        if (!cal.isCalibrated)
          const Text(
            'Mesures incohérentes : le ralenti doit vibrer davantage que '
            'l\'arrêt moteur. Le seuil par défaut reste utilisé. '
            'Recommencez en installant le téléphone comme quand vous roulez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFF9A825)),
          ),
        const SizedBox(height: 20),
        // Test en direct : sans lui, on calibre à l'aveugle.
        StreamBuilder<int>(
          stream: Stream.periodic(const Duration(milliseconds: 400), (i) => i),
          builder: (_, __) {
            final live = _meter.level;
            final immobile = live < cal.threshold;
            return Text(
              immobile
                  ? 'Test en direct : immobile ✓'
                  : 'Test en direct : en mouvement',
              style: TextStyle(
                  color: immobile
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFEF5350)),
            );
          },
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => _measure(_Phase.still),
              child: const Text('Recommencer'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminer'),
            ),
          ],
        ),
      ],
    );
  }
}
