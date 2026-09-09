import 'package:flutter/widgets.dart';

/// Une étape du tutoriel de première ouverture : un titre, un texte, et
/// éventuellement une cible réelle de l'interface à mettre en surbrillance.
/// [target] est nul pour une étape purement introductive (voir la première
/// étape, qui n'a rien à montrer avant que le rider ne voie l'écran).
class TutorialStep {
  final String title;
  final String body;
  final GlobalKey? target;
  const TutorialStep({required this.title, required this.body, this.target});
}

/// Les cinq éléments réels de la carte que le tutoriel pointe du doigt.
/// Fournis par `MapScreen`, qui pose ces clés sur les widgets correspondants.
class TutorialTargets {
  const TutorialTargets({
    required this.modeSwitch,
    required this.sos,
    required this.recording,
    required this.actions,
    required this.layers,
  });
  final GlobalKey modeSwitch;
  final GlobalKey sos;
  final GlobalKey recording;
  final GlobalKey actions;
  final GlobalKey layers;
}

/// Six étapes, sur le modèle du tutoriel du tableau de bord de streaming
/// (projet DRONE 31) : une par fonction que le rider doit connaître avant
/// sa première sortie.
List<TutorialStep> buildTutorialSteps(TutorialTargets t) => [
      const TutorialStep(
        title: 'Bienvenue sur MOTO OFFROAD',
        body: 'Ce tutoriel te montre les six fonctions essentielles en moins de deux minutes. '
            'Tu pourras le revoir à tout moment depuis les réglages.',
      ),
      TutorialStep(
        title: 'Solo ou Groupe',
        body: 'En Solo, une personne de confiance suit ton trajet en direct et sera prévenue si tu ne donnes plus signe de vie. '
            'En Groupe, tu vois tes coéquipiers sur la carte et tu peux fixer un point de ralliement.',
        target: t.modeSwitch,
      ),
      TutorialStep(
        title: 'SOS et détection de chute',
        body: 'Ce bouton appelle les secours et prévient tes contacts avec ta position. '
            'La détection de chute agit seule : après un choc, un compte à rebours démarre, et sans réaction de ta part l’alerte part.',
        target: t.sos,
      ),
      TutorialStep(
        title: 'Enregistrer ta sortie',
        body: 'Distance, durée, dénivelé et trace complète, même écran éteint. '
            'La sortie se retrouve ensuite dans l’onglet Sorties, et s’exporte en GPX.',
        target: t.recording,
      ),
      TutorialStep(
        title: 'Le menu d’actions',
        body: 'Itinéraire vers une destination, recherche de points d’intérêt — carburant, bivouac, réparateur — et météo du secteur.',
        target: t.actions,
      ),
      TutorialStep(
        title: 'Fonds de carte et hors ligne',
        body: 'Choisis ton fond de carte, et télécharge une zone avant de partir : '
            'sans réseau sur le terrain, seules les tuiles déjà téléchargées s’afficheront.',
        target: t.layers,
      ),
    ];
