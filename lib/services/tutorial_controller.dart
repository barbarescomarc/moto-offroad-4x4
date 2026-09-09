import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tutorial_steps.dart';

/// État du tutoriel de première ouverture : quelle étape est affichée, et
/// mémorisation du fait qu'il a déjà été vu (pour ne pas le rejouer à
/// chaque lancement). La tâche 18 (réglages) appelle [replay] pour le
/// revoir volontairement.
class TutorialController extends ChangeNotifier {
  TutorialController({required TutorialTargets targets})
      : _steps = buildTutorialSteps(targets);

  static const String _kDone = 'tutorial_done';

  final List<TutorialStep> _steps;
  bool _visible = false;
  int _index = 0;
  bool _disposed = false;

  bool get visible => _visible;
  int get index => _index;
  int get total => _steps.length;
  TutorialStep get current => _steps[_index];

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Démarre le tutoriel s'il n'a jamais été vu. À appeler à la première
  /// arrivée sur la carte, après le mur d'inscription.
  ///
  /// Appelé sans attendre depuis `initState` (qui ne peut pas être async) :
  /// entre le lancement de cet appel et la résolution de
  /// `SharedPreferences.getInstance()`, l'écran peut déjà avoir été
  /// démonté et le contrôleur libéré — la garde ci-dessous évite un
  /// `notifyListeners()` sur un `ChangeNotifier` déjà disposé (qui lève en
  /// mode debug).
  Future<void> startIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    if (prefs.getBool(_kDone) ?? false) return;
    _index = 0;
    _visible = true;
    notifyListeners();
  }

  /// Passe à l'étape suivante, ou ferme le tutoriel depuis la dernière.
  void next() {
    if (_index >= _steps.length - 1) {
      _close();
      return;
    }
    _index++;
    notifyListeners();
  }

  void previous() {
    if (_index == 0) return;
    _index--;
    notifyListeners();
  }

  Future<void> skip() async => _close();

  /// Relance le tutoriel depuis le début, quel que soit l'état mémorisé.
  Future<void> replay() async {
    _index = 0;
    _visible = true;
    notifyListeners();
  }

  Future<void> _close() async {
    _visible = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDone, true);
  }
}
