package app.motooffroad

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

// ── Bandeau de réponses rapides pendant un appel ─────────────
//
// Une notification prioritaire plutôt qu'une fenêtre SYSTEM_ALERT_WINDOW : pas
// de permission spéciale à accorder, et aucune surcouche constructeur ne la
// révoque. Android n'affiche que trois boutons d'action (spec §9.2).
object QuickReplyNotification {
    private const val CHANNEL_ID = "quick_reply"
    private const val NOTIFICATION_ID = 4202
    const val ACTION_TAP = "app.motooffroad.QUICK_REPLY_TAP"
    const val EXTRA_INDEX = "index"
    const val EXTRA_NUMBER = "number"

    fun show(context: Context, labels: List<String>, number: String) {
        ensureChannel(context)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setContentTitle("Appel entrant")
            .setContentText("Répondre par SMS sans décrocher")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setOngoing(false)

        labels.take(3).forEachIndexed { index, label ->
            val intent = Intent(context, QuickReplyReceiver::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_INDEX, index)
                putExtra(EXTRA_NUMBER, number)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, label, pending)
        }

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS refusée : l'auto-réponse fonctionne toujours.
        }
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Réponses rapides aux appels",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Bandeau proposant de répondre par SMS pendant un appel"
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
