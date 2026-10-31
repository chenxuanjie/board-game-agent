package com.example.boardgameagent

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** A visible, user-enabled service. Android may stop it under background limits. */
class PublicRealtimeService : Service() {
    private var engine: FlutterEngine? = null
    private var destroyed = false

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(SERVICE_CHANNEL, "NAS 实时连接", NotificationManager.IMPORTANCE_LOW))
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = launch?.let { PendingIntent.getActivity(this, 0, it,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, SERVICE_CHANNEL)
            else Notification.Builder(this)
        startForeground(SERVICE_ID, builder.setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle("桌游导师正在接收 NAS 更新")
            .setContentText("关闭后台提醒可停止此连接")
            .setContentIntent(pending).setOngoing(true).build())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (PublicReminder.snapshot(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_RECONNECT) {
            engine?.destroy()
            engine = null
        }
        if (engine == null) startEngine()
        return START_STICKY
    }

    private fun startEngine() {
        try {
            val flutterEngine = FlutterEngine(applicationContext)
            engine = flutterEngine
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "settings" -> {
                                val snapshot = PublicReminder.snapshot(this)
                                if (snapshot == null) result.error("disabled", "Reminders disabled", null)
                                else result.success(mapOf("origin" to snapshot.first, "generation" to snapshot.second))
                            }
                            "publications" -> {
                                val origin = call.argument<String>("origin") ?: ""
                                val generation = call.argument<Number>("generation")?.toLong() ?: -1
                                val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                                if (items.size > 256) throw IllegalArgumentException("Too many publications")
                                for (item in items) accept(origin, generation, item)
                                result.success(null)
                            }
                            "started" -> result.success(null)
                            "waiting" -> result.success(null)
                            "failed" -> { result.success(null); stopSelf() }
                            else -> result.notImplemented()
                        }
                    } catch (_: Exception) { result.error("reminder_failed", "Unable to process publication", null) }
                }
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            flutterEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "publicReminderMain"))
        } catch (_: Exception) { stopSelf() }
    }

    private fun accept(origin: String, generation: Long, item: Map<String, Any?>) {
        if (destroyed || !PublicReminder.current(this, origin, generation)) return
        val revision = (item["revision"] as? Number)?.toLong() ?: return
        if (revision < 0) return
        when (item["topic"]) {
            "catalog" -> PublicReminder.applyCatalog(this, origin, generation, revision) {
                notifyUser(PublicReminder.CATALOG_ID, "桌游资料有更新 · NAS 实时连接", "打开桌游导师查看最新资料")
            }
            "release" -> {
                val supported = mutableSetOf<String>()
                if (Build.SUPPORTED_ABIS.contains("arm64-v8a")) supported.add("arm64")
                if (Build.SUPPORTED_ABIS.contains("armeabi-v7a")) supported.add("arm")
                if (Build.SUPPORTED_ABIS.contains("x86_64")) supported.add("x64")
                if (Build.SUPPORTED_ABIS.contains("x86")) supported.add("x86")
                if (!PublicReminderPolicy.matchesAndroidRelease(item["channel"], item["platform"], item["architecture"], supported)) return
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(packageName, 0)
                @Suppress("DEPRECATION")
                val installed = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                PublicReminder.applyRelease(this, origin, generation, revision, installed) {
                    notifyUser(PublicReminder.RELEASE_ID, "发现应用新版本 · NAS 实时连接", "打开桌游导师检查更新")
                }
            }
        }
    }

    private fun notifyUser(id: Int, title: String, text: String): Boolean {
        PublicReminder.createChannel(this)
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        if (PublicReminder.state(this)["allowed"] != true) return false
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(this, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, PublicReminder.CHANNEL) else Notification.Builder(this)
        getSystemService(NotificationManager::class.java).notify(id, builder.setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(title).setContentText(text).setContentIntent(pending).setAutoCancel(true).build())
        return true
    }

    override fun onDestroy() {
        destroyed = true
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) { stopSelf() }
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_RECONNECT = "com.example.boardgameagent.RECONNECT_PUBLIC_REMINDERS"
        private const val CHANNEL = "board_game_agent/realtime_reminders_service"
        private const val SERVICE_CHANNEL = "board_public_connection_v1"
        private const val SERVICE_ID = 5120
    }
}
