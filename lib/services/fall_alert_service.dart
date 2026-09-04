import '../providers/solo_provider.dart';
import 'location_service.dart';

typedef SendSmsFn = Future<bool> Function(String phone, String text);
typedef SendServerAlertFn = Future<bool> Function({required String kind});

// ── Orchestration de la chaîne d'alerte à deux canaux ────────
//
// Dépendances injectées en fonctions, comme AutoReplyService : le service
// lit l'état courant des réglages à chaque appel plutôt que de garder une
// référence figée aux providers.
class FallAlertService {
  FallAlertService({
    required this.sendSms,
    required this.sendServerAlert,
    required this.phoneChannelEnabled,
    required this.serverChannelEnabled,
    required this.trustedContacts,
    required this.positionProvider,
  });

  final SendSmsFn sendSms;
  final SendServerAlertFn sendServerAlert;
  final bool Function() phoneChannelEnabled;
  final bool Function() serverChannelEnabled;
  final List<TrustedContact> Function() trustedContacts;
  final Future<GpsSnapshot?> Function() positionProvider;

  Future<void> sendFallAlert({required String kind}) async {
    final snap = await positionProvider();

    if (phoneChannelEnabled()) {
      final text = _smsText(kind, snap);
      for (final contact in trustedContacts()) {
        await sendSms(contact.phone, text);
      }
    }

    if (serverChannelEnabled()) {
      await sendServerAlert(kind: kind);
    }
  }

  String _smsText(String kind, GpsSnapshot? snap) {
    final label = kind == 'sos' ? 'SOS' : 'une chute possible';
    final positionLine = snap != null
        ? 'Position : ${snap.googleMapsUrl}'
        : 'Position indisponible';
    return 'ALERTE — $label détectée sur MOTO OFFROAD 4X4.\n$positionLine';
  }
}
