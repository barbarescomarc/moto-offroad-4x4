import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:go_router/go_router.dart';
import 'app/theme.dart';
import 'app/router.dart';
import 'providers/map_provider.dart';
import 'providers/trace_provider.dart';
import 'providers/group_provider.dart';
import 'providers/fuel_provider.dart';
import 'providers/solo_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/rides_provider.dart';
import 'providers/quick_reply_provider.dart';
import 'services/ride_database.dart';
import 'services/ride_repository.dart';
import 'services/ride_recording_service.dart';
import 'services/auto_reply_service.dart';
import 'services/auto_reply_policy.dart';
import 'services/alert_channel_unlock.dart';
import 'services/call_bridge.dart';
import 'services/fall_alert_service.dart';
import 'services/fall_detector.dart';
import 'services/fall_thresholds.dart';
import 'services/location_service.dart';
import 'services/tracker_api_client.dart';
import 'services/position_uplink_service.dart';
import 'services/vibration_calibration.dart';

// Références mutables lues par les fermetures de FallAlertService : le
// service ne change jamais d'identité (ProxyProvider2 renvoie toujours la
// même instance), seul ce qu'il lit doit rester à jour. Mises à jour par le
// callback `update` du ProxyProvider à chaque notification de
// SettingsProvider/SoloProvider — pas de BuildContext à conserver ici.
SettingsProvider? _fallSettingsRef;
SoloProvider? _fallSoloRef;

// Garde de ré-entrance : un second choc qualifiant pendant qu'un écran
// d'alerte est déjà affiché (ou en cours d'ouverture) ne doit pas empiler un
// second FallCountdownScreen ni redéclencher un SMS aux contacts de
// confiance. Simple drapeau top-level (pas un Provider) : posé juste avant
// le push, relâché par `.whenComplete()` quand la route est dépilée, que le
// compte à rebours ait été annulé ou soit allé à son terme.
bool _fallAlertInFlight = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        Provider<AlertChannelUnlock>(create: (_) => AlertChannelUnlock()),
        ProxyProvider2<SettingsProvider, SoloProvider, FallAlertService>(
          create: (_) => FallAlertService(
            sendSms: CallBridge().sendSms,
            sendServerAlert: ({required kind}) async {
              final solo = _fallSoloRef;
              if (solo == null || solo.sessionId == null || solo.deviceKey == null || solo.memberId == null) {
                return false;
              }
              return TrackerApiClient().sendAlert(
                sessionId: solo.sessionId!, deviceKey: solo.deviceKey!, memberId: solo.memberId!, kind: kind,
              );
            },
            phoneChannelEnabled: () => _fallSettingsRef?.alertChannelPhone ?? true,
            serverChannelEnabled: () => _fallSettingsRef?.alertChannelServer ?? true,
            trustedContacts: () => _fallSoloRef?.contacts ?? [],
            positionProvider: () => LocationService().getCurrentPosition(),
          ),
          update: (_, settings, solo, previous) {
            _fallSettingsRef = settings;
            _fallSoloRef = solo;
            return previous!;
          },
        ),
      ],
      child: _AutoReplyHost(
        child: _SoloUplinkHost(
          child: _FallDetectionHost(
            child: MaterialApp.router(
              title: 'Moto Offroad 4x4',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              routerConfig: appRouter,
            ),
          ),
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

// ── Cycle de vie de l'envoi de position en mode Solo ─────────
class _SoloUplinkHost extends StatefulWidget {
  const _SoloUplinkHost({required this.child});
  final Widget child;

  @override
  State<_SoloUplinkHost> createState() => _SoloUplinkHostState();
}

class _SoloUplinkHostState extends State<_SoloUplinkHost> {
  final _uplink = PositionUplinkService(sendPositions: TrackerApiClient().sendPositions);
  bool _wasActive = false;
  bool _groupWasActive = false;

  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();
    final group = context.watch<GroupProvider>();

    if (solo.soloActive && !_wasActive) {
      _wasActive = true;
      RideRecordingService().start(
        title: 'Mode Solo Sécurisé actif',
        text: 'Votre position est envoyée à vos contacts de confiance',
      );
      _uplink.start(
        positions: LocationService().stream,
        sessionId: solo.sessionId!,
        deviceKey: solo.deviceKey!,
        memberId: solo.memberId!,
        interval: const Duration(seconds: 5),
      );
    } else if (!solo.soloActive && _wasActive) {
      _wasActive = false;
      _uplink.stop();
    }

    if (group.groupActive && !_groupWasActive) {
      _groupWasActive = true;
      group.startLiveSharing(positions: LocationService().stream);
    } else if (!group.groupActive && _groupWasActive) {
      _groupWasActive = false;
    }

    return widget.child;
  }

  @override
  void dispose() {
    _uplink.stop();
    super.dispose();
  }
}

// ── Cycle de vie de la détection de chute ────────────────────
// Même règle de garde que l'auto-réponse aux appels : actif seulement
// pendant un enregistrement ou en mode Solo, jamais téléphone posé sur
// une table.
class _FallDetectionHost extends StatefulWidget {
  const _FallDetectionHost({required this.child});
  final Widget child;

  @override
  State<_FallDetectionHost> createState() => _FallDetectionHostState();
}

class _FallDetectionHostState extends State<_FallDetectionHost> {
  FallDetector? _detector;
  bool _running = false;
  VibrationCalibration? _lastCalibration;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final recording = context.watch<RecordingProvider>();
    final solo = context.watch<SoloProvider>();

    final shouldRun = settings.fallDetectionEnabled && (recording.isRecording || solo.soloActive);

    if (shouldRun && !_running) {
      _running = true;
      _detector = FallDetector(
        accelerometer: accelerometerEventStream().map((e) => [e.x, e.y, e.z]),
        positions: LocationService().stream,
        shockThreshold: () => shockThresholdMs2(_lastCalibration ?? const VibrationCalibration()),
        idleVibrationLevel: () => _lastCalibration?.idleLevel ?? VibrationCalibration.defaultThreshold,
      );
      VibrationCalibration.load().then((cal) => _lastCalibration = cal);
      _detector!.start(onFallDetected: () {
        if (_fallAlertInFlight) return;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) return;
        _fallAlertInFlight = true;
        GoRouter.of(ctx).push(AppRoutes.fallCountdown).whenComplete(() {
          _fallAlertInFlight = false;
        });
      });
    } else if (!shouldRun && _running) {
      _running = false;
      _detector?.stop();
      _detector = null;
    }

    return widget.child;
  }

  @override
  void dispose() {
    _detector?.stop();
    super.dispose();
  }
}
