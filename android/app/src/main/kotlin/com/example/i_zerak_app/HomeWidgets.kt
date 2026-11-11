package com.example.i_zerak_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Currency
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Ce que partagent l'application et les widgets de l'ecran d'accueil.
 *
 * Les widgets ne lisent pas Hive : l'application leur transmet un instantane
 * (cf. HomeWidgetsService cote Dart) chaque fois qu'elle passe en
 * arriere-plan. En retour, un appui sur « Velo » note seulement la date dans
 * `pending_bike` ; l'application l'enregistre a son prochain lancement, au
 * prix du carburant de ce jour-la.
 */
object HomeWidgetStore {
    private const val PREFS = "izerak_home_widgets"
    private const val SNAPSHOT = "snapshot"
    private const val PENDING = "pending_bike"
    private const val GOAL_PREFIX = "goal_shown_"

    const val EXTRA_ACTION = "izerak_action"
    const val ACTION_CAR = "car"
    const val ACTION_FREE_TIME = "free_time"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun snapshot(context: Context): JSONObject? {
        val raw = prefs(context).getString(SNAPSHOT, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (error: org.json.JSONException) {
            null
        }
    }

    fun save(context: Context, snapshot: Map<*, *>) {
        prefs(context).edit().putString(SNAPSHOT, JSONObject(snapshot).toString()).apply()
        refreshAll(context)
    }

    fun pendingBikeDays(context: Context): Set<String> =
        prefs(context).getStringSet(PENDING, emptySet()) ?: emptySet()

    fun addPendingBikeDay(context: Context, day: String) {
        // Copie obligatoire : le Set rendu par getStringSet ne doit pas etre
        // modifie en place.
        val days = pendingBikeDays(context).toMutableSet()
        days.add(day)
        prefs(context).edit().putStringSet(PENDING, days).apply()
    }

    fun takePendingBikeDays(context: Context): List<String> {
        val days = pendingBikeDays(context).toList()
        prefs(context).edit().remove(PENDING).apply()
        return days
    }

    fun shownGoal(context: Context, widgetId: Int): String? =
        prefs(context).getString("$GOAL_PREFIX$widgetId", null)

    fun showGoal(context: Context, widgetId: Int, goalId: String?) {
        prefs(context).edit().putString("$GOAL_PREFIX$widgetId", goalId).apply()
    }

    fun forget(context: Context, widgetIds: IntArray) {
        val edit = prefs(context).edit()
        for (id in widgetIds) {
            edit.remove("$GOAL_PREFIX$id")
        }
        edit.apply()
    }

    fun euros(value: Double): String = NumberFormat.getCurrencyInstance().apply {
        currency = Currency.getInstance("EUR")
    }.format(value)

    fun openApp(context: Context, requestCode: Int, action: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (action != null) {
            intent.putExtra(EXTRA_ACTION, action)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Redessine tous les widgets poses. */
    fun refreshAll(context: Context) {
        // Celui-ci mesure le journal d'utilisation : hors du fil appelant.
        FreeTimeWidgetProvider.refreshAll(context)
        val manager = AppWidgetManager.getInstance(context)
        for (id in manager.getAppWidgetIds(ComponentName(context, CommuteWidgetProvider::class.java))) {
            manager.updateAppWidget(id, CommuteWidgetProvider.views(context))
        }
        for (id in manager.getAppWidgetIds(ComponentName(context, GoalWidgetProvider::class.java))) {
            manager.updateAppWidget(id, GoalWidgetProvider.views(context, id))
        }
    }
}

/**
 * « Velo / Voiture ? » : la journee du jour en un appui.
 *
 * Velo s'enregistre sans ouvrir l'application ; Voiture l'ouvre, puisqu'il
 * faut en donner la raison.
 */
class CommuteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, views(context))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_BIKE) {
            // Relu a l'appui : le widget a pu rester affiche depuis la veille.
            if (state(context) == State.READY) {
                HomeWidgetStore.addPendingBikeDay(context, HomeWidgetStore.todayKey())
            }
            HomeWidgetStore.refreshAll(context)
        }
    }

    private enum class State { SETUP, READY, BIKE, CAR, REMOTE }

    companion object {
        const val ACTION_BIKE = "com.example.i_zerak_app.WIDGET_BIKE"

        private fun commute(context: Context): JSONObject? =
            HomeWidgetStore.snapshot(context)?.optJSONObject("commute")

        /** Ce que l'application savait du jour, s'il s'agit bien d'aujourd'hui. */
        private fun recordedToday(context: Context): String? {
            val snapshot = HomeWidgetStore.snapshot(context) ?: return null
            if (snapshot.optString("today") != HomeWidgetStore.todayKey()) {
                return null
            }
            val recorded = snapshot.optJSONObject("commute")?.optString("recorded", "") ?: ""
            return recorded.ifEmpty { null }
        }

        private fun state(context: Context): State {
            if (commute(context)?.optBoolean("configured", false) != true) {
                return State.SETUP
            }
            if (HomeWidgetStore.todayKey() in HomeWidgetStore.pendingBikeDays(context)) {
                return State.BIKE
            }
            return when (recordedToday(context)) {
                "bike" -> State.BIKE
                "car" -> State.CAR
                "remote" -> State.REMOTE
                else -> State.READY
            }
        }

        /**
         * Ce que la journee enregistree a donne, et ou c'est parti : la
         * cagnotte velo, ou l'une des deux cases d'un trajet en voiture.
         */
        private fun status(
            context: Context,
            state: State,
            commute: JSONObject?,
            tripValue: Double,
        ): Pair<String, String?> {
            val amount = commute?.optDouble("amount", tripValue) ?: tripValue
            val euros = HomeWidgetStore.euros(amount)
            return when (state) {
                State.SETUP -> context.getString(R.string.widget_setup) to null
                State.REMOTE -> context.getString(R.string.widget_recorded_remote) to null
                State.CAR -> {
                    val missed = commute?.optString("bucket") == "missed"
                    context.getString(R.string.widget_recorded_car) to context.getString(
                        if (missed) R.string.widget_into_missed else R.string.widget_into_essential,
                        euros,
                    )
                }
                else -> {
                    // Enregistre depuis le widget : le montant exact sera
                    // calcule par l'application au prix du jour, d'ou le « ≈ ».
                    val fromApp = recordedToday(context) == "bike"
                    context.getString(R.string.widget_recorded_bike) to context.getString(
                        if (fromApp) R.string.widget_into_pot else R.string.widget_into_pot_estimate,
                        HomeWidgetStore.euros(if (fromApp) amount else tripValue),
                    )
                }
            }
        }

        fun views(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_commute)
            val commute = commute(context)
            val tripValue = commute?.optDouble("tripValue", 0.0) ?: 0.0
            val state = state(context)

            val ready = state == State.READY
            views.setViewVisibility(R.id.widget_buttons, if (ready) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_status, if (ready) View.GONE else View.VISIBLE)

            if (ready) {
                views.setTextViewText(
                    R.id.widget_bike_gain,
                    context.getString(R.string.widget_bike_gain, HomeWidgetStore.euros(tripValue)),
                )
                val bike = Intent(context, CommuteWidgetProvider::class.java).setAction(ACTION_BIKE)
                views.setOnClickPendingIntent(
                    R.id.widget_bike,
                    PendingIntent.getBroadcast(
                        context, 0, bike,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_car,
                    HomeWidgetStore.openApp(context, 11, HomeWidgetStore.ACTION_CAR),
                )
            } else {
                val (title, detail) = status(context, state, commute, tripValue)
                views.setTextViewText(R.id.widget_status_title, title)
                views.setTextViewText(R.id.widget_status_detail, detail)
                views.setViewVisibility(R.id.widget_status_detail, if (detail == null) View.GONE else View.VISIBLE)
                views.setOnClickPendingIntent(R.id.widget_status, HomeWidgetStore.openApp(context, 10))
            }
            return views
        }
    }
}

