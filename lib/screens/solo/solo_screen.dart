import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/solo_provider.dart';

class SoloScreen extends StatefulWidget {
  const SoloScreen({super.key});

  @override
  State<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends State<SoloScreen> {
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _relationCtrl = TextEditingController();
  Set<String> _selectedContactIds = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0A),
      appBar: AppBar(
        backgroundColor: AppColors.green,
        title: const Text('🛡️  Mode Solo Sécurisé',
          style: TextStyle(color: Colors.white, fontFamily: 'Rajdhani', fontSize: 20, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Statut actif / inactif ──────────────────
              _statusCard(solo),
              const SizedBox(height: 16),

              // ── Contacts de confiance ───────────────────
              _sectionTitle('CONTACTS DE CONFIANCE (max 3)'),
              const SizedBox(height: 8),
              ...solo.contacts.map((c) => _contactCard(c, solo)),
              if (solo.contacts.length < 3) _addContactBtn(solo),
              const SizedBox(height: 16),

              // ── Seuil d'immobilisation ──────────────────
              _sectionTitle('ALERTE AUTOMATIQUE'),
              const SizedBox(height: 8),
              _immobilitySlider(solo),
              const SizedBox(height: 24),

              // ── Bouton activer / désactiver ─────────────
              solo.soloActive
                  ? _deactivateBtn(solo)
                  : _activateBtn(solo),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(SoloProvider solo) {
    if (!solo.soloActive) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: const Row(children: [
          Icon(Icons.shield_outlined, color: AppColors.textMuted, size: 24),
          SizedBox(width: 12),
          Expanded(child: Text(
            'Mode Solo désactivé — activez-le avant de partir seul',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withOpacity(.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withOpacity(.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.shield, color: AppColors.statusGreen, size: 22),
            SizedBox(width: 8),
            Text('MODE SOLO ACTIF', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.statusGreen, letterSpacing: .5,
            )),
          ]),
          const SizedBox(height: 10),
          // Lien de suivi
          if (solo.trackingUrl != null) ...[
            const Text('Lien de suivi envoyé à vos contacts :', style: TextStyle(
              fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.green.withOpacity(.3)),
              ),
              child: Text(solo.trackingUrl!,
                style: const TextStyle(color: AppColors.statusGreen, fontSize: 12,
                  fontFamily: 'Rajdhani')),
            ),
            const SizedBox(height: 8),
            const Text('⚠️ Le lien est chiffré et expire à la fin de la session',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
          if (solo.sessionStart != null) ...[
            const SizedBox(height: 4),
            Text('Session démarrée à ${_timeLabel(solo.sessionStart!)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _contactCard(TrustedContact contact, SoloProvider solo) {
    final isSelected = _selectedContactIds.contains(contact.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: contact.isNotified
            ? AppColors.green.withOpacity(.08)
            : AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: contact.isNotified
              ? AppColors.green.withOpacity(.4)
              : isSelected ? AppColors.orange.withOpacity(.5)
              : const Color(0xFF2A2A3E),
        ),
      ),
      child: ListTile(
        onTap: solo.soloActive ? null : () {
          setState(() {
            if (isSelected) _selectedContactIds.remove(contact.id);
            else _selectedContactIds.add(contact.id);
          });
        },
        leading: CircleAvatar(
          backgroundColor: AppColors.blue,
          child: Text(contact.name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        title: Text(contact.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text('${contact.relation} · ${contact.phone}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contact.isNotified)
              const Chip(
                label: Text('Notifié', style: TextStyle(fontSize: 10, color: AppColors.statusGreen)),
                backgroundColor: Color(0xFF0D2A0D),
                side: BorderSide(color: AppColors.green),
              )
            else if (!solo.soloActive)
              Checkbox(
                value: isSelected,
                activeColor: AppColors.orange,
                onChanged: (_) {
                  setState(() {
                    if (isSelected) _selectedContactIds.remove(contact.id);
                    else _selectedContactIds.add(contact.id);
                  });
                },
              ),
            if (!solo.soloActive)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
                onPressed: () => solo.removeContact(contact.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addContactBtn(SoloProvider solo) {
    return GestureDetector(
      onTap: () => _showAddContactDialog(solo),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.orange.withOpacity(.3), style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_outlined, color: AppColors.orange, size: 20),
            SizedBox(width: 8),
            Text('Ajouter un contact de confiance',
              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _immobilitySlider(SoloProvider solo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Alerte si immobile depuis', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text('${solo.immobilityThresholdMin} min',
                style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700,
                  fontFamily: 'Rajdhani', fontSize: 18)),
            ],
          ),
          Slider(
            value: solo.immobilityThresholdMin.toDouble(),
            min: 10, max: 60, divisions: 10,
            activeColor: AppColors.orange,
            onChanged: (v) => solo.setImmobilityThreshold(v.round()),
          ),
          const Text('Vos contacts de confiance recevront une alerte automatique si votre GPS n\'a pas bougé pendant ce temps.',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _activateBtn(SoloProvider solo) {
    final hasContacts = solo.contacts.isNotEmpty;
    final hasSelected = _selectedContactIds.isNotEmpty;
    final canActivate = hasContacts && hasSelected;

    return Column(
      children: [
        if (!canActivate && hasContacts)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Sélectionnez au moins un contact à notifier',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center),
          ),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: canActivate
                ? () async {
                    await solo.activate(_selectedContactIds.toList());
                  }
                : null,
            icon: const Icon(Icons.shield, size: 22),
            label: const Text('PARTIR EN MODE SOLO SÉCURISÉ',
              style: TextStyle(fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              disabledBackgroundColor: AppColors.bgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _deactivateBtn(SoloProvider solo) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: () {
          solo.deactivate();
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.stop_circle_outlined, color: AppColors.red),
        label: const Text('DÉSACTIVER — Envoyer SMS d\'arrivée',
          style: TextStyle(fontFamily: 'Rajdhani', fontSize: 15,
            fontWeight: FontWeight.w700, color: AppColors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.red),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  void _showAddContactDialog(SoloProvider solo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        title: const Text('Ajouter un contact', style: TextStyle(color: Colors.white, fontFamily: 'Rajdhani')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _relationCtrl,
              decoration: const InputDecoration(labelText: 'Relation (ex: Conjointe)'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              if (_nameCtrl.text.isNotEmpty && _phoneCtrl.text.isNotEmpty) {
                solo.addContact(
                  name:     _nameCtrl.text,
                  phone:    _phoneCtrl.text,
                  relation: _relationCtrl.text.isNotEmpty ? _relationCtrl.text : 'Contact',
                );
                _nameCtrl.clear();
                _phoneCtrl.clear();
                _relationCtrl.clear();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(
    fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5));

  String _timeLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

