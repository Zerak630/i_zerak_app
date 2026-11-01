package com.example.i_zerak_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // Lire le journal d'utilisation de toute une journee prend parfois une
    // seconde : jamais sur le fil de l'interface.
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingNotificationResult: MethodChannel.Result? = null

    /** Ce qu'un widget a demande en ouvrant l'application, jusqu'a ce que le Dart le lise. */
    private var launchAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readLaunchAction(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "izerak/screen_time")
            .setMethodCallHandler(::onScreenTimeCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "izerak/home_widgets")
            .setMethodCallHandler(::onHomeWidgetsCall)
    }

    // L'activite est en singleTop : un widget touche alors qu'iZerak est deja
    // ouvert arrive ici plutot qu'a la creation.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readLaunchAction(intent)
    }

    private fun readLaunchAction(intent: Intent?) {
        val action = intent?.getStringExtra(HomeWidgetStore.EXTRA_ACTION) ?: return
        launchAction = action
        // Retiree de l'intent : une rotation recree l'activite avec le meme,
        // et ne doit pas reposer la question.
        intent.removeExtra(HomeWidgetStore.EXTRA_ACTION)
    }

    private fun onHomeWidgetsCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                val snapshot = call.arguments as? Map<*, *>
                if (snapshot == null) {
                    result.error("bad_args", "instantane attendu", null)
                    return
                }
                HomeWidgetStore.save(this, snapshot)
                result.success(null)
            }
            "takePendingBikeDays" -> result.success(HomeWidgetStore.takePendingBikeDays(this))
            "takeLaunchAction" -> {
                result.success(launchAction)
                launchAction = null
            }
            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private fun onScreenTimeCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(UsageSessions.hasAccess(this))
            "openAccessSettings" -> {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }
            "sessions" -> {
                val from = call.argument<Number>("from")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                val packages = call.argument<List<String>>("packages")?.toSet()
                if (from == null || to == null || packages == null) {
                    result.error("bad_args", "from, to et packages sont requis", null)
                    return
                }
                background(result) {
                    val window = UsageSessions.query(this, from, to, packages)
                    mapOf(
                        "hasData" to window.hasData,
                        "sessions" to window.sessions.map {
                            mapOf("p" to it.pkg, "s" to it.start, "e" to it.end)
                        },
                    )
                }
            }
            "launchableApps" -> background(result) { UsageSessions.launchableApps(this) }
            "configureReport" -> {
                DailyReport.configure(this, call.arguments as? Map<*, *>)
                result.success(null)
            }
            "requestNotifications" -> requestNotifications(result)
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("usage", error.message, null) }
            }
        }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotificationResult?.success(false)
        pendingNotificationResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
    }

    private companion object {
        const val NOTIFICATION_REQUEST = 4202
    }
}
