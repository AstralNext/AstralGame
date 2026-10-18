package fan.astral.next.game

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 悬浮窗 channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FloatingOverlayController.channelName(),
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    result.success(FloatingOverlayController.canDrawOverlays(this))
                }
                "openOverlayPermissionSettings" -> {
                    FloatingOverlayController.openOverlayPermissionSettings(this)
                    result.success(null)
                }
                "showOverlay" -> {
                    result.success(FloatingOverlayController.show(this))
                }
                "hideOverlay" -> {
                    FloatingOverlayController.hide()
                    result.success(null)
                }
                "updateOverlay" -> {
                    val json = call.argument<String>("payload")
                    if (json != null) {
                        FloatingOverlayController.update(this, json)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 通知栏 channel（前台服务通知权限与样式）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fan.astral.next.game/notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureNotificationPermission" -> ensureNotificationPermission(result)
                "refreshVpnNotification" -> {
                    postVpnNotification()
                    result.success(null)
                }
                "cancelVpnNotification" -> {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE)
                        as NotificationManager
                    manager.cancel(VPN_NOTIFICATION_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 桌面快捷方式 channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "astral.game/shortcut",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createPinnedShortcut" -> createPinnedShortcut(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.success(false)
            return
        }
        pendingNotificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    /// 用本地化文案和点击跳转覆盖插件创建的前台服务通知（同一 channel / id）。
    private fun postVpnNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                VPN_NOTIFICATION_CHANNEL_ID,
                "Astral 连接",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "虚拟局域网运行状态"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            it.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            PendingIntent.getActivity(this, 0, it, pendingFlags)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, VPN_NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle("Astral 已连接")
            .setContentText("虚拟局域网正在运行")
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        contentIntent?.let { builder.setContentIntent(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(
                Notification.FOREGROUND_SERVICE_IMMEDIATE,
            )
        }
        manager.notify(VPN_NOTIFICATION_ID, builder.build())
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createPinnedShortcut(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val id = call.argument<String>("id") ?: run {
            result.error("BAD_ARGS", "缺少 id", null); return
        }
        val label = call.argument<String>("label") ?: run {
            result.error("BAD_ARGS", "缺少 label", null); return
        }
        val url = call.argument<String>("url") ?: run {
            result.error("BAD_ARGS", "缺少 url", null); return
        }
        val iconBytes = call.argument<ByteArray>("iconBytes")
        val gameColor = call.argument<Number>("gameColor")?.toInt()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Android 8.0 以下不支持 requestPinShortcut", null)
            return
        }

        val sm = getSystemService(SHORTCUT_SERVICE) as ShortcutManager
        if (!sm.isRequestPinShortcutSupported) {
            result.error("UNSUPPORTED", "桌面启动器不支持固定快捷方式", null)
            return
        }

        try {
            val pinIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                setClass(this@MainActivity, MainActivity::class.java)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val icon = buildShortcutIcon(iconBytes, gameColor)

            val shortcut = ShortcutInfo.Builder(this, id)
                .setShortLabel(label)
                .setLongLabel(label)
                .setIcon(icon)
                .setIntent(pinIntent)
                .build()

            // 不需要等待桌面回调：桌面会瞬间创建（或弹窗由系统处理），
            // 返回值即代表桌面是否接受了这次固定请求。
            val pinned = sm.requestPinShortcut(shortcut, null)
            result.success(pinned)
        } catch (e: SecurityException) {
            result.error("NO_PERMISSION", e.message ?: "没有创建桌面快捷方式的权限", null)
        } catch (e: Exception) {
            result.error("FAILED", e.message, null)
        }
    }

    private fun buildShortcutIcon(iconBytes: ByteArray?, gameColor: Int?): Icon {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // 有图标：直接铺满整个图标
        var drewIcon = false
        iconBytes?.let { bytes ->
            try {
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bmp != null) {
                    val scaled = Bitmap.createScaledBitmap(bmp, size, size, true)
                    canvas.drawBitmap(scaled, 0f, 0f, Paint().apply { isAntiAlias = true; isFilterBitmap = true })
                    drewIcon = true
                }
            } catch (_: Exception) {}
        }

        // 没有图标：用纯色填充
        if (!drewIcon) {
            val paint = Paint().apply {
                color = gameColor ?: 0xFF6B7280.toInt()
            }
            canvas.drawPaint(paint)
        }

        return Icon.createWithBitmap(bitmap)
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 4101
        private const val VPN_NOTIFICATION_CHANNEL_ID = "astral_vpn"
        private const val VPN_NOTIFICATION_ID = 1
    }
}

