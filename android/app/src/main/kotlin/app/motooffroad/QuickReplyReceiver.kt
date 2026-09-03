package app.motooffroad

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// ── Pression sur un bouton du bandeau ────────────────────────
class QuickReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != QuickReplyNotification.ACTION_TAP) return

        val index = intent.getIntExtra(QuickReplyNotification.EXTRA_INDEX, -1)
        val number = intent.getStringExtra(QuickReplyNotification.EXTRA_NUMBER) ?: ""

        CallBridge.sink?.success(
            mapOf("type" to "quick_reply", "number" to number, "index" to index)
        )
        QuickReplyNotification.hide(context)
    }
}
