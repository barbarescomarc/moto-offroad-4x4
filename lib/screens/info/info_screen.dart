import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/location_service.dart';

class InfoScreen extends StatelessWidget {
  final bool embedded;

  const InfoScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final snap = LocationService().lastSnapshot;
    final coords = snap != null
        ? '${snap.position.latitude.toStringAsFixed(4)}°N  ${snap.position.longitude.toStringAsFixed(4)}°E'
        : 'GPS non disponible';

    final cartes = <Widget>[
      _positionCard(coords),
      const SizedBox(height: 16),
      _infoCard(
        icon: Icons.two_wheeler,
        color: AppColors.accent,
        title: 'OFFROAD — RÉGLEMENTATION FRANCE',
        items: _offroadRules,
      ),
      const SizedBox(height: 16),
      _infoCard(
        icon: Icons.night_shelter_outlined,
        color: AppColors.secondary,
        title: 'BIVOUAC SAUVAGE — CE QUE DIT LA LOI',
        items: _bivouacRules,
      ),
      const SizedBox(height: 16),
      _infoCard(
        icon: Icons.warning_amber_rounded,
        color: AppColors.statusOrange,
        title: 'ZONES À RISQUE EN FRANCE',
        items: _dangerZones,
      ),
      const SizedBox(height: 16),
      _infoCard(
        icon: Icons.eco_outlined,
        color: AppColors.statusGreen,
        title: 'BONS RÉFLEXES TERRAINS',
        items: _goodPractices,
      ),
      const SizedBox(height: 16),
      _emergencyCard(),
    ];

    // Repliée dans les Réglages, cette page est posée dans la zone défilante
    // de l'écran hôte : la hauteur y est non bornée, et une liste défilante
    // ne peut pas s'y poser — elle lève « Vertical viewport was given
    // unbounded height » et la section s'ouvre alors sur du vide (constaté le
    // 2026-09-13). Une simple colonne, elle, s'étire autant qu'il faut et se
    // laisse faire défiler par l'hôte.
    if (embedded) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cartes,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('ℹ️  INFO TERRAIN')),
      body: ListView(padding: const EdgeInsets.all(16), children: cartes),
    );
  }

  // ── Position GPS actuelle ──────────────────────────────────
  Widget _positionCard(String coords) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Position actuelle', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                Text(coords, style: const TextStyle(color: AppColors.foreground, fontFamily: 'Inter', fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Carte info générique ───────────────────────────────────
  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required List<_InfoItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color:        AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(
                  color: color, fontFamily: 'Inter',
                  fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .8,
                ))),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          // Items
          ...items.map((item) => _itemRow(item)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _itemRow(_InfoItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 15, color: item.color ?? AppColors.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.text, style: const TextStyle(
              color: AppColors.mutedForeground, fontSize: 12, height: 1.45)),
          ),
        ],
      ),
    );
  }

  // ── Numéros d'urgence ──────────────────────────────────────
  Widget _emergencyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.destructive.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppColors.destructive.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency, color: AppColors.statusRed, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('NUMÉROS D\'URGENCE', style: TextStyle(
                  color: AppColors.statusRed, fontFamily: 'Inter',
                  fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .8,
                )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._emergencyNumbers.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 30,
                child: Text(e.$1, style: const TextStyle(
                  color: AppColors.statusRed, fontFamily: 'Inter',
                  fontSize: 16, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              // Expanded, pas un Text nu : repliée dans les Réglages, la
              // carte est bien plus étroite qu'en plein écran, et le libellé
              // débordait par la droite au lieu de passer à la ligne.
              Expanded(
                child: Text(e.$2, style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 12)),
              ),
            ]),
          )),
        ],
      ),
    );
  }
}

// ── Données réglementation ─────────────────────────────────────
class _InfoItem {
  final String text;
  final IconData icon;
  final Color? color;

  const _InfoItem(this.text, this.icon, [this.color]);
}

