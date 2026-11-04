package com.example.i_zerak_app

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * Le bilan du soir : une notification par jour, calculee application fermee.
 *
 * Le Dart transmet ses reglages a chaque ouverture de l'onglet (cf.
 * ScreenTimeService.reportConfig) ; ils sont gardes dans les preferences, et
 * l'alarme se reprogramme d'elle-meme chaque soir et apres un redemarrage.
 *
 * Le quota, le gain et l'economie loupee sont recalcules ici avec la meme
 * formule que ScreenTimeSettings.quotaFor, earnedOn et missedOn : les deux
 * doivent rester d'accord.
 */
object DailyReport {
    const val ACTION = "com.example.i_zerak_app.DAILY_REPORT"
    private const val PREFS = "izerak_screen_time"
    private const val KEY = "report"
    private const val CHANNEL_ID = "screen_time_report"
    private const val NOTIFICATION_ID = 4201

    /**
     * Les reglages du Temps libre, partages avec le widget du meme nom : ils
     * sont transmis des que l'onglet est configure, bilan active ou non
     * (cf. `enabled`).
     */
    fun configure(context: Context, config: Map<*, *>?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (config == null) {
            prefs.edit().remove(KEY).apply()
        } else {
            prefs.edit().putString(KEY, JSONObject(config).toString()).apply()
        }
        schedule(context)
        FreeTimeWidgetProvider.refreshAll(context)
    }

    fun load(context: Context): JSONObject? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return null
        return try {
            JSONObject(raw)
        } catch (error: org.json.JSONException) {
            null
        }
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, DailyReportReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Programme le prochain bilan, ou l'annule sans reglages. Alarme inexacte :
     * quelques minutes de retard ne genent pas, et une alarme exacte
     * demanderait une autorisation de plus.
     */
    fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = pendingIntent(context)
        alarms.cancel(pending)
        val config = load(context) ?: return
        if (!config.optBoolean("enabled", true)) {
            return
        }
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, config.optInt("hour", 21))
            set(Calendar.MINUTE, config.optInt("minute", 30))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pending)
    }

    fun formatMinutes(context: Context, minutes: Long): String =
        if (minutes < 60) {
            context.getString(R.string.report_minutes, minutes)
        } else {
            context.getString(R.string.report_hours, minutes / 60, minutes % 60)
        }

    fun post(context: Context) {
        val config = load(context) ?: return
        if (!config.optBoolean("enabled", true) || !UsageSessions.hasAccess(context)) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val day = ScreenTimeToday.measure(context, config)
        val euros = HomeWidgetStore.euros(day.amount)
        val spent = formatMinutes(context, day.minutes.toLong())
        val limit = formatMinutes(context, day.quota.toLong())
        var text = context.getString(
            if (day.under) R.string.report_under else R.string.report_over, spent, limit, euros
        )
        if (day.streak != null) {
            text += context.resources.getQuantityString(R.plurals.report_streak, day.streak, day.streak)
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.report_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_hourglass)
            .setContentTitle(context.getString(R.string.report_title))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }
}

/**
 * La journee en cours du Temps libre, mesuree application fermee : pour le
 * bilan du soir et le widget.
 *
 * Meme formule que ScreenTimeSettings.quotaFor, earnedOn et missedOn cote
 * Dart : les deux doivent rester d'accord.
 */
object ScreenTimeToday {
    class Day(
        val seconds: Long,
        val quota: Double,
        /** Le gain si le quota tient, sinon l'economie loupee. */
        val amount: Double,
        /** Jours tenus d'affilee, aujourd'hui compris ; nul si inconnu ou rompu. */
        val streak: Int?,
    ) {
        val minutes: Double get() = seconds / 60.0
        val under: Boolean get() = seconds <= quota * 60
    }

    /** Jours depuis le 1er janvier 1970, sur la date calendaire locale. */
    private fun epochDay(calendar: Calendar): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH))
        }
        return utc.timeInMillis / 86_400_000L
    }

    fun measure(context: Context, config: JSONObject): Day {
        val packages = mutableSetOf<String>()
        val list = config.optJSONArray("packages")
        for (i in 0 until (list?.length() ?: 0)) {
            packages.add(list!!.getString(i))
        }
        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val seconds = UsageSessions.secondsSince(context, midnight.timeInMillis, packages)
        val minutes = seconds / 60.0

        val baseline = config.optDouble("baseline", 0.0)
        val today = epochDay(midnight)
        val week = max(0L, (today - config.optLong("startEpochDay", today)) / 7)
        val target = baseline * (1 - config.optDouble("decrease", 0.1)).pow((week + 1).toDouble())
        val floor = min(config.optDouble("floor", 20.0), baseline)
        val quota = Math.round(max(target, floor)).toDouble()
        val rate = config.optDouble("rate", 2.0)
        fun gainFor(spent: Double) = (max(0.0, baseline - spent) / 60 * rate * 100).roundToLong() / 100.0
        val under = seconds <= quota * 60
        // Sous le quota, le gain du jour ; au-dessus, rien dans la cagnotte,
        // et ce que le quota aurait rapporte part en economies loupees.
        val amount = if (under) gainFor(minutes) else gainFor(quota)
        // La serie n'est connue que si l'onglet a ete ouvert depuis hier.
        val streak = if (under && config.optLong("streakThroughEpochDay", -1) == today - 1) {
            config.optInt("streak", 0) + 1
        } else {
            null
        }
        return Day(seconds, quota, amount, streak)
    }
}

/** Reveil du bilan, et reprogrammation apres un redemarrage ou une mise a jour. */
class DailyReportReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            DailyReport.ACTION -> {
                // Lire le journal d'utilisation peut prendre un moment : hors
                // du fil principal, sans que le systeme tue le recepteur.
                val pending = goAsync()
                Thread {
                    try {
                        DailyReport.post(context)
                    } finally {
                        DailyReport.schedule(context)
                        pending.finish()
                    }
                }.start()
            }
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                DailyReport.schedule(context)
        }
    }
}
