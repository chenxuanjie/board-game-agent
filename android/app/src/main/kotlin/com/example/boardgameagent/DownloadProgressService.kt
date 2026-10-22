package com.example.boardgameagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.ResultReceiver
import android.os.SystemClock

/** Download-only foreground priority. The existing Dart owner still performs
 * transport, cache commits and APK validation. All mutations run on main looper. */
class DownloadProgressService : Service() {
    companion object {
        const val CHANNEL = "board_game_downloads_v1"
        var active: DownloadProgressService? = null
            private set
        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "资料与应用下载", NotificationManager.IMPORTANCE_LOW)
                )
            }
        }
    }
    private data class Transfer(val id: Int, val title: String, var message: String,
        var completed: Long = 0, var total: Long = 0,
        val startedAt: Long = SystemClock.elapsedRealtime())
    private val transfers = linkedMapOf<String, Transfer>()
    private var foregroundId: Int? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    // Longer than the existing APK 10-minute/library 15-minute deadlines.
    private val safetyStop = Runnable { stopExpired() }
    private val manager get() = getSystemService(NotificationManager::class.java)

    override fun onCreate() {
        super.onCreate()
        active = this
        createChannel(this)
    }
    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val receiver = intent?.getParcelableExtra<ResultReceiver>("receiver")
        val key = intent?.getStringExtra("id")
        if (key != "apk" && key != "library") {
            receiver?.send(1, null)
            stopSelf()
            return START_NOT_STICKY
        }
        val request = intent ?: return START_NOT_STICKY
        val transfer = Transfer(if (key == "apk") 4101 else 4102,
            request.getStringExtra("title") ?: "下载更新",
            request.getStringExtra("message") ?: "正在下载",
            total = request.getLongExtra("total", 0))
        transfers[key] = transfer
        try {
            if (foregroundId == null) promote(transfer) else manager.notify(transfer.id, notification(transfer))
            if (wakeLock == null) {
                wakeLock = getSystemService(PowerManager::class.java).newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK, "$packageName:downloads"
                ).apply { setReferenceCounted(false) }
            }
            if (wakeLock?.isHeld == true) wakeLock?.release()
            wakeLock?.acquire(16 * 60 * 1000L)
            scheduleSafetyStop()
            receiver?.send(0, null)
        } catch (_: Exception) {
            transfers.remove(key)
            receiver?.send(1, null)
            if (transfers.isEmpty()) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        // No misleading restarted service after the Dart transfer owner dies.
        return START_NOT_STICKY
    }

    private fun promote(transfer: Transfer) {
        val notification = notification(transfer)
        if (Build.VERSION.SDK_INT >= 29) startForeground(transfer.id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(transfer.id, notification)
        foregroundId = transfer.id
    }

    fun update(args: Map<String, Any?>) {
        val transfer = transfers[args["id"]] ?: return
        transfer.message = args["message"] as? String ?: transfer.message
        transfer.completed = ((args["completed"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0)
        transfer.total = ((args["total"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0)
        manager.notify(transfer.id, notification(transfer))
    }

    fun finish(args: Map<String, Any?>) {
        val transfer = transfers.remove(args["id"]) ?: return
        transfer.message = args["message"] as? String ?: "下载已结束"
        if (foregroundId == transfer.id) {
            stopForeground(STOP_FOREGROUND_DETACH)
            foregroundId = null
            transfers.values.firstOrNull()?.let { promote(it) }
        }
        manager.notify(transfer.id, notification(transfer, terminal = true))
        if (transfers.isEmpty()) stopSelf()
    }

    @Suppress("DEPRECATION") // API 24/25 have no notification channels.
    private fun notification(transfer: Transfer, terminal: Boolean = false): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(this, transfer.id, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(transfer.title).setContentText(transfer.message)
            .setContentIntent(pending).setOnlyAlertOnce(true)
            .setOngoing(!terminal).setAutoCancel(terminal)
            .setPriority(Notification.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_PROGRESS)
        if (!terminal) {
            val percent = if (transfer.total > 0)
                (transfer.completed.toDouble() / transfer.total * 100).toInt().coerceIn(0, 100) else 0
            builder.setProgress(100, percent, transfer.total <= 0)
        }
        return builder.build()
    }

    private fun stopInterrupted() {
        for (key in transfers.keys.toList()) finish(mapOf("id" to key, "message" to "下载已中断，请返回应用重试"))
        stopSelf()
    }
    private fun scheduleSafetyStop() {
        handler.removeCallbacks(safetyStop)
        val earliest = transfers.values.minOfOrNull { it.startedAt } ?: return
        handler.postDelayed(safetyStop, (earliest + 16 * 60 * 1000L - SystemClock.elapsedRealtime()).coerceAtLeast(1))
    }
    private fun stopExpired() {
        val now = SystemClock.elapsedRealtime()
        for ((key, transfer) in transfers.toMap()) {
            if (now - transfer.startedAt >= 16 * 60 * 1000L) {
                finish(mapOf("id" to key, "message" to "下载超时，请返回应用重试"))
            }
        }
        scheduleSafetyStop()
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopInterrupted() }
    override fun onTaskRemoved(rootIntent: Intent?) { stopInterrupted(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        handler.removeCallbacks(safetyStop)
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (active === this) active = null
        // Interruption must not leave a permanently 'downloading' notification.
        for (transfer in transfers.values) {
            transfer.message = "下载已中断，请返回应用重试"
            manager.notify(transfer.id, notification(transfer, terminal = true))
        }
        transfers.clear()
        super.onDestroy()
    }
}
