import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../models/quick_reply.dart';
import '../../providers/quick_reply_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/call_bridge.dart';

class CallSettingsScreen extends StatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  State<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<CallSettingsScreen> {
  bool _granted = true;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final granted = await CallBridge().hasPermissions();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _askPermissions() async {
    await CallBridge().requestPermissions();
    await _refreshPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final replies  = context.watch<QuickReplyProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('Appels et position')),
      body: ListView(
        children: [
          if (!_granted) _permissionBanner(),
          _sectionLabel('AUTO-RÉPONSE'),
          SwitchListTile(
            title: const Text('Répondre automatiquement aux appels',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Uniquement pendant un enregistrement ou en mode Solo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyEnabled,
            onChanged: _granted ? settings.setAutoReplyEnabled : null,
          ),
          ListTile(
            enabled: _granted,
            title: const Text('Message envoyé',
              style: TextStyle(color: Colors.white)),
            subtitle: Text(settings.autoReplyMessage,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.edit, color: AppColors.textMuted),
            onTap: _granted
                ? () => _editText(
                      title: 'Message envoyé',
                      initial: settings.autoReplyMessage,
                      onSave: settings.setAutoReplyMessage,
                    )
                : null,
          ),
          SwitchListTile(
            title: const Text('Joindre ma position',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text('Ajoute les coordonnées et le lien Google Maps',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyAttachPosition,
            onChanged: _granted ? settings.setAutoReplyAttachPosition : null,
          ),
          SwitchListTile(
            title: const Text('Répondre à tous les appelants',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Sinon, seuls vos contacts de confiance reçoivent une réponse',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: settings.autoReplyAllCallers,
            onChanged: _granted ? settings.setAutoReplyAllCallers : null,
          ),
          const Divider(color: Color(0xFF2A2A3E)),
          _sectionLabel('RÉPONSES RAPIDES (3 maximum)'),
          ...replies.replies.map((r) => _replyTile(r, replies)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: replies.resetToDefaults,
              child: const Text('Rétablir les réponses par défaut'),
            ),
          ),
          const Divider(color: Color(0xFF2A2A3E)),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Envoyer ma position',
              style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Transmet vos coordonnées GPS par SMS à un contact de confiance',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.sendPosition),
          ),
        ],
      ),
    );
  }

  Widget _permissionBanner() => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.red.withOpacity(.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.red),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Permissions manquantes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          "Sans l'accès au téléphone, au journal d'appels et aux SMS, "
          "l'auto-réponse ne peut pas fonctionner.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _askPermissions,
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );

  Widget _replyTile(QuickReply reply, QuickReplyProvider provider) => ListTile(
    title: Text(reply.text, style: const TextStyle(color: Colors.white)),
    subtitle: Text(
      reply.attachPosition ? 'Position jointe' : 'Sans position',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    trailing: Switch(
      value: reply.attachPosition,
      onChanged: (v) => provider.updateReply(reply.id, attachPosition: v),
    ),
    onTap: () => _editText(
      title: 'Réponse rapide',
      initial: reply.text,
      onSave: (v) => provider.updateReply(reply.id, text: v),
    ),
  );

  Future<void> _editText({
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 160,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) await onSave(saved);
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: const TextStyle(
      color: AppColors.textMuted, fontSize: 12,
      fontWeight: FontWeight.w700, letterSpacing: 1)),
  );
}
