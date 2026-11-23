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
import android.util.Log
import org.json.JSONObject
import java.net.URL
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager
import kotlin.concurrent.thread

/**
 * Le bilan de la semaine (chaque dimanche soir) et du mois (le dernier jour).
 *
 * Le natif ne lit pas Hive : le Dart lui transmet, chaque fois que
 * l'application passe en arriere-plan, les textes deja rediges du bilan en
 * cours et du precedent, chacun avec le jour ou sa periode se termine
 * (cf. RecapService.config). Au reveil, on notifie celui qui se termine ce
 * jour-la ; sans lui — l'application n'a pas ete ouverte de la periode — on
 * ne dit rien plutot que d'annoncer des zeros.
 */
object RecapReport {
    const val ACTION = "com.example.i_zerak_app.RECAP_REPORT"
    private const val PREFS = "izerak_recap"
    private const val KEY = "config"
    private const val CHANNEL_ID = "recap_report"
    private const val WEEK_NOTIFICATION_ID = 4301
    private const val MONTH_NOTIFICATION_ID = 4302
    private const val TAG = "RecapReport"
    private const val LIVE_DEADLINE_MS = 12_000L

    fun configure(context: Context, config: Map<*, *>?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (config == null) {
            prefs.edit().remove(KEY).apply()
        } else {
            prefs.edit().putString(KEY, JSONObject(config).toString()).apply()
        }
        schedule(context)
    }

    private fun load(context: Context): JSONObject? {
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
        Intent(context, RecapReportReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun isLastDayOfMonth(day: Calendar): Boolean =
        day.get(Calendar.DAY_OF_MONTH) == day.getActualMaximum(Calendar.DAY_OF_MONTH)

    /**
     * Le prochain dimanche, ou le prochain dernier jour du mois, a l'heure
     * choisie, strictement apres maintenant. Nul si les deux bilans sont
     * desactives.
     */
    private fun nextFire(config: JSONObject, now: Long): Long? {
        val weekly = config.optBoolean("weekly", true)
        val monthly = config.optBoolean("monthly", true)
        if (!weekly && !monthly) {
            return null
        }
        val candidate = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, config.optInt("hour", 19))
            set(Calendar.MINUTE, config.optInt("minute", 30))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        // Au plus un mois et une semaine a parcourir : le dernier jour du
        // mois revient toujours avant.
        for (i in 0..40) {
            val due = (weekly && candidate.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) ||
                (monthly && isLastDayOfMonth(candidate))
            if (due && candidate.timeInMillis > now) {
                return candidate.timeInMillis
            }
            candidate.add(Calendar.DAY_OF_YEAR, 1)
        }
        return null
    }

    /** Alarme inexacte, comme le bilan du soir : quelques minutes de retard ne genent pas. */
    fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = pendingIntent(context)
        alarms.cancel(pending)
        val config = load(context) ?: return
        val next = nextFire(config, System.currentTimeMillis()) ?: return
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
    }

