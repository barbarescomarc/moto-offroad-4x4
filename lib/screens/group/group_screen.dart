import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/group_provider.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final group = context.watch<GroupProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('👥  GROUPE')),
      body: group.groupActive ? _buildActive(context, group) : _buildInactive(context, group),
    );
  }

  Widget _buildInactive(BuildContext context, GroupProvider group) {
    final nameCtrl = TextEditingController(text: 'Pilote');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A3E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mode groupe — jusqu\'à 10 motos', style: TextStyle(
                  fontFamily: 'Rajdhani', fontSize: 18, fontWeight: FontWeight.w700,
                  color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Partagez votre position, envoyez un point de ralliement et partagez une trace en temps réel.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Votre nom dans le groupe',
                    prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => group.createSession(nameCtrl.text.isEmpty ? 'Pilote' : nameCtrl.text),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('CRÉER UNE SESSION'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(BuildContext context, GroupProvider group) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Code session & invite ────────────────────
          _sessionCard(context, group),
          const SizedBox(height: 12),

          // ── Mon partage de position ──────────────────
          _sharingCard(group),
          const SizedBox(height: 12),

          // ── Actions groupe ───────────────────────────
          _actionsRow(context, group),
          const SizedBox(height: 16),

          // ── Liste membres ────────────────────────────
          Text('MEMBRES (${group.onlineCount}/${GroupProvider.maxMembers})',
            style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 12,
              color: AppColors.textMuted, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          ...group.members.map((m) => _memberTile(m)),
          const SizedBox(height: 24),

          // ── Quitter ──────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: group.leaveGroup,
              icon: const Icon(Icons.exit_to_app, color: AppColors.statusRed),
              label: const Text('Quitter le groupe',
                style: TextStyle(color: AppColors.statusRed)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.red),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(BuildContext context, GroupProvider group) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SESSION ACTIVE', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(group.sessionId ?? '------',
                style: const TextStyle(fontFamily: 'Rajdhani', fontSize: 32,
                  fontWeight: FontWeight.w700, color: AppColors.orange, letterSpacing: 4)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: group.sessionId ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copié'), duration: Duration(seconds: 1)));
                },
              ),
            ],
          ),
          if (group.inviteLink != null) ...[
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: group.inviteLink!)),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2A2A3E)),
                ),
                child: Row(children: [
                  const Icon(Icons.link, color: AppColors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(group.inviteLink!,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.copy, color: AppColors.textMuted, size: 14),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sharingCard(GroupProvider group) {
    final sharing = group.sharingMyPosition;
    return GestureDetector(
      onTap: group.toggleMySharing,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sharing ? AppColors.statusGreen.withOpacity(.08) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sharing ? AppColors.statusGreen.withOpacity(.4) : const Color(0xFF2A2A3E)),
        ),
        child: Row(
          children: [
            Icon(sharing ? Icons.navigation : Icons.navigation_outlined,
              color: sharing ? AppColors.statusGreen : AppColors.textMuted, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sharing ? 'Ma position est visible par le groupe' : 'Position masquée',
                  style: TextStyle(
                    color: sharing ? AppColors.statusGreen : AppColors.textSecondary,
                    fontWeight: FontWeight.w600, fontSize: 13)),
                Text(sharing ? 'Tap pour masquer' : 'Tap pour partager',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            )),
            Switch(
              value: sharing,
              onChanged: (_) => group.toggleMySharing(),
              activeColor: AppColors.statusGreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow(BuildContext context, GroupProvider group) {
    return Row(
      children: [
        Expanded(child: _actionBtn(
          Icons.flag,
          group.rallyPoint != null ? 'Supprimer le\nralliement' : 'Point de\nralliement',
          AppColors.orange,
          () {
            if (group.rallyPoint != null) {
              group.setRallyPoint(null);
            } else {
              // TODO: ouvre la carte pour choisir le point
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tap sur la carte pour choisir le point de ralliement')));
            }
          },
        )),
        const SizedBox(width: 10),
        Expanded(child: _actionBtn(
          Icons.route,
          'Partager\nla trace',
          AppColors.blue,
          () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trace partagée avec le groupe'))),
        )),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600,
                fontFamily: 'Rajdhani')),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(GroupMember m) {
    final color = Color(int.parse('0xFF${m.color.replaceFirst('#', '')}'));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: color,
            child: Text(m.name.isNotEmpty ? m.name[0] : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(
                m.isSharing
                    ? (m.speedKmh != null ? '${m.speedKmh!.toStringAsFixed(0)} km/h' : 'En ligne')
                    : 'Position masquée',
                style: TextStyle(fontSize: 11,
                  color: m.isSharing ? AppColors.statusGreen : AppColors.textMuted)),
            ],
          )),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.isOnline ? AppColors.statusGreen : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

