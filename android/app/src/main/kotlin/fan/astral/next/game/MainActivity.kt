package fan.astral.next.game

import android.content.Intent
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    FloatingOverlayController.show(this)
                    result.success(null)
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

            val pinned = sm.requestPinShortcut(shortcut, null)
            result.success(pinned)
        } catch (e: Exception) {
            result.error("NO_PERMISSION", e.message, null)
        }
    }

    private fun buildShortcutIcon(iconBytes: ByteArray?, gameColor: Int?): Icon {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // 圆形裁剪区域，图标会铺满整个圆
        val circlePath = android.graphics.Path().apply {
            addCircle(size / 2f, size / 2f, size / 2f, android.graphics.Path.Direction.CW)
        }
        canvas.clipPath(circlePath)

        // 先画背景色（填满圆形）
        val bgPaint = Paint().apply {
            color = gameColor ?: 0xFF6B7280.toInt()
            isAntiAlias = true
        }
        canvas.drawPaint(bgPaint)

        // Flutter 端已经解析好了真实图标 bytes，直接 decode 并铺满
        iconBytes?.let { bytes ->
            try {
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bmp != null) {
                    // 铺满整个 96x96（不再缩小 + 偏移）
                    val scaled = Bitmap.createScaledBitmap(bmp, size, size, true)
                    canvas.drawBitmap(scaled, 0f, 0f, Paint().apply { isAntiAlias = true; isFilterBitmap = true })
                }
            } catch (_: Exception) {}
        }

        return Icon.createWithBitmap(bitmap)
    }
}

