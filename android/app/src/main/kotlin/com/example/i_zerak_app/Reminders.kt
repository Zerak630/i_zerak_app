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
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Les rappels du soir : « Velo ou voiture aujourd'hui ? » du lundi au
 * vendredi, et « Seance faite ? » pour chaque creneau du programme du jour.
 *
 * Le natif ne lit pas Hive : le Dart lui transmet, chaque fois que
 * l'application passe en arriere-plan, les reglages, les textes deja traduits
 * et ce qui est deja saisi (cf. ReminderService). Un rappel ne part que si la
 * journee ou le creneau n'avait pas de reponse a ce moment-la.
 *
 * Les reponses se donnent depuis la notification, sans ouvrir l'application :
 * « Velo » passe par le meme chemin que le widget (`pending_bike`), « Faite »
 * et « Pas faite » sont notes ici, et le Dart les enregistre au lancement
 * suivant. « Voiture » ouvre l'application, puisqu'il faut en donner la raison.
 */
object Reminders {
    const val ACTION_COMMUTE = "com.example.i_zerak_app.REMINDER_COMMUTE"
    const val ACTION_SPORT = "com.example.i_zerak_app.REMINDER_SPORT"
    const val ACTION_BIKE = "com.example.i_zerak_app.REMINDER_BIKE"
    const val ACTION_SLOT_DONE = "com.example.i_zerak_app.REMINDER_SLOT_DONE"
    const val ACTION_SLOT_SKIPPED = "com.example.i_zerak_app.REMINDER_SLOT_SKIPPED"
    const val EXTRA_SLOT = "slot"
    const val EXTRA_DAY = "day"

    private const val PREFS = "izerak_reminders"
    private const val KEY = "config"
    private const val PENDING = "pending_slots"
    private const val CHANNEL_ID = "reminders"

    // Une notification par jour (trajet) ou par creneau (sport) : l'etiquette
    // la distingue, l'identifiant dit de quel rappel il s'agit.
    private const val COMMUTE_ID = 4401
    private const val SPORT_ID = 4402

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun configure(context: Context, config: Map<*, *>?) {
        if (config == null) {
            prefs(context).edit().remove(KEY).apply()
        } else {
            prefs(context).edit().putString(KEY, JSONObject(config).toString()).apply()
        }
        schedule(context)
        dismissAnswered(context)
    }

