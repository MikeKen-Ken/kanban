package com.mikeken.kanban

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_WIDGET_SYNC = "com.mikeken.kanban.WIDGET_SYNC"
        private const val KEY_PENDING_WIDGET_SYNC = "pending_widget_sync"
    }

    private val notificationsChannel = "com.mikeken.kanban/notifications"
    private val appUpdateChannel = "com.mikeken.kanban/app_update"
    private val homeWidgetChannel = "com.mikeken.kanban/home_widget"
    private var widgetMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.action == ACTION_WIDGET_SYNC) {
            markWidgetSyncPending()
            intent.action = Intent.ACTION_MAIN
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_WIDGET_SYNC) {
            markWidgetSyncPending()
            intent.action = Intent.ACTION_MAIN
            widgetMethodChannel?.invokeMethod("syncRequested", null)
        }
        setIntent(intent)
    }

    private fun markWidgetSyncPending() {
        getSharedPreferences(KanbanWidgetStore.PREFS_NAME, MODE_PRIVATE)
            .edit().putBoolean(KEY_PENDING_WIDGET_SYNC, true).apply()
    }

    private fun consumeWidgetSyncPending(): Boolean {
        val prefs = getSharedPreferences(KanbanWidgetStore.PREFS_NAME, MODE_PRIVATE)
        val pending = prefs.getBoolean(KEY_PENDING_WIDGET_SYNC, false)
        if (pending) prefs.edit().remove(KEY_PENDING_WIDGET_SYNC).apply()
        return pending
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appUpdateChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }
                "openUnknownSourcesSettings" -> {
                    openUnknownSourcesSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "缺少 path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(path)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            homeWidgetChannel,
        )
        widgetMethodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateProjects" -> {
                    val json = call.argument<String>("json")
                    if (json.isNullOrBlank()) {
                        result.error("invalid_args", "Missing json", null)
                        return@setMethodCallHandler
                    }
                    try {
                        KanbanWidgetStore(this).saveProjects(json)
                        KanbanHomeWidgetProvider.updateAll(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("update_failed", e.message, null)
                    }
                }
                "consumePendingSync" -> result.success(consumeWidgetSyncPending())
                else -> result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
        }
        startActivity(intent)
    }

    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openUnknownSourcesSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } else {
            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("APK 不存在: $path")
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