    /** Jours depuis le 1er janvier 1970, sur la date calendaire locale. */
    private fun epochDay(calendar: Calendar): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH))
        }
        return utc.timeInMillis / 86_400_000L
    }

    private fun entry(config: JSONObject, kind: String, endEpochDay: Long): JSONObject? {
        val entries = config.optJSONArray("entries") ?: return null
        for (i in 0 until entries.length()) {
            val entry = entries.optJSONObject(i) ?: continue
            if (entry.optString("kind") == kind && entry.optLong("endEpochDay", -1) == endEpochDay) {
                return entry
            }
        }
        return null
    }

    fun post(context: Context) {
        val config = load(context) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val today = Calendar.getInstance()
        val day = epochDay(today)
        if (config.optBoolean("weekly", true) && today.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) {
            entry(config, "week", day)?.let {
                notify(context, it, WEEK_NOTIFICATION_ID, liveText(it) ?: it.optString("text"))
            }
        }
        if (config.optBoolean("monthly", true) && isLastDayOfMonth(today)) {
            entry(config, "month", day)?.let {
                notify(context, it, MONTH_NOTIFICATION_ID, it.optString("text"))
            }
        }
    }

    /**
     * Le bilan complete du temps de jeu releve a l'instant sur le Pi. Nul si
     * le Pi ne repond pas a temps ou que sa semaine n'est pas mesuree : la
     * notification garde alors le texte prepare, qui dit « au dernier releve ».
     *
     * Dans un fil a part, avec une limite globale : les delais de connexion et
     * de lecture ne couvrent pas la resolution DNS.
     */
    private fun liveText(entry: JSONObject): String? {
        val live = entry.optJSONObject("live") ?: return null
        val result = AtomicReference<String?>()
        val worker = thread(isDaemon = true) {
            try {
                result.set(renderLive(live))
            } catch (error: Exception) {
                Log.d(TAG, "Temps de jeu indisponible : ${error.javaClass.simpleName}")
            }
        }
        worker.join(LIVE_DEADLINE_MS)
        return result.get()
    }

    private fun renderLive(live: JSONObject): String? {
        val week = fetchWeek(live) ?: return null
        if (!week.optBoolean("measured", false)) {
            return null
        }
        val played = week.getInt("minutes")
        return if (played <= 0) {
            live.getString("none")
        } else {
            live.getString("template")
                .replace("{played}", duration(played))
                .replace("{next}", duration(target(played, live.getInt("ratio"), live.getInt("cap"))))
        }
    }

    /** Meme calcul que GameContractSettings.targetFor. */
    private fun target(played: Int, ratio: Int, cap: Int): Int {
        val step = ratio * 5
        return minOf(((played + step - 1) / step) * 5, cap)
    }

    /** Meme ecriture que `free_minutes` et `free_hours`, en francais comme en anglais. */
    private fun duration(minutes: Int): String =
        if (minutes < 60) "$minutes min" else "${minutes / 60} h ${(minutes % 60).toString().padStart(2, '0')}"

    private fun fetchWeek(live: JSONObject): JSONObject? {
        val connection = URL(live.getString("url")).openConnection() as? HttpsURLConnection ?: return null
        try {
            connection.sslSocketFactory = pinnedFactory(live.getString("pin"))
            // L'empreinte designe deja le certificat exact : comme cote Dart, le
            // nom d'hote (adresse locale ou Tailscale) n'a rien a y ajouter.
            connection.hostnameVerifier = HostnameVerifier { _, _ -> true }
            connection.connectTimeout = 4000
            connection.readTimeout = 4000
            connection.setRequestProperty("Authorization", "Bearer ${live.getString("token")}")
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode != 200) {
                return null
            }
            return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    /** N'accepte que le certificat dont l'empreinte SHA-256 est epinglee. */
    private fun pinnedFactory(pin: String): SSLSocketFactory {
        val trust = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
                throw CertificateException("Pas de certificat client")

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                val digest = MessageDigest.getInstance("SHA-256").digest(chain[0].encoded)
                val actual = digest.joinToString("") { "%02x".format(it) }
                if (!MessageDigest.isEqual(actual.toByteArray(), pin.toByteArray())) {
                    throw CertificateException("Certificat non epingle")
                }
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        return SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }.socketFactory
    }

    private fun notify(context: Context, entry: JSONObject, id: Int, text: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.recap_channel),
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
            .setContentTitle(entry.optString("title"))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(id, notification)
    }
}

/** Reveil du bilan, et reprogrammation apres un redemarrage ou une mise a jour. */
class RecapReportReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            RecapReport.ACTION -> {
                // Avant le reseau : si le processus meurt pendant l'appel au
                // Pi, les bilans suivants restent programmes.
                RecapReport.schedule(context)
                val pending = goAsync()
                thread {
                    try {
                        RecapReport.post(context)
                    } catch (error: Exception) {
                        Log.w("RecapReport", "Bilan non notifie", error)
                    } finally {
                        pending.finish()
                    }
                }
            }
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                RecapReport.schedule(context)
        }
    }
}
