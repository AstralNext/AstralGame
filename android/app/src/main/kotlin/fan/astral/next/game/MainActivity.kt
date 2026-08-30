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
import java.io.File
import java.io.FileOutputStream
import java.net.URL

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                "createPinnedShortcut" -> {
                    createPinnedShortcut(call, result)
                }
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
        val iconAsset = call.argument<String>("iconAsset")
        val gameColor = call.argument<Int>("gameColor")

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

            val icon = buildShortcutIcon(iconAsset, gameColor)

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

    private fun buildShortcutIcon(iconAsset: String?, gameColor: Int?): Icon {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint().apply {
            color = gameColor ?: 0xFF6B7280.toInt()
            isAntiAlias = true
        }
        // 先画背景色
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)

        // 尝试下载并叠加游戏图标
        iconAsset?.let { asset ->
            try {
                val ref = parseMediaRef(asset)
                val bmp = when (ref) {
                    is MediaRef.Network -> downloadBitmap(ref.url)
                    is MediaRef.Asset -> loadAssetBitmap(ref.path)
                }
                if (bmp != null) {
                    val scaled = Bitmap.createScaledBitmap(bmp, size - 16, size - 16, true)
                    canvas.drawBitmap(scaled, 8f, 8f, Paint().apply { isAntiAlias = true })
                }
            } catch (_: Exception) {}
        }

        return Icon.createWithBitmap(bitmap)
    }

    private fun parseMediaRef(raw: String): MediaRef {
        val s = raw.trim()
        return when {
            s.startsWith("http://") || s.startsWith("https://") -> MediaRef.Network(s)
            else -> MediaRef.Asset(s)
        }
    }

    private fun downloadBitmap(url: String): Bitmap? {
        return try {
            val conn = URL(url).openConnection()
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            BitmapFactory.decodeStream(conn.getInputStream())
        } catch (_: Exception) { null }
    }

    private fun loadAssetBitmap(path: String): Bitmap? {
        return try {
            val normalized = if (path.startsWith("assets/")) path else "assets/$path"
            val stream = assets.open(normalized)
            BitmapFactory.decodeStream(stream)
        } catch (_: Exception) { null }
    }

    sealed class MediaRef {
        data class Network(val url: String) : MediaRef()
        data class Asset(val path: String) : MediaRef()
    }
}