    private fun load(context: Context): JSONObject? {
        val raw = prefs(context).getString(KEY, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (error: org.json.JSONException) {
            null
        }
    }

    // --- Reponses donnees depuis les notifications de sport -----------------

    private fun pendingSlots(context: Context): Set<String> =
        prefs(context).getStringSet(PENDING, emptySet()) ?: emptySet()

    private fun addPendingSlot(context: Context, answer: String) {
        // Copie obligatoire : le Set rendu par getStringSet ne se modifie pas.
        val answers = pendingSlots(context).toMutableSet()
        answers.add(answer)
        prefs(context).edit().putStringSet(PENDING, answers).apply()
    }

    fun takePendingSlotAnswers(context: Context): List<String> {
        val answers = pendingSlots(context).toList()
        prefs(context).edit().remove(PENDING).apply()
        return answers
    }

    // --- Programmation -------------------------------------------------------

    /** 1 pour lundi, 7 pour dimanche, comme `DateTime.weekday` cote Dart. */
    private fun isoWeekday(calendar: Calendar): Int = (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1

    private fun strings(array: JSONArray?): Set<String> {
        if (array == null) {
            return emptySet()
        }
        return (0 until array.length()).mapNotNull { array.optString(it, null) }.toSet()
    }

    private fun slots(section: JSONObject): List<JSONObject> {
        val list = section.optJSONArray("slots") ?: return emptyList()
        return (0 until list.length()).mapNotNull { list.optJSONObject(it) }
    }

    private fun sportWeekdays(section: JSONObject): Set<Int> = slots(section).map { it.optInt("weekday") }.toSet()

    private fun alarm(context: Context, action: String, code: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        code,
        Intent(context, ReminderReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Le prochain jour retenu par [due], a l'heure du rappel, strictement apres maintenant. */
    private fun nextFire(section: JSONObject, now: Long, due: (Calendar) -> Boolean): Long? {
        val candidate = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, section.optInt("hour", 19))
            set(Calendar.MINUTE, section.optInt("minute", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (i in 0..7) {
            if (due(candidate) && candidate.timeInMillis > now) {
                return candidate.timeInMillis
            }
            candidate.add(Calendar.DAY_OF_YEAR, 1)
        }
        return null
    }

    /** Alarmes inexactes, comme les bilans : quelques minutes de retard ne genent pas. */
    fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val config = load(context)
        val now = System.currentTimeMillis()

        val commuteAlarm = alarm(context, ACTION_COMMUTE, 1)
        alarms.cancel(commuteAlarm)
        val commute = config?.optJSONObject("commute")
        if (commute != null && commute.optBoolean("enabled") && commute.optBoolean("configured")) {
            nextFire(commute, now) { isoWeekday(it) <= 5 }?.let {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, commuteAlarm)
            }
        }

        val sportAlarm = alarm(context, ACTION_SPORT, 2)
        alarms.cancel(sportAlarm)
        val sport = config?.optJSONObject("sport")
        if (sport != null && sport.optBoolean("enabled")) {
            val weekdays = sportWeekdays(sport)
            if (weekdays.isNotEmpty()) {
                nextFire(sport, now) { isoWeekday(it) in weekdays }?.let {
                    alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, sportAlarm)
                }
            }
        }
    }

    // --- Notifications -------------------------------------------------------

    private fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun manager(context: Context): NotificationManager {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.reminder_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
        return manager
    }

    private fun builder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    private fun answer(context: Context, action: String, day: String, slot: String? = null): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(action)
            .putExtra(EXTRA_DAY, day)
        if (slot != null) {
            intent.putExtra(EXTRA_SLOT, slot)
        }
        // Un code par bouton et par notification : sinon FLAG_UPDATE_CURRENT
        // reecrirait les extras d'une notification encore affichee.
        return PendingIntent.getBroadcast(
            context,
            "$action|$slot|$day".hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun postCommute(context: Context) {
        val section = load(context)?.optJSONObject("commute") ?: return
        if (!section.optBoolean("enabled") || !section.optBoolean("configured") || !canNotify(context)) {
            return
        }
        if (isoWeekday(Calendar.getInstance()) > 5) {
            return
        }
        val today = HomeWidgetStore.todayKey()
        if (today in strings(section.optJSONArray("answered")) ||
            today in HomeWidgetStore.pendingBikeDays(context)
        ) {
            return
        }
        val text = section.optString("text")
        val notification = builder(context)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(section.optString("title"))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(HomeWidgetStore.openApp(context, 40, HomeWidgetStore.ACTION_COMMUTE))
            .setAutoCancel(true)
            .addAction(
                Notification.Action.Builder(null, section.optString("bike"), answer(context, ACTION_BIKE, today)).build()
            )
            .addAction(
                Notification.Action.Builder(
                    null,
                    section.optString("car"),
                    HomeWidgetStore.openApp(context, 41, HomeWidgetStore.ACTION_CAR),
                ).build()
            )
            .build()
        manager(context).notify(today, COMMUTE_ID, notification)
    }

    fun postSport(context: Context) {
        val section = load(context)?.optJSONObject("sport") ?: return
        if (!section.optBoolean("enabled") || !canNotify(context)) {
            return
        }
        val weekday = isoWeekday(Calendar.getInstance())
        val today = HomeWidgetStore.todayKey()
        val answered = strings(section.optJSONArray("answered"))
        val pending = pendingSlots(context)
        val manager = manager(context)
        for (slot in slots(section)) {
            val id = slot.optString("id")
            if (id.isEmpty() || slot.optInt("weekday") != weekday) {
                continue
            }
            val key = "$id|$today"
            if (key in answered || "done|$key" in pending || "skipped|$key" in pending) {
                continue
            }
            val text = slot.optString("text")
            val notification = builder(context)
                .setSmallIcon(R.drawable.ic_stat_reminder)
                .setContentTitle(slot.optString("title"))
                .setContentText(text)
                .setContentIntent(HomeWidgetStore.openApp(context, 42, HomeWidgetStore.ACTION_SPORT))
                .setAutoCancel(true)
                .addAction(
                    Notification.Action.Builder(
                        null, section.optString("done"), answer(context, ACTION_SLOT_DONE, today, id),
                    ).build()
                )
                .addAction(
                    Notification.Action.Builder(
                        null, section.optString("skipped"), answer(context, ACTION_SLOT_SKIPPED, today, id),
                    ).build()
                )
                .build()
            manager.notify(key, SPORT_ID, notification)
        }
    }

    /**
     * Retire les rappels dont la reponse a ete donnee dans l'application :
     * une notification restee dans le volet n'a plus rien a demander.
     */
    private fun dismissAnswered(context: Context) {
        val config = load(context) ?: return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val commuteDone = strings(config.optJSONObject("commute")?.optJSONArray("answered"))
        val sportDone = strings(config.optJSONObject("sport")?.optJSONArray("answered"))
        for (shown in manager.activeNotifications) {
            val tag = shown.tag ?: continue
            val answered = when (shown.id) {
                COMMUTE_ID -> tag in commuteDone
                SPORT_ID -> tag in sportDone
                else -> false
            }
            if (answered) {
                manager.cancel(tag, shown.id)
            }
        }
    }

    /** Un bouton d'une notification a ete touche. */
    fun onAnswer(context: Context, intent: Intent) {
        val day = intent.getStringExtra(EXTRA_DAY) ?: return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        when (intent.action) {
            ACTION_BIKE -> {
                HomeWidgetStore.addPendingBikeDay(context, day)
                manager.cancel(day, COMMUTE_ID)
                // Le widget du trajet passe aussitot a « Velo ».
                HomeWidgetStore.refreshAll(context)
            }
            ACTION_SLOT_DONE, ACTION_SLOT_SKIPPED -> {
                val slot = intent.getStringExtra(EXTRA_SLOT) ?: return
                val verdict = if (intent.action == ACTION_SLOT_DONE) "done" else "skipped"
                addPendingSlot(context, "$verdict|$slot|$day")
                manager.cancel("$slot|$day", SPORT_ID)
            }
        }
    }
}

/** Reveil des rappels, reponses depuis les notifications, et reprogrammation apres un redemarrage. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Reminders.ACTION_COMMUTE -> {
                Reminders.schedule(context)
                Reminders.postCommute(context)
            }
            Reminders.ACTION_SPORT -> {
                Reminders.schedule(context)
                Reminders.postSport(context)
            }
            Reminders.ACTION_BIKE, Reminders.ACTION_SLOT_DONE, Reminders.ACTION_SLOT_SKIPPED ->
                Reminders.onAnswer(context, intent)
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                Reminders.schedule(context)
        }
    }
}
