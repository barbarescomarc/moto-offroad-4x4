import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/map/map_screen.dart';
import '../screens/sos/sos_screen.dart';
import '../screens/solo/solo_screen.dart';
import '../screens/fuel/fuel_screen.dart';
import '../screens/group/group_screen.dart';
import '../screens/weather/weather_screen.dart';
import '../screens/info/info_screen.dart';
import '../screens/settings/settings_screen.dart';

// ── Routes nommées ───────────────────────────────────────────
class AppRoutes {
  static const String map      = '/';
  static const String fuel     = '/fuel';
  static const String info     = '/info';
  static const String weather  = '/weather';
  static const String settings = '/settings';
  static const String sos      = '/sos';
  static const String solo     = '/solo';
  static const String group    = '/group';
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
          path: AppRoutes.info,
          pageBuilder: (_, __) => const NoTransitionPage(child: InfoScreen()),
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
      path: AppRoutes.sos,
      pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: SosScreen()),
    ),
    GoRoute(
      path: AppRoutes.solo,
      pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: SoloScreen()),
    ),
    GoRoute(
      path: AppRoutes.group,
      pageBuilder: (_, __) => const MaterialPage(fullscreenDialog: true, child: GroupScreen()),
    ),
  ],
);

// ── Shell principal avec BottomNavigationBar ─────────────────
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    switch (location) {
      case AppRoutes.map:      return 0;
      case AppRoutes.fuel:     return 1;
      case AppRoutes.info:     return 2;
      case AppRoutes.weather:  return 3;
      case AppRoutes.settings: return 4;
      default:                 return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex(context),
        onTap: (i) => _onNavTap(context, i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined),              activeIcon: Icon(Icons.map),                 label: 'Carte'),
          BottomNavigationBarItem(icon: Icon(Icons.local_gas_station_outlined), activeIcon: Icon(Icons.local_gas_station),   label: 'Carbu'),
          BottomNavigationBarItem(icon: Icon(Icons.info_outline),              activeIcon: Icon(Icons.info),                label: 'Info'),
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
      case 2: context.go(AppRoutes.info);     break;
      case 3: context.go(AppRoutes.weather);  break;
      case 4: context.go(AppRoutes.settings); break;
    }
  }
}
