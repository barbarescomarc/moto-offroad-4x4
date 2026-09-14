import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../models/moto_preset.dart';
import '../../models/vehicle_kind.dart';
import '../../models/rider_profile.dart';
import '../../providers/account_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/fuel_provider.dart';
import '../../services/alert_channel_unlock.dart';
import '../../services/call_bridge.dart';
import '../../services/tracker_api_client.dart';
import '../../widgets/glass_control.dart';
import '../../widgets/update_tile.dart';
import '../../widgets/map_cache_tile.dart';
import '../info/info_screen.dart';
import 'legal_links_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pilotEmailCtrl;
  bool? _smsPermissionGranted;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: MotoCategory.values.length, vsync: this);
    _nameCtrl = TextEditingController(
      text: context.read<SettingsProvider>().riderName,
    );
    _pilotEmailCtrl = TextEditingController(
      text: context.read<SettingsProvider>().pilotEmail,
    );
    if (Platform.isAndroid) {
      CallBridge().hasPermissions().then((v) {
        if (mounted) setState(() => _smsPermissionGranted = v);
      });
    }
  }

  Future<void> _requestSmsPermission() async {
    await CallBridge().requestPermissions();
    final granted = await CallBridge().hasPermissions();
    if (mounted) setState(() => _smsPermissionGranted = granted);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _pilotEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('⚙️  RÉGLAGES')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassPanel(child: _accountSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _vehicleSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _riderSection()),
            const SizedBox(height: 16),
            // Niveau et modele ne decrivent qu'un pilote de moto : les
            // afficher pour un camping-car demanderait de repondre a des
            // questions sans objet.
            if (context.watch<SettingsProvider>().vehicleKind.usesMotoProfile) ...[
              GlassPanel(child: _levelSection()),
              const SizedBox(height: 16),
              GlassPanel(child: _motoSection()),
              const SizedBox(height: 16),
            ],
            if (context.watch<SettingsProvider>().vehicleKind.hasGabarit) ...[
              GlassPanel(child: _gabaritSection()),
              const SizedBox(height: 16),
            ],
            GlassPanel(child: _recordingSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _fallDetectionSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _guidanceSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _appSection()),
            const SizedBox(height: 16),
            const GlassPanel(child: LegalLinksSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _infoSection()),
          ],
        ),
      ),
    );
  }

  // ── Compte rider ───────────────────────────────────────────
  Widget _accountSection(BuildContext context) {
    final compte = context.watch<AccountProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('COMPTE'),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('entree-mon-compte'),
          leading: const Icon(Icons.account_circle_outlined, color: AppColors.textMuted),
          title: Text(compte.email ?? 'Mon compte',
            style: const TextStyle(color: Colors.white)),
          subtitle: const Text('Se déconnecter, supprimer le compte, revoir le tutoriel',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          contentPadding: EdgeInsets.zero,
          onTap: () => context.push(AppRoutes.account),
        ),
      ],
    );
  }

  // ── Nom du pilote ──────────────────────────────────────────
  Widget _riderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('PILOTE'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Nom / pseudo',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onSubmitted:      (v) => _saveName(v),
          onEditingComplete: ()  => _saveName(_nameCtrl.text),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pilotEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'E-mail (obligatoire pour le mode Solo)',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted),
          ),
          onChanged: (v) => context.read<SettingsProvider>().setPilotEmail(v),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: context.watch<SettingsProvider>().pilotNewsletterOptIn,
          onChanged: (v) async {
            final enabled = v ?? false;
            await context.read<SettingsProvider>().setPilotNewsletterOptIn(enabled);
            final email = context.read<SettingsProvider>().pilotEmail;
            if (email.isEmpty) return; // rien à (dés)inscrire sans e-mail pilote
            if (enabled) {
              await TrackerApiClient().subscribeNewsletter(email: email, source: 'pilot');
            } else {
              await TrackerApiClient().unsubscribeNewsletter(email: email);
            }
          },
          title: const Text('Recevoir les nouvelles de GO FREE',
            style: TextStyle(color: Colors.white, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.orange,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  void _saveName(String name) {
    context.read<SettingsProvider>().setRiderName(name);
    if (name.trim().toLowerCase() == 'jhon' || name.trim().toLowerCase() == 'john') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          '💊 Pensez à prendre une dose de Testicouille par jour !',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: Color(0xFF6A1B9A),
        duration: Duration(seconds: 5),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ));
    }
  }

  // ── Niveau pilote ──────────────────────────────────────────
  // ── Choix du véhicule ──────────────────────────────────────

  Widget _vehicleSection() {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('MON VÉHICULE'),
        const SizedBox(height: 12),
        Row(
          children: VehicleKind.values
              .map((v) => Expanded(child: _vehicleCard(v, settings)))
              .toList(),
        ),
        const SizedBox(height: 10),
        Text(
          settings.vehicleKind.hasGabarit
              ? 'Les aires, la vidange, l\'eau et les bornes remplacent le réparateur moto autour de toi.'
              : 'Les stations-service et les réparateurs s\'affichent autour de toi.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        // Le réglage n'a de sens que pour le camping-car : les deux autres
        // véhicules vont déjà sur la piste sans avoir à le demander.
        if (settings.vehicleKind.hasGabarit) _horsRouteInterrupteur(settings),
      ],
    );
  }

  /// La piste, pour les fourgons 4x4 qui la pratiquent vraiment.
  ///
  /// Le sous-titre annonce la contrepartie plutôt que de la laisser
  /// découvrir en route : sur piste, ORS n'accepte plus le profil poids
  /// lourd, donc plus les restrictions de hauteur. Le pilote qui ouvre cet
  /// interrupteur doit savoir ce qu'il échange.
  Widget _horsRouteInterrupteur(SettingsProvider settings) {
    return SwitchListTile(
      key: const Key('van-hors-route'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Autoriser les pistes'),
      subtitle: Text(
        settings.vanToutTerrain
            ? 'Mode Offroad ouvert. Sur piste, la hauteur et le tonnage ne '
              'sont plus pris en compte dans l\'itinéraire.'
            : 'Pour les fourgons 4x4. Sans ça, le guidage reste sur les '
              'routes ouvertes, hauteur et tonnage respectés.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      value: settings.vanToutTerrain,
      onChanged: settings.setVanToutTerrain,
    );
  }

  Widget _vehicleCard(VehicleKind kind, SettingsProvider settings) {
    final active = settings.vehicleKind == kind;
    return GestureDetector(
      key: Key('vehicule-${kind.name}'),
      onTap: () => settings.setVehicleKind(kind),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color:        active ? AppColors.orange.withValues(alpha: .15) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
            color: active ? AppColors.orange : const Color(0xFF2A2A3E),
          ),
        ),
        child: Column(
          children: [
            Icon(kind.icon,
                color: active ? AppColors.orange : AppColors.textSecondary, size: 24),
            const SizedBox(height: 6),
            Text(
              kind.shortLabel,
              style: TextStyle(
                color:      active ? AppColors.orange : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                fontSize:   12,
                fontFamily: 'Rajdhani',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Gabarit du camping-car ─────────────────────────────────

  Widget _gabaritSection() {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('MON GABARIT'),
        const SizedBox(height: 6),
        const Text(
          'Ce qui t\'arrête : une barre de hauteur, un pont, un tonnage. '
          'Relève les valeurs sur la carte grise, pas sur la brochure. '
          'Le guidage écarte les routes qui ne passent pas.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        // La meme franchise que le reste du produit : l'evitement vaut ce que
        // vaut la cartographie. Mieux vaut que le pilote le sache aux reglages
        // qu'au pied du pont.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Seuls les obstacles relevés dans OpenStreetMap peuvent être '
                'évités. Un pont bas non cartographié ne le sera pas : ces '
                'valeurs aident, elles ne remplacent pas les panneaux.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.35),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _gabaritCurseur(
          cle: 'gabarit-hauteur',
          libelle: 'Hauteur',
          valeur: settings.gabaritHauteurM,
          min: 1.5, max: 4.5, pas: 0.05, unite: 'm',
          onChange: (v) => settings.setGabarit(hauteurM: v),
        ),
        _gabaritCurseur(
          cle: 'gabarit-longueur',
          libelle: 'Longueur',
          valeur: settings.gabaritLongueurM,
          min: 3.0, max: 12.0, pas: 0.1, unite: 'm',
          onChange: (v) => settings.setGabarit(longueurM: v),
        ),
        _gabaritCurseur(
          cle: 'gabarit-poids',
          libelle: 'Poids total',
          valeur: settings.gabaritPoidsT,
          min: 1.0, max: 19.0, pas: 0.1, unite: 't',
          onChange: (v) => settings.setGabarit(poidsT: v),
        ),
      ],
    );
  }

  Widget _gabaritCurseur({
    required String cle,
    required String libelle,
    required double valeur,
    required double min,
    required double max,
    required double pas,
    required String unite,
    required ValueChanged<double> onChange,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(libelle,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            key: Key(cle),
            value: valeur.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / pas).round(),
            activeColor: AppColors.orange,
            onChanged: onChange,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${valeur.toStringAsFixed(unite == 't' ? 1 : 2)} $unite',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _levelSection() {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('NIVEAU PILOTE'),
        const SizedBox(height: 12),
        Row(
          children: SkillLevel.values
              .map((l) => Expanded(child: _levelCard(l, settings)))
              .toList(),
        ),
      ],
    );
  }

  Widget _levelCard(SkillLevel level, SettingsProvider settings) {
    final active = settings.skillLevel == level;
    final color  = Color(level.color);
    return GestureDetector(
      onTap: () => settings.setSkillLevel(level),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:        active ? color.withValues(alpha: .15) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: active ? color : const Color(0xFF2A2A3E)),
        ),
        child: Column(
          children: [
            Icon(_levelIcon(level), color: active ? color : AppColors.textSecondary, size: 24),
            const SizedBox(height: 6),
            Text(
              level.label,
              style: TextStyle(
                color:      active ? color : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                fontSize:   12,
                fontFamily: 'Rajdhani',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _levelIcon(SkillLevel l) {
    switch (l) {
      case SkillLevel.debutant:  return Icons.looks_one_outlined;
      case SkillLevel.confirme:  return Icons.looks_two_outlined;
      case SkillLevel.expert:    return Icons.looks_3_outlined;
    }
  }

  // ── Sélection moto ─────────────────────────────────────────
  Widget _motoSection() {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('MA MOTO'),
        const SizedBox(height: 8),
        if (settings.moto != null) _selectedMotoCard(settings.moto!),
        const SizedBox(height: 12),
        _motoCategoryTabs(settings),
      ],
    );
  }

  Widget _selectedMotoCard(MotoPreset moto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        AppColors.orange.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: AppColors.orange.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(moto.category.icon, color: AppColors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(moto.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                  '${moto.consumptionL100.toStringAsFixed(1)} L/100 km · Réservoir ${moto.tankLiters.toStringAsFixed(0)} L',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _motoCategoryTabs(SettingsProvider settings) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: MotoCategory.values
              .map((c) => Tab(icon: Icon(c.icon, size: 18), text: c.label))
              .toList(),
          labelColor:         AppColors.orange,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor:     AppColors.orange,
          labelStyle: const TextStyle(fontSize: 11, fontFamily: 'Rajdhani'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: TabBarView(
            controller: _tabs,
            children: MotoCategory.values
                .map((c) => _motoList(c, settings))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _motoList(MotoCategory cat, SettingsProvider settings) {
    final motos = kMotoPresets.where((m) => m.category == cat).toList();
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: motos.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A3E), height: 1),
      itemBuilder: (ctx, i) => _motoTile(motos[i], settings),
    );
  }

  Widget _motoTile(MotoPreset moto, SettingsProvider settings) {
    final active = settings.moto?.name == moto.name;
    return ListTile(
      dense:       true,
      selected:    active,
      selectedColor: AppColors.orange,
      title: Text(moto.name,
        style: TextStyle(
          color:      active ? AppColors.orange : Colors.white,
          fontSize:   13,
          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '${moto.consumptionL100.toStringAsFixed(1)} L/100 · ${moto.tankLiters.toStringAsFixed(0)} L',
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      trailing: active ? const Icon(Icons.check_circle, color: AppColors.orange, size: 18) : null,
      onTap: () => _applyMotoPreset(moto, settings),
    );
  }

  void _applyMotoPreset(MotoPreset moto, SettingsProvider settings) {
    settings.selectMoto(moto);
    // Synchronise les valeurs réservoir + conso dans FuelProvider
    final fuel = context.read<FuelProvider>();
    fuel.setTank(moto.tankLiters);
    fuel.setConsumption(moto.consumptionL100);
    fuel.setCurrentFuel(moto.tankLiters); // plein par défaut
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${moto.name} sélectionné — réglages carbu mis à jour'),
      backgroundColor: AppColors.bgCard,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Section Enregistrement ──────────────────────────────────
  Widget _recordingSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('ENREGISTREMENT'),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Pause automatique'),
          subtitle: const Text(
              'Suspend l\'enregistrement à l\'arrêt, moteur coupé.'),
          value: settings.autoPauseEnabled,
          onChanged: settings.setAutoPauseEnabled,
        ),
        ListTile(
          title: const Text('Seuil de la pause automatique'),
          subtitle: Text('Vitesse en dessous de laquelle on considère que '
              '${settings.vehicleKind.avecArticle} est '
              'arrêté${settings.vehicleKind.accordePasse}.'),
          trailing: DropdownButton<int>(
            value: settings.pauseSpeedKmh,
            items: SettingsProvider.pauseSpeedChoices
                .map((v) => DropdownMenuItem(value: v, child: Text('$v km/h')))
                .toList(),
            onChanged: (v) => v == null ? null : settings.setPauseSpeedKmh(v),
          ),
        ),
        ListTile(
          title: const Text('Coupure sur perte de signal'),
          subtitle: const Text('Sans GPS plus longtemps que cette durée, la '
              'trace est coupée en deux plutôt que de traverser la forêt en '
              'ligne droite. La fusion est proposée à l\'arrêt.'),
          trailing: DropdownButton<int>(
            value: settings.signalGapSeconds,
            items: SettingsProvider.signalGapChoices
                .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(v < 120 ? '$v s' : '${v ~/ 60} min')))
                .toList(),
            onChanged: (v) =>
                v == null ? null : settings.setSignalGapSeconds(v),
          ),
        ),
        SwitchListTile(
          title: const Text('Demander le nom à l\'arrêt'),
          subtitle: const Text('Sinon, un nom automatique est donné, '
              'modifiable depuis l\'onglet Sorties.'),
          value: settings.askNameOnStop,
          onChanged: settings.setAskNameOnStop,
        ),
        SwitchListTile(
          title: const Text('Proposer de démarrer l\'enregistrement'),
          subtitle: const Text('Quand l\'application détecte un roulage.'),
          value: settings.suggestAutoStart,
          onChanged: settings.setSuggestAutoStart,
        ),
        SwitchListTile(
          title: const Text('Garder l\'écran allumé sur la carte'),
          subtitle: const Text('Pour le guidage, téléphone sur le guidon.'),
          value: settings.keepScreenOnMap,
          onChanged: settings.setKeepScreenOnMap,
        ),
        SwitchListTile(
          title: const Text('Masquer la barre en bas pendant la conduite'),
          subtitle: const Text('Disparaît quand vous déplacez la carte, revient '
              'd\'un toucher près du bord.'),
          value: settings.autoHideNavBar,
          onChanged: settings.setAutoHideNavBar,
        ),
        SwitchListTile(
          title: const Text('Afficher les distances en miles'),
          value: settings.useMiles,
          onChanged: settings.setUseMiles,
        ),
        ListTile(
          leading: const Icon(Icons.vibration),
          title: const Text('Calibrer les vibrations'),
          subtitle: const Text('20 secondes, pour une pause automatique '
              'fiable sur votre moto.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.calibration),
        ),
        // Auto-réponse et réponses rapides reposent sur des API réservées à
        // Android : l'écran n'a rien à proposer ailleurs.
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.phone_callback, color: AppColors.textMuted),
            title: const Text('Appels et position',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text('Auto-réponse SMS, réponses rapides',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => context.push(AppRoutes.callSettings),
          ),
        // Seul chemin vers l'écran Mode Solo : le badge de la carte ne
        // s'affiche que si le mode est déjà actif, il ne peut donc pas
        // servir à l'activer la première fois.
        ListTile(
          leading: const Icon(Icons.shield_outlined, color: AppColors.textMuted),
          title: const Text('Mode Solo Sécurisé',
            style: TextStyle(color: Colors.white)),
          subtitle: const Text('Contacts de confiance, suivi de trajet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          onTap: () => context.push(AppRoutes.solo),
        ),
      ],
    );
  }

  // ── Section Détection de chute ───────────────────────────────
  Widget _fallDetectionSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final unlock = context.read<AlertChannelUnlock>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('DÉTECTION DE CHUTE'),
        const SizedBox(height: 8),
        SwitchListTile(
          value: settings.fallDetectionEnabled,
          onChanged: (v) => settings.setFallDetectionEnabled(v),
          title: const Text('Activer la détection de chute', style: TextStyle(color: Colors.white, fontSize: 14)),
          activeColor: AppColors.orange,
          contentPadding: EdgeInsets.zero,
        ),
        if (settings.fallDetectionEnabled) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Compte à rebours avant alerte', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text('${settings.fallCountdownSeconds} s', style: const TextStyle(
                color: AppColors.orange, fontWeight: FontWeight.w700, fontFamily: 'Rajdhani', fontSize: 16)),
            ],
          ),
          Slider(
            value: settings.fallCountdownSeconds.toDouble(),
            min: 15, max: 120, divisions: 21,
            activeColor: AppColors.orange,
            onChanged: (v) => settings.setFallCountdownSeconds(v.round()),
          ),
          const SizedBox(height: 8),
          const Text('CANAUX D\'ALERTE', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5)),
          // iOS n'autorise aucune application tierce à envoyer un SMS par
          // programme : le canal y est fermé côté chaîne d'alerte, on ne
          // propose pas un réglage sans effet.
          if (Platform.isAndroid) ...[
            SwitchListTile(
              value: settings.alertChannelPhone,
              onChanged: (v) => settings.setAlertChannelPhone(v),
              title: const Text('SMS depuis le téléphone', style: TextStyle(color: Colors.white, fontSize: 14)),
              activeColor: AppColors.statusGreen,
              contentPadding: EdgeInsets.zero,
            ),
            if (settings.alertChannelPhone) _smsPermissionRow(),
          ],
          SwitchListTile(
            value: settings.alertChannelServer,
            onChanged: (v) => settings.setAlertChannelServer(v),
            title: const Text('E-mail depuis le serveur', style: TextStyle(color: Colors.white, fontSize: 14)),
            activeColor: AppColors.statusGreen,
            contentPadding: EdgeInsets.zero,
          ),
          IgnorePointer(
            child: SwitchListTile(
              value: unlock.isUnlocked('sms_gateway'),
              onChanged: null,
              secondary: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 18),
              title: const Text('SMS via passerelle', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              subtitle: const Text('Abonnement bientôt disponible',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          IgnorePointer(
            child: SwitchListTile(
              value: unlock.isUnlocked('voice_call'),
              onChanged: null,
              secondary: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 18),
              title: const Text('Appel vocal automatique', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              subtitle: const Text('Abonnement bientôt disponible',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }

  Widget _smsPermissionRow() {
    if (_smsPermissionGranted == null) return const SizedBox.shrink();
    if (_smsPermissionGranted == true) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.statusGreen, size: 14),
            SizedBox(width: 6),
            Text('SMS autorisé', style: TextStyle(color: AppColors.statusGreen, fontSize: 11)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 16),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Permission SMS non accordée — les alertes par SMS ne partiront pas.',
              style: TextStyle(color: AppColors.orange, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: _requestSmsPermission,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.orange,
            ),
            child: const Text('Autoriser', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Section Guidage GPS ────────────────────────────────────
  Widget _guidanceSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('GUIDAGE GPS'),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Éviter les autoroutes'),
          subtitle: const Text('En mode Route.'),
          value: settings.guidanceAvoidHighways,
          onChanged: settings.setGuidanceAvoidHighways,
        ),
        SwitchListTile(
          title: const Text('Éviter les péages'),
          value: settings.guidanceAvoidTolls,
          onChanged: settings.setGuidanceAvoidTolls,
        ),
        SwitchListTile(
          title: const Text('Éviter les ferries'),
          value: settings.guidanceAvoidFerries,
          onChanged: settings.setGuidanceAvoidFerries,
        ),
        SwitchListTile(
          title: const Text('Privilégier les routes sinueuses'),
          subtitle: const Text(
            'Vers une destination : retient la plus sinueuse parmi plusieurs itinéraires possibles.',
          ),
          value: settings.guidancePreferCurvy,
          onChanged: settings.setGuidancePreferCurvy,
        ),
        SwitchListTile(
          title: const Text('Couper la voix du guidage'),
          subtitle: const Text('Les instructions restent visibles à l\'écran.'),
          value: settings.guidanceVoiceMuted,
          onChanged: settings.setGuidanceVoiceMuted,
        ),
      ],
    );
  }

  // ── Application : version, partage, mise à jour ─────────────
  Widget _appSection() {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('APPLICATION'),
        const UpdateTile(),
        const MapCacheTile(),
        // Outil de depannage : il dit d'ou vient chaque tuile (reseau, cache,
        // erreur) et quel fond est reellement actif. Utile quand la carte se
        // comporte mal ; hors de propos le reste du temps, d'ou l'extinction
        // par defaut.
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text('Diagnostic des tuiles'),
          subtitle: const Text('Affiche sur la carte le fond actif et l\'origine '
              'des tuiles. À n\'activer qu\'en cas de souci d\'affichage.'),
          value: settings.tileDiagnostic,
          onChanged: settings.setTileDiagnostic,
        ),
      ],
    );
  }

  // ── Section Info (repliable) ────────────────────────────────
  Widget _infoSection() {
    return ExpansionTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('INFO'),
      children: const [InfoScreen(embedded: true)],
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(
    fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5));
}
