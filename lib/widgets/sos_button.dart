import 'package:flutter/material.dart';
import '../app/theme.dart';

/// Bouton SOS — appui long 2 secondes, 52×52 dp minimum (utilisable avec des gants)
class SosButton extends StatefulWidget {
  final VoidCallback onPressed;
  const SosButton({super.key, required this.onPressed});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  double _holdProgress = 0.0;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startHold() {
    setState(() { _holding = true; _holdProgress = 0.0; });
    _runHold();
  }

  Future<void> _runHold() async {
    const steps = 40;
    const duration = Duration(milliseconds: 2000);
    final stepDuration = duration ~/ steps;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(stepDuration);
      if (!_holding || !mounted) return;
      setState(() => _holdProgress = i / steps);
    }
    if (_holding && mounted) {
      _cancelHold();
      widget.onPressed();
    }
  }

  void _cancelHold() {
    if (!mounted) return;
    setState(() { _holding = false; _holdProgress = 0.0; });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd:   (_) => _cancelHold(),
      onLongPressCancel:    _cancelHold,
      onTap: widget.onPressed, // tap court ouvre aussi l'écran SOS
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final glowRadius = 4.0 + (_pulseAnim.value * 8.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Halo pulsé
              Container(
                width: AppSizes.sosButtonSize + 12,
                height: AppSizes.sosButtonSize + 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withOpacity(.15 * _pulseAnim.value),
                ),
              ),
              // Bouton principal
              Container(
                width: AppSizes.sosButtonSize,
                height: AppSizes.sosButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withOpacity(.5),
                      blurRadius: glowRadius,
                      spreadRadius: 1,
                    ),
                  ],
                  border: Border.all(color: Colors.white.withOpacity(.3), width: 1.5),
                ),
                child: const Center(
                  child: Text('SOS',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              // Arc de progression lors de l'appui long
              if (_holding)
                SizedBox(
                  width: AppSizes.sosButtonSize + 6,
                  height: AppSizes.sosButtonSize + 6,
                  child: CircularProgressIndicator(
                    value: _holdProgress,
                    strokeWidth: 3,
                    backgroundColor: Colors.white.withOpacity(.2),
                    color: Colors.white,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
