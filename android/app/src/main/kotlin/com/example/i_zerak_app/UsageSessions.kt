package com.example.i_zerak_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process

/** Un passage au premier plan, en millisecondes depuis l'epoque. */
data class Session(val pkg: String, val start: Long, val end: Long)

/** Ce qu'Android a vu entre deux instants (cf. UsageWindow cote Dart). */
class UsageWindow(val sessions: List<Session>, val hasData: Boolean)

/**
 * Reconstitue les passages au premier plan a partir du journal d'evenements
 * d'Android.
 *
 * Le journal donne des reprises et des pauses d'activites, pas des sessions :
 * une application est consideree au premier plan tant qu'au moins une de ses
 * activites est reprise. L'extinction de l'ecran ou le verrouillage ferment
 * tout, sans quoi une application laissee ouverte la nuit compterait jusqu'au
 * matin.
 */
object UsageSessions {
    // Une application deja ouverte a l'instant `from` n'a pas d'evenement de
    // reprise dans l'intervalle : on remonte un peu pour la retrouver.
    private const val LOOKBACK_MS = 3L * 60 * 60 * 1000

    // Valeurs brutes : les constantes nommees n'existent qu'a partir des API
    // 28 et 29, et le projet descend jusqu'a 24.
    private const val ACTIVITY_RESUMED = 1
    private const val ACTIVITY_PAUSED = 2
    private const val SCREEN_NON_INTERACTIVE = 16
    private const val KEYGUARD_SHOWN = 17
    private const val ACTIVITY_STOPPED = 23
    private const val DEVICE_SHUTDOWN = 26

    // Les deux variantes sont tour a tour marquees obsoletes selon la version
    // du SDK ; aucune remplacante ne couvre de l'API 24 a aujourd'hui.
    @Suppress("DEPRECATION")
    fun hasAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
            )
        } else {
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Les sessions des [packages] qui touchent l'intervalle [from, to[. Elles
     * ne sont pas rognees : c'est au Dart de les decouper par jour, pour que
     * l'ouverture d'une session commencee la veille ne compte pas deux fois.
     */
    fun query(context: Context, from: Long, to: Long, packages: Set<String>): UsageWindow {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = minOf(to, System.currentTimeMillis())
        if (end <= from) {
            return UsageWindow(emptyList(), false)
        }
        val events = manager.queryEvents(from - LOOKBACK_MS, end)
        val sessions = mutableListOf<Session>()
        val resumed = HashMap<String, MutableSet<String>>()
        val startedAt = HashMap<String, Long>()
        var hasData = false
        val event = UsageEvents.Event()

        fun close(pkg: String, at: Long) {
            val start = startedAt.remove(pkg) ?: return
            resumed.remove(pkg)
            if (at > start && at > from) {
                sessions.add(Session(pkg, start, at))
            }
        }

        fun closeAll(at: Long) {
            for (pkg in startedAt.keys.toList()) {
                close(pkg, at)
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val time = event.timeStamp
            if (time >= from) {
                hasData = true
            }
            when (event.eventType) {
                ACTIVITY_RESUMED -> {
                    val pkg = event.packageName
                    if (pkg != null && pkg in packages) {
                        val activities = resumed.getOrPut(pkg) { mutableSetOf() }
                        if (activities.isEmpty()) {
                            startedAt[pkg] = time
                        }
                        activities.add(event.className ?: "")
                    }
                }
                ACTIVITY_PAUSED, ACTIVITY_STOPPED -> {
                    val pkg = event.packageName
                    val activities = if (pkg == null) null else resumed[pkg]
                    if (pkg != null && activities != null) {
                        activities.remove(event.className ?: "")
                        if (activities.isEmpty()) {
                            close(pkg, time)
                        }
                    }
                }
                SCREEN_NON_INTERACTIVE, KEYGUARD_SHOWN, DEVICE_SHUTDOWN -> closeAll(time)
            }
        }
        // Encore ouvertes : elles durent jusqu'a la fin de l'intervalle.
        closeAll(end)
        return UsageWindow(sessions, hasData)
    }

    /** Secondes passees dans les [packages] entre [from] et maintenant. */
    fun secondsSince(context: Context, from: Long, packages: Set<String>): Long {
        val window = query(context, from, System.currentTimeMillis(), packages)
        return window.sessions.sumOf { maxOf(0L, it.end - maxOf(it.start, from)) } / 1000
    }

    /** Les applications qui ont une icone dans le lanceur, sauf iZerak. */
    fun launchableApps(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activities = pm.queryIntentActivities(intent, 0)
        return activities
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != context.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }
}
