import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/aire.dart';
import '../providers/aires_provider.dart';
import '../providers/settings_provider.dart';
import '../services/aires_api_client.dart';

/// La fiche d'une aire de camping-car.
///
/// Sa règle de conduite : ne jamais laisser croire qu'on sait ce qu'on ne
/// sait pas. Un champ vide affiche « Non renseigné » et un bouton pour le
/// compléter, plutôt qu'un tiret muet ou, pire, un zéro. C'est vrai de la
/// majorité des champs — prix, places et surtout hauteur limite manquent sur
/// la plupart des aires — et c'est de là que vient la base.
class AireSheet extends StatelessWidget {
  const AireSheet({
    super.key,
    required this.aire,
    required this.onGuider,
    this.client,
  });

  final AireModel aire;
  final VoidCallback onGuider;
  final AiresApiClient? client;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final passe = aire.passeAvecHauteur(settings.gabaritHauteurM);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚐 ${aire.nomAffiche}', style: const TextStyle(
                fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              )),
              const SizedBox(height: 4),
              const Text('Aire camping-car',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),

              if (passe != null) ...[
                const SizedBox(height: 12),
                _bandeauGabarit(passe, settings.gabaritHauteurM),
              ],

              const SizedBox(height: 16),
              ...ChampAire.values.map((c) => _ligneChamp(context, c)),

              if (!aire.services.estVide) ...[
                const SizedBox(height: 12),
                _services(),
              ],

              if (aire.description != null) ...[
                const SizedBox(height: 14),
                Text(aire.description!, style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 13, height: 1.4)),
              ],

              if (aire.phone != null) ...[
                const SizedBox(height: 12),
                _ligneContact(Icons.phone_outlined, aire.phone!),
              ],
              if (aire.website != null)
                _ligneContact(Icons.language, aire.website!),

              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onGuider,
                  icon: const Icon(Icons.directions),
                  label: const Text('Naviguer vers cette aire'),
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ce que le pilote veut savoir en premier : est-ce que je passe ?
  ///
  /// Une hauteur inconnue n'apparaît pas ici. Écrire « ça passe » faute
  /// d'information serait exactement le mensonge que cette fiche refuse.
  Widget _bandeauGabarit(bool passe, double hauteurM) {
    final couleur = passe ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: couleur),
      ),
      child: Row(children: [
        Icon(passe ? Icons.check_circle_outline : Icons.block, color: couleur, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          passe
              ? 'Ton gabarit passe (${hauteurM.toStringAsFixed(2)} m sous ${aire.maxHeightM} m)'
              : 'Trop haut : ${hauteurM.toStringAsFixed(2)} m pour ${aire.maxHeightM} m',
          style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
        )),
      ]),
    );
  }

  Widget _ligneChamp(BuildContext context, ChampAire champ) {
    final valeur = champ.valeurAffichee(aire);
    final renseigne = valeur != null && valeur.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: Text(champ.libelle,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: renseigne
                ? Text(valeur,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14))
                : Row(children: [
                    const Text('Non renseigné',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13,
                            fontStyle: FontStyle.italic)),
                    const SizedBox(width: 8),
                    InkWell(
                      key: Key('completer-${champ.cleServeur}'),
                      onTap: () => _ouvrirSaisie(context, champ),
                      child: const Text('· compléter',
                          style: TextStyle(color: AppColors.accent, fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _services() {
    final presents = aire.services.presents;
    if (presents.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: presents
          .map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(AireServices.libelles[s] ?? s,
                    style: const TextStyle(color: AppColors.mutedForeground, fontSize: 12)),
              ))
          .toList(),
    );
  }

  Widget _ligneContact(IconData icone, String texte) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(icone, color: AppColors.mutedForeground, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(texte,
              style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13),
              overflow: TextOverflow.ellipsis)),
        ]),
      );

  Future<void> _ouvrirSaisie(BuildContext context, ChampAire champ) async {
    final provider = context.read<AiresProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final saisie = await showDialog<String>(
      context: context,
      builder: (_) => _DialogueReleve(champ: champ),
    );
    if (saisie == null) return;

    final Object valeur = champ.estNumerique ? num.parse(saisie) : saisie;
    try {
      final etat = await (client ?? AiresApiClient()).contribuer(
        aireId: aire.id, champ: champ, valeur: valeur, vuLe: DateTime.now(),
      );
      if (etat == 'retenue') provider.appliquerReleve(aire.id, champ, valeur);
      messenger.showSnackBar(SnackBar(content: Text(
        etat == 'retenue'
            ? 'Merci — l\'info est partie pour tout le monde'
            : 'Merci — en attente d\'un second avis, la valeur en place tient',
      )));
    } on ContributionRefusee catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// La saisie d'un relevé. Volontairement une seule valeur à la fois : un
/// formulaire de huit champs se remplit mal debout à côté d'un camping-car.
class _DialogueReleve extends StatefulWidget {
  const _DialogueReleve({required this.champ});
  final ChampAire champ;

  @override
  State<_DialogueReleve> createState() => _DialogueReleveState();
}

class _DialogueReleveState extends State<_DialogueReleve> {
  final _controleur = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    final saisie = _controleur.text.trim().replaceAll(',', '.');
    if (saisie.isEmpty) {
      setState(() => _erreur = 'Entre une valeur');
      return;
    }
    if (widget.champ.estNumerique && num.tryParse(saisie) == null) {
      setState(() => _erreur = 'Un nombre est attendu');
      return;
    }
    Navigator.pop(context, saisie);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(widget.champ.libelle,
          style: const TextStyle(color: AppColors.foreground, fontFamily: 'Inter')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La franchise du reste du produit : le pilote doit savoir que ce
          // qu'il tape sera vu par les autres avant de le taper.
          const Text('Ce que tu relèves ici servira aux autres camping-caristes.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('saisie-releve'),
            controller: _controleur,
            autofocus: true,
            style: const TextStyle(color: AppColors.foreground),
            keyboardType: widget.champ.estNumerique
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            inputFormatters: widget.champ.estNumerique
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                : null,
            decoration: InputDecoration(
              suffixText: widget.champ.unite,
              errorText: _erreur,
              hintText: widget.champ == ChampAire.maxHeightM ? 'ex. 3.20' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('envoyer-releve'),
          onPressed: _valider,
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}
