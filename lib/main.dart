import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
import 'providers/rides_provider.dart';
import 'providers/quick_reply_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/guidance_provider.dart';
import 'services/ride_database.dart';
import 'services/ride_repository.dart';
import 'services/ride_recording_service.dart';
import 'services/auto_reply_service.dart';
import 'services/auto_reply_policy.dart';
import 'services/call_bridge.dart';
import 'services/location_service.dart';

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
        Provider<RideRepository>.value(value: rideRepository),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => TraceProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => FuelProvider()),
        ChangeNotifierProvider(create: (_) {
          final s = SoloProvider();
          s.loadContacts();
          return s;
        }),
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
        ChangeNotifierProvider(
          create: (_) => RidesProvider(repository: rideRepository),
        ),
        ChangeNotifierProvider(create: (_) {
          final q = QuickReplyProvider();
          q.load();
          return q;
        }),
        ChangeNotifierProvider(create: (_) {
          final f = FavoritesProvider();
          f.load();
          return f;
        }),
        ChangeNotifierProvider(create: (_) => GuidanceProvider()),
      ],
      child: _AutoReplyHost(
        child: MaterialApp.router(
          title: 'Moto Offroad 4x4',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}

// ── Cycle de vie du service d'auto-réponse ───────────────────
//
// Point d'entrée unique : démarre l'écoute des appels au lancement de
// l'application et l'arrête proprement à la fermeture. Les providers sont
// capturés une seule fois ici — leurs instances sont stables pour toute la
// vie de l'app — mais leurs accesseurs sont relus à chaque appel entrant via
// les fonctions passées au service, pour ne jamais figer un réglage.
class _AutoReplyHost extends StatefulWidget {
  const _AutoReplyHost({required this.child});

  final Widget child;

  @override
  State<_AutoReplyHost> createState() => _AutoReplyHostState();
}

class _AutoReplyHostState extends State<_AutoReplyHost> {
  late final AutoReplyService _service;

  @override
  void initState() {
    super.initState();

    final settings = context.read<SettingsProvider>();
    final recording = context.read<RecordingProvider>();
    final solo = context.read<SoloProvider>();
    final quickReplies = context.read<QuickReplyProvider>();

    _service = AutoReplyService(
      bridge: CallBridge(),
      policyBuilder: () => AutoReplyPolicy(
        enabled:       settings.autoReplyEnabled,
        allCallers:    settings.autoReplyAllCallers,
        riding:        recording.isRecording || solo.soloActive,
        trustedPhones: solo.contacts.map((c) => c.phone).toList(),
      ),
      messageBuilder:        () => settings.autoReplyMessage,
      attachPositionBuilder: () => settings.autoReplyAttachPosition,
      repliesBuilder:        () => quickReplies.replies,
      positionProvider:      () => LocationService().getCurrentPosition(),
    )..start();
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
