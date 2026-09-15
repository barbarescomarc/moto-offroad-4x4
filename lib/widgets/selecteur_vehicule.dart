import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/vehicle_kind.dart';
import '../providers/settings_provider.dart';
import 'radial_action_menu.dart';

/// Sélecteur de véhicule, en tête de l'en-tête.
///
/// Il a remplacé le « mode de navigation » (Offroad / Route / 4X4), qui
/// disait la même chose que le véhicule dans d'autres mots et pouvait le
/// contredire : on pouvait rouler en mode 4X4 avec un camping-car déclaré
/// dans les réglages, et l'application ne savait plus lequel écouter pour
/// le gabarit. Il n'y a plus qu'une notion, celle qui commandait déjà les
/// aires, les points d'intérêt, le hors-route et le calcul d'itinéraire.
///
/// Il n'apparaît que s'il y a un choix à faire : un pilote qui ne possède
/// qu'une moto n'a pas besoin d'un bouton pour choisir sa moto.
class SelecteurVehicule extends StatelessWidget {
  const SelecteurVehicule({super.key});

  /// L'arc s'ouvre vers le bas-gauche : posé en haut de l'écran, ce bouton
  /// n'a pas de place au-dessus de lui, et le bord droit lui interdit la
  /// droite.
  static const double _angleDebut = 290;
  static const double _angleFin = 350;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.plusieursVehicules) return const SizedBox.shrink();

    final autres = VehicleKind.values
        .where((v) => settings.garage.contains(v) && v != settings.vehicleKind)
        .toList();

    return RadialActionMenu(
      centerIcon: settings.vehicleKind.icon,
      centerColor: AppColors.accent,
      centerActive: true,
      radius: 110,
      onCenterTap: settings.vehiculeSuivant,
      segments: [
        for (var i = 0; i < autres.length; i++)
          RadialMenuSegment(
            icon: autres[i].icon,
            color: AppColors.accent,
            angleDeg: autres.length == 1
                ? (_angleDebut + _angleFin) / 2
                : _angleDebut + i * (_angleFin - _angleDebut) / (autres.length - 1),
            onSelect: () => settings.setVehicleKind(autres[i]),
          ),
      ],
    );
  }
}
