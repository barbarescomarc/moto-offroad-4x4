import '../providers/solo_provider.dart';
import 'location_service.dart';

typedef SendSmsFn = Future<bool> Function(String phone, String text);
typedef SendServerAlertFn = Future<bool> Function({required String kind});

// ── Issue réelle d'un envoi d'alerte ─────────────────────────
//
// Distincte des réglages (canal activé) : reflète ce qui a vraiment été
// tenté et a réussi, pour que l'écran de confirmation ne rassure jamais à
// tort une personne blessée.
class FallAlertResult {
  const FallAlertResult({required this.contactsNotified, required this.serverNotified});

  /// Nombre de contacts effectivement joints (sendSms == true).
  final int contactsNotified;

  /// True seulement si le canal serveur était actif ET l'appel a réussi.
  final bool serverNotified;
}

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

  Future<FallAlertResult> sendFallAlert({required String kind}) async {
    final snap = await positionProvider();

    var contactsNotified = 0;
    if (phoneChannelEnabled()) {
      final text = _smsText(kind, snap);
      for (final contact in trustedContacts()) {
        final sent = await sendSms(contact.phone, text);
        if (sent) contactsNotified++;
      }
    }

    var serverNotified = false;
    if (serverChannelEnabled()) {
      serverNotified = await sendServerAlert(kind: kind);
    }

    return FallAlertResult(contactsNotified: contactsNotified, serverNotified: serverNotified);
  }

  String _smsText(String kind, GpsSnapshot? snap) {
    final label = kind == 'sos' ? 'SOS' : 'une chute possible';
    final positionLine = snap != null
        ? 'Position : ${snap.googleMapsUrl}'
        : 'Position indisponible';
    return 'ALERTE — $label détectée sur MOTO OFFROAD 4X4.\n$positionLine';
  }
}
