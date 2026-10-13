package com.example.boardgameagent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver

class MainActivity : FlutterActivity() {
    private var pendingPermission: Pair<Map<String, Any?>, MethodChannel.Result>? = null
    private val permissionRequest = 4100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "board_game_agent/download_progress").setMethodCallHandler { call, result ->
            val args = (call.arguments as? Map<*, *>)?.entries?.associate {
                it.key.toString() to it.value
            } ?: emptyMap()
            if (args["id"] !in listOf("library", "apk")) {
                result.error("invalid_task", "Unknown download task", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (pendingPermission != null) {
                            result.error("permission_pending", "Notification permission pending", null)
                        } else {
                            pendingPermission = args to result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
                        }
                    } else startDownload(args, result)
                }
                "progress" -> {
                    DownloadProgressService.active?.update(args)
                    result.success(null)
                }
                "finish" -> {
                    pendingPermission?.takeIf { it.first["id"] == args["id"] }?.let {
                        pendingPermission = null
                        it.second.error("cancelled", "Download start cancelled", null)
                    }
                    DownloadProgressService.active?.finish(args)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startDownload(args: Map<String, Any?>, result: MethodChannel.Result) {
        val manager = getSystemService(NotificationManager::class.java)
        DownloadProgressService.createChannel(this)
        if (!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 26 &&
                manager.getNotificationChannel(DownloadProgressService.CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE)) {
            result.error("notifications_disabled", "Enable download notifications in settings", null)
            return
        }
        val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
            override fun onReceiveResult(code: Int, data: Bundle?) {
                if (code == 0) result.success(null)
                else result.error("foreground_failed", "Unable to start foreground download", null)
            }
        }
        val intent = Intent(this, DownloadProgressService::class.java)
            .putExtra("id", args["id"] as String)
            .putExtra("title", args["title"] as? String ?: "下载更新")
            .putExtra("message", args["message"] as? String ?: "正在下载")
            .putExtra("total", (args["total"] as? Number)?.toLong() ?: 0L)
            .putExtra("receiver", receiver)
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {
            result.error("foreground_failed", "Unable to start foreground download", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startDownload(pending.first, pending.second)
        else pending.second.error("permission_denied", "Notification permission denied", null)
    }

    override fun onDestroy() {
        pendingPermission?.second?.error("activity_closed", "Activity closed", null)
        pendingPermission = null
        super.onDestroy()
    }
}
