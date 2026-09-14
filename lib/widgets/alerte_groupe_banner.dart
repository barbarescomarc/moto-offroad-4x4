// lib/widgets/alerte_groupe_banner.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../providers/group_provider.dart';
import '../services/tracker_api_client.dart';

/// Un rider de la sortie appelle à l'aide.
///
/// Il est à quelques centaines de mètres, là où un contact de confiance est à
/// plusieurs heures de route : ce bandeau est ce qui le rend joignable par les
/// seules personnes capables d'arriver dans les minutes qui suivent. Il dit
/// donc l'essentiel du secours à moto — qui, où, à quelle distance, par où —
/// et rien d'autre.
class AlerteGroupeBanner extends StatelessWidget {
  const AlerteGroupeBanner({
    super.key,
    required this.maPosition,
    this.onYAller,
  });

  /// Position du lecteur, pour calculer la distance et le cap. Nulle tant que
  /// le GPS n'a pas accroché : le bandeau s'affiche quand même, amputé de la
  /// distance — savoir qu'un rider est à terre prime sur savoir où.
  final LatLng? Function() maPosition;

  /// Lance le guidage vers le rider en difficulté.
  final void Function(LatLng cible)? onYAller;

  @override
  Widget build(BuildContext context) {
    final groupe = context.watch<GroupProvider>();
    final alerte = groupe.alerteAafficher;
    if (alerte == null) return const SizedBox.shrink();

    final jeSuisLauteur = groupe.jeSuisLauteurDeLalerte;

    return Container(
      key: const Key('alerte-groupe'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.statusRed,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_share, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  jeSuisLauteur
                      ? 'Ton alerte est partie au groupe'
                      : '${alerte.name} — ${alerte.estSos ? 'SOS' : 'chute détectée'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Rajdhani',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _sousTitre(alerte, jeSuisLauteur),
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          _commandes(context, groupe, alerte, jeSuisLauteur),
        ],
      ),
    );
  }

  String _sousTitre(AlerteGroupe alerte, bool jeSuisLauteur) {
    if (jeSuisLauteur) {
      return 'Les riders de la sortie la voient sur leur carte. '
          'Retire-la si tu vas bien.';
    }
    final cible = alerte.position;
    if (cible == null) {
      // Le dire franchement : un bandeau muet sur la position laisserait
      // croire qu'on cherche au bon endroit.
      return 'Position inconnue — il n\'avait pas encore envoyé de point. '
          'Appelle-le, et préviens les secours.';
    }
    final moi = maPosition();
    if (moi == null) return 'Position reçue. En attente de ta position GPS.';

    final metres = const Distance().distance(moi, cible);
    return '${_distance(metres)} · ${_cap(moi, cible)} — ${_heure(alerte.raisedAt)}';
  }

  Widget _commandes(
    BuildContext context,
    GroupProvider groupe,
    AlerteGroupe alerte,
    bool jeSuisLauteur,
  ) {
    // Wrap plutôt que Row : le thème impose une largeur minimale infinie aux
    // ElevatedButton, et deux boutons côte à côte dans un Row deviennent
    // intouchables sur écran étroit.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (jeSuisLauteur)
            ElevatedButton.icon(
              key: const Key('alerte-groupe-je-vais-bien'),
              onPressed: () => groupe.retirerAlerte(),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Je vais bien'),
              style: _styleBouton,
            )
          else ...[
            TextButton(
              key: const Key('alerte-groupe-masquer'),
              onPressed: groupe.masquerAlerte,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 44),
              ),
              child: const Text('Masquer'),
            ),
            if (alerte.position != null && onYAller != null)
              ElevatedButton.icon(
                key: const Key('alerte-groupe-y-aller'),
                onPressed: () => onYAller!(alerte.position!),
                icon: const Icon(Icons.navigation, size: 18),
                label: const Text('Y aller'),
                style: _styleBouton,
              ),
          ],
        ],
      ),
    );
  }

  static final ButtonStyle _styleBouton = ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: AppColors.statusRed,
    // Le thème impose Size(double.infinity, 52) à tout ElevatedButton, ce qui
    // rend celui-ci intouchable dès qu'il partage sa ligne.
    minimumSize: const Size(64, 44),
  );

  static String _distance(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

  /// Cap en points cardinaux plutôt qu'en degrés : on lit ça avec des gants,
  /// casque sur la tête, et « nord-est » se comprend sans réfléchir.
  static String _cap(LatLng de, LatLng vers) {
    final releve = const Distance().bearing(de, vers);
    const points = ['nord', 'nord-est', 'est', 'sud-est', 'sud', 'sud-ouest', 'ouest', 'nord-ouest'];
    final index = (((releve % 360) + 360) % 360 / 45).round() % 8;
    return 'vers le ${points[index]}';
  }

  static String _heure(DateTime t) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'à ${deux(t.hour)}:${deux(t.minute)}';
  }
}
