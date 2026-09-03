import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../models/moto_preset.dart';
import '../../models/rider_profile.dart';
import '../../providers/settings_provider.dart';
import '../../providers/fuel_provider.dart';
import '../../widgets/glass_control.dart';
import '../../widgets/update_tile.dart';
import '../info/info_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: MotoCategory.values.length, vsync: this);
    _nameCtrl = TextEditingController(
      text: context.read<SettingsProvider>().riderName,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
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
            GlassPanel(child: _riderSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _levelSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _motoSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _recordingSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _guidanceSection(context)),
            const SizedBox(height: 16),
            GlassPanel(child: _appSection()),
            const SizedBox(height: 16),
            GlassPanel(child: _infoSection()),
          ],
        ),
      ),
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
      ],
    );
  }

  void _saveName(String name) {
    context.read<SettingsProvider>().setRiderName(name);
    if (name.trim().toLowerCase() == 'jhon' || name.trim().toLowerCase() == 'john') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('💊 Pensez à prendre une dose de Testicouille par jour !'),
        backgroundColor: Color(0xFF6A1B9A),
        duration: Duration(seconds: 4),
      ));
    }
  }

  // ── Niveau pilote ──────────────────────────────────────────
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
          subtitle: const Text('Vitesse en dessous de laquelle on considère '
              'que la moto est arrêtée.'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('APPLICATION'),
        const UpdateTile(),
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
