import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/map/map_screen.dart';
import '../screens/sos/sos_screen.dart';
import '../screens/solo/solo_screen.dart';
import '../screens/solo/send_position_screen.dart';
import '../screens/fuel/fuel_screen.dart';
import '../screens/group/group_screen.dart';
import '../screens/weather/weather_screen.dart';
import '../screens/rides/rides_screen.dart';
import '../screens/rides/ride_detail_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/vibration_calibration_screen.dart';
import '../screens/settings/call_settings_screen.dart';
import '../screens/sos/fall_countdown_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../services/update_checker.dart';
import '../widgets/glass_control.dart';
import '../widgets/update_tile.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Routes nommées ───────────────────────────────────────────
class AppRoutes {
  static const String map         = '/';
  static const String fuel        = '/fuel';
  static const String rides       = '/rides';
  static const String weather     = '/weather';
  static const String settings    = '/settings';
  static const String calibration = '/calibration';
  static const String callSettings = '/call-settings';
  static const String sos         = '/sos';
  static const String solo        = '/solo';
  static const String sendPosition = '/send-position';
  static const String group       = '/group';
  static const String fallCountdown = '/fall-countdown';
  static const String favorites   = '/favorites';
}

// ── Router GoRouter ──────────────────────────────────────────
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.map,
  debugLogDiagnostics: false,
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.map,
          pageBuilder: (_, __) => const NoTransitionPage(child: MapScreen()),
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
  ],
);

// ── Shell principal avec BottomNavigationBar ─────────────────
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  UpdateInfo? _maj;

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
    if (location.startsWith(AppRoutes.rides)) return 2;
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

    return Scaffold(
      body: Column(
        children: [
          if (maj != null)
            UpdateBanner(
              maj: maj,
              onDismiss: () => setState(() => _maj = null),
            ),
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