const _offroadRules = <_InfoItem>[
  _InfoItem(
    'Loi Lalonde (1991) : interdit de circuler en véhicule motorisé hors des voies ouvertes à la circulation, sauf autorisation du propriétaire.',
    Icons.gavel, AppColors.statusRed),
  _InfoItem(
    'Chemins forestiers (ONF) : accès interdit aux motos sauf chemins ouverts signalés. En forêt domaniale, une autorisation préfectorale peut être nécessaire.',
    Icons.forest),
  _InfoItem(
    'Pistes DFCI (lutte incendie) : accès interdit au public, surtout en été. Les barrières fermées doivent être respectées.',
    Icons.local_fire_department, AppColors.statusOrange),
  _InfoItem(
    'Espaces Naturels Sensibles (ENS) : réglementation spécifique par département. Consulter le CG local avant de passer.',
    Icons.nature),
  _InfoItem(
    'Bonne pratique : obtenir l\'accord du propriétaire (agriculteur, commune, ONF) ou circuler sur les sentiers balisés autorisés aux motos (FFM, traces partagées).',
    Icons.handshake_outlined, AppColors.statusGreen),
];

const _bivouacRules = <_InfoItem>[
  _InfoItem(
    'Le bivouac (1 nuit) est toléré dans la grande majorité des espaces naturels non protégés, à condition d\'arriver tard (après 19h) et de partir tôt (avant 9h).',
    Icons.check_circle_outline, AppColors.statusGreen),
  _InfoItem(
    'Ne laisser aucune trace : emporter ses déchets, éteindre les feux, ne pas creuser, éviter de couper la végétation.',
    Icons.recycling, AppColors.statusGreen),
  _InfoItem(
    'Camping (plusieurs nuits) : interdit sans autorisation du propriétaire du terrain. En zone agricole, demander toujours à l\'exploitant.',
    Icons.block, AppColors.statusRed),
  _InfoItem(
    'Zones interdites : cœur de Parc National, Réserves Naturelles Intégrales, moins de 200 m d\'un captage d\'eau potable.',
    Icons.do_not_disturb_on_outlined, AppColors.statusRed),
  _InfoItem(
    'Feux de camp : interdits dans la quasi-totalité des forêts françaises. Réchaud à gaz uniquement recommandé.',
    Icons.local_fire_department, AppColors.statusOrange),
  _InfoItem(
    'PACA et Corse : réglementation plus stricte — se renseigner auprès des mairies locales avant de bivouaquer.',
    Icons.info_outline),
];

const _dangerZones = <_InfoItem>[
  _InfoItem('Alertes météo orange/rouge : interrompre la sortie, chercher abri en dur.', Icons.thunderstorm, AppColors.statusOrange),
  _InfoItem('Rivières et ravines en montagne : crue soudaine possible même sans pluie localement visible.', Icons.water, AppColors.statusOrange),
  _InfoItem('Névés et zones enneigées tardives (après-ski) : chutes de pierre, glace masquée sous neige.', Icons.ac_unit),
  _InfoItem('Zones militaires (zone rouge sur IGN) : accès strictement interdit.', Icons.security, AppColors.statusRed),
];

const _goodPractices = <_InfoItem>[
  _InfoItem('Prévenir quelqu\'un de votre itinéraire et de votre heure de retour prévue.', Icons.share_location, AppColors.statusGreen),
  _InfoItem('Emporter eau (min 2L/personne), nourriture et kit de premiers secours.', Icons.local_drink, AppColors.statusGreen),
  _InfoItem('Batterie de secours et numéros d\'urgence enregistrés hors ligne.', Icons.battery_charging_full, AppColors.statusGreen),
  _InfoItem('Respecter la faune et la flore : ne pas passer sur les cultures, laisser passer les troupeaux.', Icons.pets, AppColors.statusGreen),
];

const _emergencyNumbers = <(String, String)>[
  ('15',  'SAMU — urgences médicales'),
  ('17',  'Police / Gendarmerie'),
  ('18',  'Pompiers — secours en montagne'),
  ('112', 'Numéro d\'urgence européen (fonctionne sans réseau local)'),
  ('114', 'Numéro d\'urgence pour les sourds et malentendants'),
];
