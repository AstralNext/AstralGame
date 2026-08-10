package fan.astral.next.game

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
                else -> result.notImplemented()
            }
        }
    }
}
