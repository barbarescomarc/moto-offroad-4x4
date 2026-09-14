import '../providers/solo_provider.dart';
import 'location_service.dart';

typedef SendSmsFn = Future<bool> Function(String phone, String text);
typedef SendServerAlertFn = Future<bool> Function({required String kind});

/// Prévient les riders de la sortie en cours. Rend `false` si aucun groupe
/// n'est actif, ou si l'appel a échoué.
typedef SendGroupAlertFn = Future<bool> Function({required String kind});

// ── Issue réelle d'un envoi d'alerte ─────────────────────────
//
// Distincte des réglages (canal activé) : reflète ce qui a vraiment été
// tenté et a réussi, pour que l'écran de confirmation ne rassure jamais à
// tort une personne blessée.
class FallAlertResult {
  const FallAlertResult({
    required this.contactsNotified,
    required this.serverNotified,
    this.groupNotified = false,
  });

  /// Nombre de contacts effectivement joints (sendSms == true).
  final int contactsNotified;

  /// True seulement si le canal serveur était actif ET l'appel a réussi.
  final bool serverNotified;

  /// True si le groupe a bien été prévenu. Distinct du canal serveur : c'est
  /// le seul canal dont les destinataires sont à portée de moto.
  final bool groupNotified;

  /// Personne n'a été joint. L'écran de confirmation ne doit jamais rassurer
  /// à tort quelqu'un qui vient de tomber.
  bool get personneJointe =>
      contactsNotified == 0 && !serverNotified && !groupNotified;
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
    this.sendGroupAlert,
  });

  final SendSmsFn sendSms;
  final SendServerAlertFn sendServerAlert;
  final bool Function() phoneChannelEnabled;
  final bool Function() serverChannelEnabled;
  final List<TrustedContact> Function() trustedContacts;
  final Future<GpsSnapshot?> Function() positionProvider;

  /// Canal « les autres riders ». Optionnel : une sortie solo n'en a pas.
  final SendGroupAlertFn? sendGroupAlert;

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

    // Les riders de la sortie, en plus des proches et non à leur place. Ils
    // sont à quelques centaines de mètres quand un contact de confiance est à
    // plusieurs heures de route : ce sont eux qui arrivent en premier.
    //
    // Ce canal ne dépend d'aucun réglage. Les deux autres se coupent parce
    // qu'ils dérangent des gens loin de la piste ; celui-ci ne dérange que
    // des gens qui roulent avec toi et qui ont accepté de le faire.
    final groupNotified = await sendGroupAlert?.call(kind: kind) ?? false;

    return FallAlertResult(
      contactsNotified: contactsNotified,
      serverNotified: serverNotified,
      groupNotified: groupNotified,
    );
  }

  String _smsText(String kind, GpsSnapshot? snap) {
    final label = kind == 'sos' ? 'SOS' : 'une chute possible';
    final positionLine = snap != null
        ? 'Position : ${snap.googleMapsUrl}'
        : 'Position indisponible';
    return 'ALERTE — $label détectée sur GO FREE.\n$positionLine';
  }
}
