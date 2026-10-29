package com.example.boardgameagent

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.net.URI

/** Optional, anonymous publication reminders. No account credentials are used. */
object PublicReminder {
    private const val PREFS = "public_reminder_v1"
    const val CHANNEL = "board_public_releases_v1"
    const val CATALOG_ID = 5121
    const val RELEASE_ID = 5122
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun start(context: Context, reconnect: Boolean = false) {
        val intent = Intent(context, PublicRealtimeService::class.java)
        if (reconnect) intent.action = PublicRealtimeService.ACTION_RECONNECT
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
        else context.startService(intent)
    }

    fun validOrigin(raw: String): String {
        val uri = URI(raw)
        require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo == null &&
            uri.query == null && uri.fragment == null && (uri.path.isNullOrEmpty() || uri.path == "/"))
        return URI("https", null, uri.host.lowercase(), uri.port, null, null, null).toASCIIString()
    }

    @Synchronized
    fun configure(context: Context, rawOrigin: String, checkUpdates: Boolean) {
        val origin = validOrigin(rawOrigin)
        val p = prefs(context)
        val changed = p.getString("origin", null) != origin
        val updated = p.getBoolean("check_updates", true) != checkUpdates
        if (!changed && !updated) return
        val editor = p.edit().putString("origin", origin).putBoolean("check_updates", checkUpdates)
            .putLong("generation", p.getLong("generation", 0) + 1)
        if (changed) editor.remove("catalog_revision").remove("release_build")
        check(editor.commit())
        if (changed) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(CATALOG_ID)
            manager.cancel(RELEASE_ID)
        }
        if (p.getBoolean("enabled", false)) {
            try {
                start(context, reconnect = true)
            } catch (_: Exception) { /* The next foreground launch can restart it. */ }
        }
    }

    fun enabled(context: Context): Boolean = prefs(context).getBoolean("enabled", false)

    @Synchronized
    fun enable(context: Context, onComplete: (Boolean) -> Unit) {
        val p = prefs(context)
        require(!p.getString("origin", null).isNullOrEmpty())
        createChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        check(manager.areNotificationsEnabled())
        if (Build.VERSION.SDK_INT >= 26) {
            check(manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
        }
        val requestId = p.getLong("enable_request", 0) + 1
        check(p.edit().putBoolean("enabled", true).putLong("enable_request", requestId)
            .putLong("generation", p.getLong("generation", 0) + 1).commit())
        try {
            start(context)
            onComplete(true)
        } catch (error: Exception) {
            rollbackEnable(context, requestId)
            throw error
        }
    }

    @Synchronized
    private fun rollbackEnable(context: Context, requestId: Long) {
        val p = prefs(context)
        if (p.getLong("enable_request", 0) != requestId) return
        p.edit().putBoolean("enabled", false)
            .putLong("generation", p.getLong("generation", 0) + 1).commit()
    }

    @Synchronized
    fun disable(context: Context) {
        val p = prefs(context)
        check(p.edit().putBoolean("enabled", false)
            .putLong("enable_request", p.getLong("enable_request", 0) + 1)
            .putLong("generation", p.getLong("generation", 0) + 1).commit())
        context.stopService(Intent(context, PublicRealtimeService::class.java))
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(CATALOG_ID)
        manager.cancel(RELEASE_ID)
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "资料与版本提醒", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    fun state(context: Context): Map<String, Any> {
        val manager = context.getSystemService(NotificationManager::class.java)
        val permission = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(
            Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channel = Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
        return mapOf("enabled" to enabled(context), "allowed" to (permission && manager.areNotificationsEnabled() && channel))
    }

    @Synchronized
    fun snapshot(context: Context): Triple<String, Long, Boolean>? {
        val p = prefs(context)
        if (!p.getBoolean("enabled", false)) return null
        val origin = p.getString("origin", null) ?: return null
        return Triple(origin, p.getLong("generation", 0), p.getBoolean("check_updates", true))
    }

    fun current(context: Context, origin: String, generation: Long): Boolean {
        val p = prefs(context)
        return p.getBoolean("enabled", false) && p.getString("origin", null) == origin && p.getLong("generation", 0) == generation
    }

    fun longValue(context: Context, key: String): Long? {
        val p = prefs(context)
        return if (p.contains(key)) p.getLong(key, 0) else null
    }

    @Synchronized
    fun applyCatalog(context: Context, origin: String, generation: Long, revision: Long,
        show: () -> Boolean): Boolean {
        if (!current(context, origin, generation)) return true
        val old = longValue(context, "catalog_revision")
        when (PublicReminderPolicy.catalog(old, revision)) {
            PublicReminderPolicy.Decision.IGNORE -> return true
            PublicReminderPolicy.Decision.NOTIFY -> if (!show()) return false
            PublicReminderPolicy.Decision.SAVE -> Unit
        }
        return prefs(context).edit().putLong("catalog_revision", revision).commit()
    }

    @Synchronized
    fun applyRelease(context: Context, origin: String, generation: Long, build: Long,
        installed: Long, show: () -> Boolean): Boolean {
        if (!current(context, origin, generation) || !prefs(context).getBoolean("check_updates", true)) return true
        val old = longValue(context, "release_build")
        when (PublicReminderPolicy.release(old, build, installed)) {
            PublicReminderPolicy.Decision.IGNORE -> return true
            PublicReminderPolicy.Decision.NOTIFY -> if (!show()) return false
            PublicReminderPolicy.Decision.SAVE -> Unit
        }
        return prefs(context).edit().putLong("release_build", build).commit()
    }
}
