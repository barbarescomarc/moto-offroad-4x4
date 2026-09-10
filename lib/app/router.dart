import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../app/account_gate.dart';
import '../app/theme.dart';
import '../providers/account_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/account/welcome_screen.dart';
import '../screens/account/register_screen.dart';
import '../screens/account/login_screen.dart';
import '../screens/account/verify_screen.dart';
import '../screens/account/forgot_password_screen.dart';
import '../screens/account/account_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/sos/sos_screen.dart';
import '../screens/solo/solo_screen.dart';
import '../screens/solo/send_position_screen.dart';
import '../screens/fuel/fuel_screen.dart';
import '../screens/group/group_screen.dart';
import '../screens/weather/weather_screen.dart';
import '../screens/rides/rides_screen.dart';
import '../screens/rides/publish_trace_screen.dart';
import '../screens/rides/ride_detail_screen.dart';
import '../screens/rides/shared_trace_detail_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/vibration_calibration_screen.dart';
import '../screens/settings/call_settings_screen.dart';
import '../screens/sos/fall_countdown_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/roadbook/roadbook_screen.dart';
import '../services/account_storage.dart';
import '../services/grace_window.dart';
import '../services/shared_traces_api_client.dart';
import '../services/update_checker.dart';
import '../widgets/account_banner.dart';
import '../widgets/glass_control.dart';
import '../widgets/update_tile.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Routes nommées ───────────────────────────────────────────
class AppRoutes {
  static const String map         = '/';
  static const String fuel        = '/fuel';
  static const String rides       = '/rides';
  static const String traces      = '/traces';
  static const String weather     = '/weather';
  static const String settings    = '/settings';
  static const String calibration = '/calibration';
  static const String callSettings = '/call-settings';
  static const String account      = '/mon-compte';
  static const String sos         = '/sos';
  static const String solo        = '/solo';
  static const String sendPosition = '/send-position';
  static const String group       = '/group';
  static const String fallCountdown = '/fall-countdown';
  static const String favorites   = '/favorites';
  static const String roadbook    = '/roadbook';
  // Écrans du compte (voir account_gate.dart) — hors du ShellRoute : pas de
  // barre de navigation tant que le rider n'a pas franchi ce mur.
  static const String welcome = '/bienvenue';
  static const String register = '/inscription';
  static const String login = '/connexion';
  static const String verify = '/verification';
  static const String forgotPassword = '/mot-de-passe-oublie';
}

// ── Pont vers refreshListenable ──────────────────────────────
//
// GoRouter a besoin d'un `Listenable` dès sa construction, mais le véritable
// `AccountProvider` n'existe qu'une fois l'arbre de widgets monté (il est
// créé par le `MultiProvider` de `main.dart`). Ce pont s'abonne au premier
// `AccountProvider` que `redirect` lui fournit via le `BuildContext` de
// chaque appel, pour que le routeur se réévalue dès que le statut du
// compte change — même sans navigation explicite (ex. fin de `restore()`
// au démarrage).
class _AccountGateBridge extends ChangeNotifier {
  AccountProvider? _source;

  void observe(AccountProvider compte) {
    if (identical(_source, compte)) return;
    _source?.removeListener(notifyListeners);
    _source = compte;
    compte.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _source?.removeListener(notifyListeners);
    super.dispose();
  }
}

