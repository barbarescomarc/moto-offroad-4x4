import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../models/moto_preset.dart';
import '../../models/rider_profile.dart';
import '../../providers/settings_provider.dart';
import '../../providers/fuel_provider.dart';

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
            _riderSection(),
            const SizedBox(height: 24),
            _levelSection(),
            const SizedBox(height: 24),
            _motoSection(),
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

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(
    fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5));
}
