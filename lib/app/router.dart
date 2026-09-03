import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
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
import '../services/update_checker.dart';
import '../widgets/update_tile.dart';

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
}

// ── Router GoRouter ──────────────────────────────────────────
final GoRouter appRouter = GoRouter(
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
      path: AppRoutes.sendPosition,
      pageBuilder: (_, __) => const MaterialPage(
        fullscreenDialog: true, child: SendPositionScreen()),
    ),
    GoRoute(
      path: AppRoutes.group,
      pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: GroupScreen()),
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
    final maj = _maj;
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex(context),
        onTap: (i) => _onNavTap(context, i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined),              activeIcon: Icon(Icons.map),                 label: 'Carte'),
          BottomNavigationBarItem(icon: Icon(Icons.local_gas_station_outlined), activeIcon: Icon(Icons.local_gas_station),   label: 'Carbu'),
          BottomNavigationBarItem(icon: Icon(Icons.route_outlined),            activeIcon: Icon(Icons.route),               label: 'Sorties'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud_outlined),            activeIcon: Icon(Icons.cloud),               label: 'Météo'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined),         activeIcon: Icon(Icons.settings),            label: 'Réglages'),
        ],
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
