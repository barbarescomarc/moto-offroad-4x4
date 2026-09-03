package app.motooffroad

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ── Pont natif : appels entrants, SMS, bandeau ───────────────
class CallBridge(private val activity: Activity) : EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "app.motooffroad/call"
        const val EVENT_CHANNEL = "app.motooffroad/call_events"
        private const val PERMISSION_REQUEST = 4201

        private val REQUIRED = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.SEND_SMS
        )

        // Le récepteur des boutons du bandeau passe par ici.
        var sink: EventChannel.EventSink? = null
    }

    private var callReceiver: BroadcastReceiver? = null
    private var lastState: String? = null

    // Demande de permission en cours : ActivityCompat.requestPermissions est
    // asynchrone, la réponse Dart n'est honorée qu'au retour de
    // onRequestPermissionsResult, via onPermissionsResult ci-dessous.
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        registerCallReceiver()
    }

    override fun onCancel(arguments: Any?) {
        unregisterCallReceiver()
        sink = null
        // Ne pas laisser un Future Dart pendre indéfiniment si l'écoute
        // s'arrête pendant qu'une demande de permission est en cours.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
    }

    // ── Détection d'appel entrant ────────────────────────────
    private fun registerCallReceiver() {
        if (callReceiver != null) return
        callReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val state = intent?.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return

                // Android émet plusieurs fois le même état ; on ne réagit qu'au
                // passage effectif vers RINGING.
                if (state == lastState) return
                lastState = state

                if (state != TelephonyManager.EXTRA_STATE_RINGING) {
                    QuickReplyNotification.hide(activity)
                    return
                }

                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                sink?.success(mapOf("type" to "incoming", "number" to number, "index" to -1))
            }
        }
        // Depuis Android 14, un registerReceiver sans drapeau d'exportation lève
        // une SecurityException au démarrage de l'écoute : ContextCompat gère
        // toutes les versions correctement.
        ContextCompat.registerReceiver(
            activity,
            callReceiver,
            IntentFilter("android.intent.action.PHONE_STATE"),
            ContextCompat.RECEIVER_EXPORTED
        )
    }

    private fun unregisterCallReceiver() {
        callReceiver?.let { activity.unregisterReceiver(it) }
        callReceiver = null
    }

    // ── Méthodes appelées depuis Dart ────────────────────────
    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sendSms" -> {
                val phone = call.argument<String>("phone") ?: ""
                val text = call.argument<String>("text") ?: ""
                result.success(sendSms(phone, text))
            }
            "showBanner" -> {
                val labels = call.argument<List<String>>("labels") ?: emptyList()
                val number = call.argument<String>("number") ?: ""
                QuickReplyNotification.show(activity, labels, number)
                result.success(null)
            }
            "hideBanner" -> {
                QuickReplyNotification.hide(activity)
                result.success(null)
            }
            "hasPermissions" -> result.success(hasPermissions())
            "requestPermissions" -> {
                if (hasPermissions()) {
                    // Déjà accordées : pas de dialogue à ouvrir.
                    result.success(true)
                } else if (pendingPermissionResult != null) {
                    // Une demande est déjà en cours : un MethodChannel.Result ne
                    // peut être honoré qu'une seule fois, on ne peut pas écraser
                    // l'ancien sans faire planter l'application.
                    result.success(false)
                } else {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(activity, REQUIRED, PERMISSION_REQUEST)
                }
            }
            else -> result.notImplemented()
        }
    }

    // Appelée depuis MainActivity.onRequestPermissionsResult une fois que
    // l'utilisateur a répondu à la boîte de dialogue système.
    fun onPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermissionResult?.success(hasPermissions())
        pendingPermissionResult = null
        return true
    }

    private fun hasPermissions(): Boolean = REQUIRED.all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    // Un message long est découpé par l'opérateur : sendMultipartTextMessage
    // évite la troncature quand la position est jointe.
    private fun sendSms(phone: String, text: String): Boolean {
        if (phone.isBlank() || !hasPermissions()) return false
        return try {
            val manager = if (android.os.Build.VERSION.SDK_INT >= 31) {
                activity.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = manager.divideMessage(text)
            manager.sendMultipartTextMessage(phone, null, parts, null, null)
            true
        } catch (e: Exception) {
            false
        }
    }
}