/**
 * « Objectif » : un objectif des cagnottes Velo et Temps libre. Un appui
 * passe au suivant ; l'icone en haut a droite ouvre l'application.
 */
class GoalWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, views(context, id))
        }
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        HomeWidgetStore.forget(context, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_NEXT) {
            return
        }
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return
        }
        val goals = goals(context)
        if (goals.isNotEmpty()) {
            val next = (indexShown(context, id, goals) + 1) % goals.size
            HomeWidgetStore.showGoal(context, id, goals[next].optString("id"))
        }
        AppWidgetManager.getInstance(context).updateAppWidget(id, views(context, id))
    }

    companion object {
        const val ACTION_NEXT = "com.example.i_zerak_app.WIDGET_NEXT_GOAL"

        private fun goals(context: Context): List<JSONObject> {
            val list = HomeWidgetStore.snapshot(context)?.optJSONArray("goals") ?: JSONArray()
            return (0 until list.length()).mapNotNull { list.optJSONObject(it) }
        }

        /**
         * L'objectif affiche est retenu par son identifiant, pas par son rang :
         * en valider un ou en ajouter un ne doit pas faire sauter le widget sur
         * un autre.
         */
        private fun indexShown(context: Context, widgetId: Int, goals: List<JSONObject>): Int {
            val shown = HomeWidgetStore.shownGoal(context, widgetId)
            val index = goals.indexOfFirst { it.optString("id") == shown }
            return if (index < 0) 0 else index
        }

        fun views(context: Context, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_goal)
            views.setOnClickPendingIntent(R.id.widget_open, HomeWidgetStore.openApp(context, 20))
            val goals = goals(context)

            if (goals.isEmpty()) {
                views.setViewVisibility(R.id.widget_goal_content, View.GONE)
                views.setViewVisibility(R.id.widget_goal_empty, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.widget_root, HomeWidgetStore.openApp(context, 21))
                return views
            }

            val index = indexShown(context, widgetId, goals)
            val goal = goals[index]
            val current = goal.optDouble("current", 0.0)
            val target = goal.optDouble("target", 0.0)
            val ratio = if (target <= 0) 1.0 else (current / target).coerceIn(0.0, 1.0)
            val reached = current + 0.005 >= target
            val milestone = goal.optBoolean("milestone", false)
            val pot = context.getString(
                if (goal.optString("pot") == "free") R.string.widget_pot_free else R.string.widget_pot_commute
            )

            views.setViewVisibility(R.id.widget_goal_content, View.VISIBLE)
            views.setViewVisibility(R.id.widget_goal_empty, View.GONE)
            views.setTextViewText(
                R.id.widget_goal_pot,
                (if (milestone) "$pot · ${context.getString(R.string.widget_milestone)}" else pot)
                    .uppercase(Locale.getDefault()),
            )
            views.setTextViewText(
                R.id.widget_goal_position,
                if (goals.size > 1) context.getString(R.string.widget_goal_position, index + 1, goals.size) else "",
            )
            views.setTextViewText(R.id.widget_goal_name, goal.optString("name"))
            views.setProgressBar(R.id.widget_goal_progress, 1000, (ratio * 1000).roundToInt(), false)
            views.setTextViewText(
                R.id.widget_goal_amounts,
                context.getString(
                    R.string.widget_goal_progress,
                    HomeWidgetStore.euros(current.coerceAtMost(target)),
                    HomeWidgetStore.euros(target),
                ),
            )
            views.setTextViewText(
                R.id.widget_goal_percent,
                if (reached) {
                    context.getString(R.string.widget_goal_reached)
                } else {
                    // Arrondi par defaut : 99,6 % ne doit pas s'afficher 100 %.
                    NumberFormat.getPercentInstance().format(kotlin.math.floor(ratio * 100) / 100)
                },
            )

            val next = Intent(context, GoalWidgetProvider::class.java)
                .setAction(ACTION_NEXT)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getBroadcast(
                    context, widgetId, next,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            return views
        }
    }
}

