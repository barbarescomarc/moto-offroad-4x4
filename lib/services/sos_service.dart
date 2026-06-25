import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'location_service.dart';

// ── Service SOS ──────────────────────────────────────────────
class SosService {
  static final SosService _instance = SosService._();
  factory SosService() => _instance;
  SosService._();

  final _locationService = LocationService();

  // ── Récupère les coords et copie dans le presse-papier ──
  Future<GpsSnapshot?> getSnapshot() async {
    return _locationService.lastSnapshot
        ?? await _locationService.getCurrentPosition();
  }

  // ── Appel 112 direct ────────────────────────────────────
  Future<bool> call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  // ── SMS pré-rempli vers 112 (Europe) / 15 (SAMU France) ─
  Future<bool> sendSms({String number = '112'}) async {
    final snap = await getSnapshot();
    if (snap == null) return false;

    final message = Uri.encodeComponent(snap.sosMessage);
    final uri = Uri.parse('sms:$number?body=$message');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  // ── Partage WhatsApp ─────────────────────────────────────
  Future<bool> shareWhatsApp() async {
    final snap = await getSnapshot();
    if (snap == null) return false;

    final message = Uri.encodeComponent(snap.sosMessage);
    final uri = Uri.parse('whatsapp://send?text=$message');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    // Fallback : partage générique
    return shareGeneric();
  }

  // ── Partage générique (Signal, Messenger, email…) ────────
  Future<bool> shareGeneric() async {
    final snap = await getSnapshot();
    if (snap == null) return false;

    await Share.share(
      snap.sosMessage,
      subject: '🆘 URGENCE — Position GPS',
    );
    return true;
  }

  // ── Ouvre la position dans Google Maps ───────────────────
  Future<bool> openInMaps() async {
    final snap = await getSnapshot();
    if (snap == null) return false;

    final uri = Uri.parse(snap.googleMapsUrl);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  // ── Texte des coordonnées brutes ─────────────────────────
  Future<String?> getCoordinatesText() async {
    final snap = await getSnapshot();
    return snap?.sosText;
  }
}
