import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/map/map_screen.dart';
import '../screens/sos/sos_screen.dart';
import '../screens/solo/solo_screen.dart';
import '../screens/fuel/fuel_screen.dart';
import '../screens/group/group_screen.dart';
import '../screens/weather/weather_screen.dart';

// ── Routes nommées ───────────────────────────────────────────
class AppRoutes {
  static const String map     = '/';
  static const String sos     = '/sos';
  static const String solo    = '/solo';
  static const String fuel    = '/fuel';
  static const String group   = '/group';
  static const String weather = '/weather';
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
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MapScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.fuel,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FuelScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.group,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: GroupScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.weather,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WeatherScreen(),
          ),
        ),
      ],
    ),
    // Modals (pas dans le shell)
    GoRoute(
      path: AppRoutes.sos,
      pageBuilder: (context, state) => MaterialPage(
        fullscreenDialog: true,
        child: const SosScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.solo,
      pageBuilder: (context, state) => MaterialPage(
        fullscreenDialog: true,
        child: const SoloScreen(),
      ),
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
      case AppRoutes.map:     return 0;
      case AppRoutes.fuel:    return 1;
      case AppRoutes.group:   return 2;
      case AppRoutes.weather: return 3;
      default:                return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex(context),
        onTap: (i) {
          switch (i) {
            case 0: context.go(AppRoutes.map);     break;
            case 1: context.go(AppRoutes.fuel);    break;
            case 2: context.go(AppRoutes.group);   break;
            case 3: context.go(AppRoutes.weather); break;
            case 4: context.push(AppRoutes.sos);   break;
            case 5: context.push(AppRoutes.solo);  break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined),              activeIcon: Icon(Icons.map),                label: 'Carte'),
          BottomNavigationBarItem(icon: Icon(Icons.local_gas_station_outlined), activeIcon: Icon(Icons.local_gas_station),  label: 'Carbu'),
          BottomNavigationBarItem(icon: Icon(Icons.group_outlined),            activeIcon: Icon(Icons.group),              label: 'Groupe'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud_outlined),            activeIcon: Icon(Icons.cloud),              label: 'Météo'),
          BottomNavigationBarItem(icon: Icon(Icons.emergency_outlined),        activeIcon: Icon(Icons.emergency),          label: 'SOS'),
          BottomNavigationBarItem(icon: Icon(Icons.shield_outlined),           activeIcon: Icon(Icons.shield),             label: 'Solo'),
        ],
      ),
    );
  }
}