/**
 * « Temps libre » : le temps passe aujourd'hui sur les reseaux, face au quota.
 *
 * Mesure par le natif a chaque mise a jour, sans l'application : toutes les
 * 30 minutes, chaque fois qu'iZerak passe en arriere-plan, et a chaque appui
 * sur le widget. Les reglages viennent de ceux du bilan du soir
 * (cf. DailyReport.configure).
 */
class FreeTimeWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // Lire le journal d'utilisation de la journee prend un moment :
            // hors du fil principal, sans que le systeme coupe le recepteur.
            AppWidgetManager.ACTION_APPWIDGET_UPDATE, ACTION_REFRESH -> {
                val pending = goAsync()
                Thread {
                    try {
                        render(context)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.example.i_zerak_app.WIDGET_FREE_TIME_REFRESH"

        fun refreshAll(context: Context) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, FreeTimeWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                context.sendBroadcast(Intent(context, FreeTimeWidgetProvider::class.java).setAction(ACTION_REFRESH))
            }
        }

        private fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, FreeTimeWidgetProvider::class.java))
            if (ids.isEmpty()) {
                return
            }
            val views = views(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
            }
        }

        private fun message(context: Context, text: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_free_time)
            views.setViewVisibility(R.id.widget_free_content, View.GONE)
            views.setViewVisibility(R.id.widget_free_message, View.VISIBLE)
            views.setTextViewText(R.id.widget_free_message, context.getString(text))
            val open = HomeWidgetStore.openApp(context, 31, HomeWidgetStore.ACTION_FREE_TIME)
            views.setOnClickPendingIntent(R.id.widget_root, open)
            views.setOnClickPendingIntent(R.id.widget_open, open)
            return views
        }

        fun views(context: Context): RemoteViews {
            val config = DailyReport.load(context) ?: return message(context, R.string.widget_free_setup)
            if (!UsageSessions.hasAccess(context)) {
                return message(context, R.string.widget_free_access)
            }
            val day = ScreenTimeToday.measure(context, config)
            val views = RemoteViews(context.packageName, R.layout.widget_free_time)
            val color = context.getColor(if (day.under) R.color.widget_primary else R.color.widget_tertiary)
            val ratio = if (day.quota <= 0) 1.0 else (day.minutes / day.quota).coerceIn(0.0, 1.0)

            views.setViewVisibility(R.id.widget_free_content, View.VISIBLE)
            views.setViewVisibility(R.id.widget_free_message, View.GONE)
            views.setTextViewText(
                R.id.widget_free_updated,
                java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(Date()),
            )
            views.setTextViewText(R.id.widget_free_time, DailyReport.formatMinutes(context, day.minutes.toLong()))
            views.setTextColor(R.id.widget_free_time, color)
            views.setTextViewText(
                R.id.widget_free_quota,
                context.getString(R.string.widget_free_quota, DailyReport.formatMinutes(context, day.quota.toLong())),
            )
            // Deux barres plutot qu'une teinte changee : avant Android 12, un
            // widget ne peut pas recolorer une barre de progression.
            val bar = if (day.under) R.id.widget_free_progress else R.id.widget_free_progress_over
            views.setViewVisibility(R.id.widget_free_progress, if (day.under) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_free_progress_over, if (day.under) View.GONE else View.VISIBLE)
            views.setProgressBar(bar, 1000, (ratio * 1000).roundToInt(), false)
            views.setTextViewText(
                R.id.widget_free_amount,
                context.getString(
                    if (day.under) R.string.widget_free_gain else R.string.widget_free_missed,
                    HomeWidgetStore.euros(day.amount),
                ),
            )
            views.setTextColor(R.id.widget_free_amount, color)
            views.setTextViewText(
                R.id.widget_free_streak,
                day.streak?.let { context.resources.getQuantityString(R.plurals.widget_free_streak, it, it) } ?: "",
            )

            val refresh = Intent(context, FreeTimeWidgetProvider::class.java).setAction(ACTION_REFRESH)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getBroadcast(
                    context, 30, refresh,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_open,
                HomeWidgetStore.openApp(context, 31, HomeWidgetStore.ACTION_FREE_TIME),
            )
            return views
        }
    }
}