// ── Router GoRouter ──────────────────────────────────────────
//
// Fonction plutôt que simple constante : l'application se sert de l'unique
// instance [appRouter], mais les tests ont besoin d'un routeur isolé (voir
// test/app/router_test.dart), sans partager l'état d'un routeur déjà
// parcouru par un test précédent. `initialLocation` n'est paramétrable que
// pour ces tests — l'application ne passe jamais autre chose que la valeur
// par défaut.
GoRouter buildAppRouter({String initialLocation = AppRoutes.map}) {
  final pont = _AccountGateBridge();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    debugLogDiagnostics: false,
    refreshListenable: pont,
    redirect: (context, state) {
      final compte = context.read<AccountProvider>();
      pont.observe(compte);
      return accountRedirect(
        status: compte.status,
        location: state.matchedLocation,
        graceActive: graceWindow.active,
      );
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.map,
            pageBuilder: (_, __) => const NoTransitionPage(child: _MapGate()),
          ),
          GoRoute(
            path: AppRoutes.fuel,
            pageBuilder: (_, __) => const NoTransitionPage(child: FuelScreen()),
          ),
          GoRoute(
            path: AppRoutes.rides,
            pageBuilder: (_, __) => const NoTransitionPage(child: RidesScreen()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => MaterialPage(
                  child: RideDetailScreen(rideId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '${AppRoutes.traces}/:id',
            pageBuilder: (_, state) => MaterialPage(
              child: SharedTraceDetailScreen(
                traceId: state.pathParameters['id']!,
                api: SharedTracesApiClient(readToken: () => AccountStorage().readToken()),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.weather,
            pageBuilder: (_, __) => const NoTransitionPage(child: WeatherScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (_, __) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      // Modals (hors shell)
      GoRoute(
        path: AppRoutes.calibration,
        pageBuilder: (_, __) => const MaterialPage(
            fullscreenDialog: true, child: VibrationCalibrationScreen()),
      ),
      GoRoute(
        path: AppRoutes.callSettings,
        pageBuilder: (_, __) => const MaterialPage(
            fullscreenDialog: true, child: CallSettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.account,
        pageBuilder: (_, __) => const MaterialPage(
            fullscreenDialog: true, child: AccountScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.rides}/:id/publier',
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: PublishTraceScreen(
            rideId: state.pathParameters['id']!,
            api: SharedTracesApiClient(readToken: () => AccountStorage().readToken()),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.sos,
        pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: SosScreen()),
      ),
      GoRoute(
        path: AppRoutes.solo,
        pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: SoloScreen()),
      ),
      GoRoute(
        path: AppRoutes.favorites,
        pageBuilder: (_, __) =>
            const MaterialPage(fullscreenDialog: true, child: FavoritesScreen()),
      ),
      GoRoute(
        path: AppRoutes.roadbook,
        pageBuilder: (_, __) =>
            const MaterialPage(fullscreenDialog: true, child: RoadbookScreen()),
      ),
      GoRoute(
        path: AppRoutes.sendPosition,
        pageBuilder: (_, __) => const MaterialPage(
          fullscreenDialog: true, child: SendPositionScreen()),
      ),
      GoRoute(
        path: AppRoutes.group,
        pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: GroupScreen()),
      ),
      GoRoute(
        path: AppRoutes.fallCountdown,
        pageBuilder: (_, __) => const MaterialPage(
            fullscreenDialog: true, child: FallCountdownScreen()),
      ),
      // Écrans du compte (hors ShellRoute : pas de barre de navigation).
      GoRoute(
        path: AppRoutes.welcome,
        pageBuilder: (_, __) => const NoTransitionPage(child: WelcomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (_, __) => const NoTransitionPage(child: RegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (_, __) => const NoTransitionPage(child: LoginScreen()),
      ),
      GoRoute(
        path: AppRoutes.verify,
        pageBuilder: (_, __) => const NoTransitionPage(child: VerifyScreen()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (_, __) =>
            const NoTransitionPage(child: ForgotPasswordScreen()),
      ),
    ],
  );
}

/// Instance unique utilisée par l'application (voir `main.dart`). Les tests
/// qui ont besoin d'un routeur isolé appellent [buildAppRouter] directement.
final GoRouter appRouter = buildAppRouter();

// ── Garde de chargement du compte, devant la carte ───────────
//
// AccountProvider est un provider `lazy` (voir main.dart) : sa construction,
// et l'appel à `restore()` qu'elle déclenche, n'a lieu qu'au premier
// `redirect` du routeur, et cet appel n'est jamais attendu avant le premier
// rendu. Sans cette garde, `MapScreen` se montait directement pendant ce
// court chargement (accountRedirect rend `null` pour `chargement`, exprès
// pour ne pas transformer cet état en mur) et son `initState` demandait
// aussitôt la permission de localisation — avant même que le mur
// d'inscription ait pu s'appliquer. Mauvaise première impression, et sur
// iOS une demande de permission sans contexte est un motif classique de
// refus en revue App Store.
//
// Neutre et bref : ne dure que le temps de lire le jeton stocké (et, le cas
// échéant, d'interroger `/me`) — un rider hors ligne avec un jeton valide
// arrive normalement sur la carte une fois `restore()` résolu, cet écran ne
// devient pas un second mur.
class _AccountLoadingScreen extends StatelessWidget {
  const _AccountLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('ecran-chargement-compte'),
      backgroundColor: AppColors.bgDark,
      body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
    );
  }
}

/// Bascule entre l'écran neutre ci-dessus et la carte selon l'état du
/// compte. Ne porte aucune autre logique : c'est `MapScreen` qui garde toute
/// la sienne.
class _MapGate extends StatelessWidget {
  const _MapGate();

  @override
  Widget build(BuildContext context) {
    final statut = context.watch<AccountProvider>().status;
    return statut == AccountStatus.chargement ? const _AccountLoadingScreen() : const MapScreen();
  }
}

// ── Shell principal avec BottomNavigationBar ─────────────────
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  UpdateInfo? _maj;

  // Dernier bandeau de compte que le rider a explicitement refermé (voir
  // AccountBanner) : refermable pour la session en cours seulement, jamais
  // persisté — il réapparaît à chaque lancement, comme l'exige le chapitre
  // 7.2 de la spec pour le délai de grâce.
  AccountBannerKind? _bandeauCompteMasque;

  @override
  void initState() {
    super.initState();
    // Au plus une interrogation de GitHub par jour, et jamais bloquante :
    // l'application est distribuée hors magasin, personne ne prévient
    // l'utilisateur à notre place, mais ce n'est pas une urgence.
    WidgetsBinding.instance.addPostFrameCallback((_) => _chercherMaj());
  }

  Future<void> _chercherMaj() async {
    final info = await PackageInfo.fromPlatform();
    final maj = await UpdateChecker.checkIfDue(currentVersion: info.version);
    if (maj != null && mounted) setState(() => _maj = maj);
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(AppRoutes.rides) || location.startsWith(AppRoutes.traces)) return 2;
    switch (location) {
      case AppRoutes.map:      return 0;
      case AppRoutes.fuel:     return 1;
      case AppRoutes.weather:  return 3;
      case AppRoutes.settings: return 4;
      default:                 return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maj      = _maj;
    final mapProv  = context.watch<MapProvider>();
    final settings = context.watch<SettingsProvider>();
    // Masquée seulement si le réglage l'autorise ET qu'un déplacement de
    // carte l'a demandé — désactiver le réglage la rend toujours visible,
    // quel que soit l'état accumulé de MapProvider.
    final hidden = settings.autoHideNavBar && !mapProv.navBarVisible;

    final compte = context.watch<AccountProvider>();
    final bandeauCompte = accountBannerKind(status: compte.status, graceActive: graceWindow.active);
    final afficherBandeauCompte =
        bandeauCompte != AccountBannerKind.aucun && bandeauCompte != _bandeauCompteMasque;

    return Scaffold(
      body: Column(
        children: [
          if (maj != null)
            UpdateBanner(
              maj: maj,
              onDismiss: () => setState(() => _maj = null),
            ),
          if (afficherBandeauCompte) _buildAccountBanner(context, bandeauCompte),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: hidden
            ? _NavBarRevealHandle(key: const ValueKey('handle'), onTap: mapProv.showNavBar)
            : _GlassNavBar(key: const ValueKey('bar'), currentIndex: _currentIndex(context), onTap: (i) => _onNavTap(context, i)),
      ),
    );
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go(AppRoutes.map);      break;
      case 1: context.go(AppRoutes.fuel);     break;
      case 2: context.go(AppRoutes.rides);    break;
      case 3: context.go(AppRoutes.weather);  break;
      case 4: context.go(AppRoutes.settings); break;
    }
  }

  // Un seul mécanisme d'affichage (AccountBanner) pour les deux besoins du
  // lot comptes riders — voir accountBannerKind pour la règle qui choisit
  // lequel montrer, jamais les deux à la fois.
  Widget _buildAccountBanner(BuildContext context, AccountBannerKind bandeau) {
    switch (bandeau) {
      case AccountBannerKind.sessionExpiree:
        return AccountBanner(
          icon: Icons.lock_clock,
          message: 'Ta session a expiré. Reconnecte-toi quand tu le peux — '
              'la carte, le GPS, le SOS et la détection de chute restent disponibles.',
          actionLabel: 'Se reconnecter',
          onAction: () => context.push(AppRoutes.login),
          onDismiss: () => setState(() => _bandeauCompteMasque = bandeau),
        );

      case AccountBannerKind.delaiDeGrace:
        final echeance = graceWindow.deadline;
        final message = echeance == null
            ? 'Un compte sera bientôt nécessaire pour continuer à utiliser l\'application.'
            : 'Un compte sera nécessaire à partir du ${formatGraceDeadline(echeance)}.';
        return AccountBanner(
          icon: Icons.hourglass_bottom,
          message: message,
          actionLabel: 'Créer mon compte',
          onAction: () => context.push(AppRoutes.register),
          onDismiss: () => setState(() => _bandeauCompteMasque = bandeau),
        );

      case AccountBannerKind.aucun:
        return const SizedBox.shrink();
    }
  }
}

// ── Barre de navigation, verre dépoli ────────────────────────
//
// Remplace BottomNavigationBar, dont le style Material ne permet pas la
// translucidité — même matériau que les contrôles flottants de la carte,
// détachée du bord bas comme une barre flottante plutôt que collée dessus.
class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _GlassNavBar({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.map_outlined,               active: Icons.map,               label: 'Carte'),
    (icon: Icons.local_gas_station_outlined, active: Icons.local_gas_station, label: 'Carbu'),
    (icon: Icons.route_outlined,             active: Icons.route,             label: 'Sorties'),
    (icon: Icons.cloud_outlined,             active: Icons.cloud,             label: 'Météo'),
    (icon: Icons.settings_outlined,          active: Icons.settings,          label: 'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: GlassPanel(
          borderRadius: 22,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: _navItem(_items[i], selected: i == currentIndex),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(({IconData icon, IconData active, String label}) item, {required bool selected}) {
    final color = selected ? AppColors.orange : Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(selected ? item.active : item.icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(item.label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Poignée de révélation ────────────────────────────────────
//
// Remplace la barre de navigation quand elle est masquée. Un toucher la fait
// réapparaître sans naviguer : il faut un second geste, sur l'onglet voulu,
// pour changer d'écran — comme sur YouTube ou Google Maps.
class _NavBarRevealHandle extends StatelessWidget {
  final VoidCallback onTap;
  const _NavBarRevealHandle({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 28,
            width: double.infinity,
            child: GlassPanel(
              borderRadius: 12,
              padding: EdgeInsets.zero,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
