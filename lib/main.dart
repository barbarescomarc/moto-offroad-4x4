import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/theme.dart';
import 'app/router.dart';
import 'config/firebase_options.dart';
import 'providers/map_provider.dart';
import 'providers/trace_provider.dart';
import 'providers/group_provider.dart';
import 'providers/fuel_provider.dart';
import 'providers/solo_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/recording_provider.dart';
import 'services/ride_database.dart';
import 'services/ride_repository.dart';
import 'services/ride_recording_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation Firebase (mode groupe temps réel)
  // ⚠️  Nécessite google-services.json dans android/app/
  // ⚠️  Voir lib/config/firebase_options.dart pour le guide de configuration
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase non configuré — le mode groupe sera désactivé
    debugPrint('Firebase non initialisé : $e');
  }

  // Orientation : portrait + paysage autorisés
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // UI système : overlay sombre (barre de statut transparente)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1A1A2E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Maintenir l'écran allumé par défaut (navigation active)
  WakelockPlus.enable();

  // Base locale des sorties
  final rideRepository = RideRepository(await RideDatabase.open());

  runApp(MotoOffroadApp(rideRepository: rideRepository));
}

class MotoOffroadApp extends StatelessWidget {
  const MotoOffroadApp({super.key, required this.rideRepository});

  final RideRepository rideRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => TraceProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => FuelProvider()),
        ChangeNotifierProvider(create: (_) => SoloProvider()),
        ChangeNotifierProvider(create: (_) {
          final s = SettingsProvider();
          s.load(); // chargement async des préférences persistées
          return s;
        }),
        ChangeNotifierProvider(
          create: (_) => RecordingProvider(
            repository: rideRepository,
            service:    RideRecordingService(),
          ),
        ),
      ],
      child: MaterialApp.router(
        title: 'Moto Offroad 4x4',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: appRouter,
      ),
    );
  }
}
