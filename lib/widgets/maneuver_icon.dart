// lib/widgets/maneuver_icon.dart
import 'package:flutter/material.dart';
import '../models/route_result.dart';

IconData maneuverIcon(ManeuverType? m) {
  switch (m) {
    case ManeuverType.turnLeft:   return Icons.turn_left;
    case ManeuverType.turnRight:  return Icons.turn_right;
    case ManeuverType.sharpLeft:  return Icons.turn_sharp_left;
    case ManeuverType.sharpRight: return Icons.turn_sharp_right;
    case ManeuverType.uturn:      return Icons.u_turn_left;
    case ManeuverType.arrive:     return Icons.flag;
    case ManeuverType.depart:     return Icons.navigation;
    case ManeuverType.straight:
    case null:                    return Icons.straight;
  }
}
