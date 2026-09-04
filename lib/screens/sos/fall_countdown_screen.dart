import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/settings_provider.dart';
import '../../services/fall_alert_service.dart';

class FallCountdownScreen extends StatefulWidget {
  const FallCountdownScreen({super.key});

  @override
  State<FallCountdownScreen> createState() => _FallCountdownScreenState();
}

class _FallCountdownScreenState extends State<FallCountdownScreen> {
  Timer? _tick;
  Timer? _alarm;
  Timer? _autoClose;
  late int _remaining;
  bool _sent = false;
  bool _phoneChannelUsed = false;
  bool _serverChannelUsed = false;

  @override
  void initState() {
    super.initState();
    _remaining = context.read<SettingsProvider>().fallCountdownSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _trigger();
      }
    });
    _alarm = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _alarm?.cancel();
    _autoClose?.cancel();
    super.dispose();
  }

  Future<void> _trigger() async {
    _alarm?.cancel();
    final settings = context.read<SettingsProvider>();
    final service = context.read<FallAlertService>();
    _phoneChannelUsed = settings.alertChannelPhone;
    _serverChannelUsed = settings.alertChannelServer;
    await service.sendFallAlert(kind: 'fall');
    if (!mounted) return;
    setState(() => _sent = true);
    // Filet de sécurité, pas la sortie normale : une personne sonnée ne doit
    // pas être bousculée par un minuteur trop court. Elle peut fermer l'écran
    // d'un geste dès qu'elle est prête ; sinon il se ferme tout seul.
    _autoClose = Timer(const Duration(seconds: 5), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _cancel() {
    HapticFeedback.heavyImpact();
    _tick?.cancel();
    _alarm?.cancel();
    Navigator.of(context).pop();
  }

  void _dismissConfirmation() {
    _autoClose?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // seule l'annulation explicite ferme cet écran
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: _sent ? _confirmation() : _countdown(),
        ),
      ),
    );
  }

  // ── Compte à rebours ─────────────────────────────────────────
  //
  // Le chiffre est la seule information qui compte à cet instant : blanc sur
  // fond quasi noir (contraste ~20:1, très au-dessus du rouge sur noir du
  // brief d'origine ~3.6:1) pour rester lisible en plein soleil, à travers un
  // écran fissuré, par quelqu'un de sonné. Le rouge reste réservé à l'icône
  // et au texte d'alerte : il signale le danger, il n'a pas besoin d'être
  // aussi lisible que le décompte lui-même.
  Widget _countdown() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 64),
                const SizedBox(height: 24),
                const Text('CHUTE DÉTECTÉE',
                  style: TextStyle(fontFamily: 'Rajdhani', fontSize: 24, fontWeight: FontWeight.w700,
                    color: Colors.white, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                const Text('Appuyez pour annuler si vous allez bien',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 32),
                // Pas de police Rajdhani ici : une police système neutre
                // garde des chiffres aux formes simples, plus sûrs à
                // reconnaître d'un coup d'œil qu'une police à caractère.
                Text('$_remaining',
                  style: const TextStyle(
                    fontSize: 140,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.0,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 2))],
                  )),
              ],
            ),
          ),
        ),
        // Bouton ancré en bas : zone naturellement atteignable au pouce,
        // une seule main, y compris si l'autre est blessée. Pleine largeur,
        // haute (96dp, largement au-dessus des 48dp "gants" habituels de
        // l'appli) : la cible ne doit jamais être manquée par un geste
        // imprécis avec des gants.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            height: 96,
            child: ElevatedButton(
              onPressed: _cancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.red,
                elevation: 8,
                shadowColor: AppColors.red.withOpacity(.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('ANNULER', style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Confirmation ─────────────────────────────────────────────
  //
  // Dernière chose vue avant que les secours n'arrivent : elle doit rassurer,
  // pas juste accuser réception. On dit précisément qui a été prévenu, et on
  // laisse la personne fermer l'écran à son rythme (l'auto-fermeture à 5s
  // n'est qu'un filet de sécurité si elle ne peut pas interagir).
  Widget _confirmation() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissConfirmation,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 80),
              const SizedBox(height: 24),
              const Text('Alerte envoyée', style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 12),
              Text(_confirmationDetail(), textAlign: TextAlign.center, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
              const SizedBox(height: 8),
              const Text("Restez calme, de l'aide arrive.", textAlign: TextAlign.center, style: TextStyle(
                color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  String _confirmationDetail() {
    if (_phoneChannelUsed && _serverChannelUsed) {
      return 'Vos contacts de confiance et les secours ont été prévenus de votre position.';
    }
    if (_phoneChannelUsed) {
      return 'Vos contacts de confiance ont été prévenus de votre position.';
    }
    if (_serverChannelUsed) {
      return 'Les secours ont été prévenus de votre position.';
    }
    return 'Votre position a été enregistrée.';
  }
}
