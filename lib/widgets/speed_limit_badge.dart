// lib/widgets/speed_limit_badge.dart
import 'package:flutter/material.dart';

// Panneau routier européen (rond blanc, liseré rouge) — affiché à côté du
// chiffre de vitesse en guidage actif, quand une limite a pu être trouvée.
class SpeedLimitBadge extends StatelessWidget {
  final double limitKmh;
  final double size;

  const SpeedLimitBadge({super.key, required this.limitKmh, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD32F2F), width: size * 0.11),
      ),
      child: Text(
        limitKmh.toStringAsFixed(0),
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          fontFamily: 'Rajdhani',
        ),
      ),
    );
  }
}
