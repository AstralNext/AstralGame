package fan.astral.next.game

import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.res.Resources
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

object FloatingOverlayController {
    private const val CHANNEL = "fan.astral.next.game/floating_overlay"
    private const val MARGIN_START_DP = 12
    private const val MARGIN_TOP_DP = 8

    private var appContext: Context? = null
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var userListContainer: LinearLayout? = null
    private var emptyView: TextView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var componentCallbacks: ComponentCallbacks? = null
    private val renderedRows = mutableListOf<RenderedRow>()

    private data class RenderedRow(
        val ipView: TextView,
        val latencyView: TextView,
        val avatarView: ImageView,
        var avatarKey: String,
    )

    fun channelName(): String = CHANNEL

    fun canDrawOverlays(context: Context): Boolean =
        Settings.canDrawOverlays(context.applicationContext)

    fun openOverlayPermissionSettings(context: Context) {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun show(context: Context): Boolean {
        val ctx = context.applicationContext
        if (!canDrawOverlays(ctx)) {
            hide()
            return false
        }
        if (overlayView?.isAttachedToWindow == true) return true
        // 静态引用可能因窗口 token 失效而脱离，先清理再重建。
        hide()

        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val inflater = LayoutInflater.from(ctx)
        val panel = inflater.inflate(R.layout.overlay_floating_panel, null)
        panel.setBackgroundColor(Color.TRANSPARENT)

        val list = panel.findViewById<LinearLayout>(R.id.overlay_user_list)
        val empty = panel.findViewById<TextView>(R.id.overlay_empty)
        val params = createLayoutParams(ctx)
        applyPosition(ctx, params)

        try {
            wm.addView(panel, params)
        } catch (_: Exception) {
            return false
        }

        appContext = ctx
        windowManager = wm
        overlayView = panel
        userListContainer = list
        emptyView = empty
        layoutParams = params
        registerConfigurationListener(ctx)
        return true
    }

    fun hide() {
        val wm = windowManager
        val view = overlayView
        if (wm != null && view != null) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {
            }
        }
        componentCallbacks?.let { callbacks ->
            try {
                appContext?.unregisterComponentCallbacks(callbacks)
            } catch (_: Exception) {
            }
        }
        componentCallbacks = null
        appContext = null
        overlayView = null
        userListContainer = null
        emptyView = null
        windowManager = null
        layoutParams = null
        renderedRows.clear()
    }

    fun update(context: Context, payloadJson: String) {
        if (overlayView?.isAttachedToWindow != true) {
            if (!show(context)) return
        }
        val list = userListContainer ?: return
        val empty = emptyView ?: return

        val root = try {
            JSONObject(payloadJson)
        } catch (_: Exception) {
            JSONObject()
        }

        val connected = root.optBoolean("connected", false)
        val users = root.optJSONArray("users") ?: JSONArray()

        if (!connected || users.length() == 0) {
            empty.visibility = View.VISIBLE
            empty.text = if (connected) {
                context.getString(R.string.overlay_empty)
            } else {
                context.getString(R.string.overlay_not_connected)
            }
            list.visibility = View.GONE
            list.removeAllViews()
            renderedRows.clear()
            return
        }

        empty.visibility = View.GONE
        list.visibility = View.VISIBLE

        // 用户数不变时原地刷新延迟，避免每次轮询重建视图导致闪烁和头像重复解码。
        if (renderedRows.size == users.length()) {
            for (i in 0 until users.length()) {
                val user = users.optJSONObject(i) ?: continue
                bindRow(renderedRows[i], user)
            }
            return
        }

        rebuildRows(context, list, users)
    }

    private fun rebuildRows(context: Context, list: LinearLayout, users: JSONArray) {
        list.removeAllViews()
        renderedRows.clear()
        val inflater = LayoutInflater.from(context.applicationContext)
        for (i in 0 until users.length()) {
            val user = users.optJSONObject(i) ?: continue
            val row = inflater.inflate(R.layout.overlay_user_row, list, false)
            val holder = RenderedRow(
                ipView = row.findViewById(R.id.overlay_user_ip),
                latencyView = row.findViewById(R.id.overlay_user_latency),
                avatarView = row.findViewById(R.id.overlay_user_avatar),
                avatarKey = "",
            )
            bindRow(holder, user)
            list.addView(row)
            renderedRows.add(holder)
        }
    }

    private fun bindRow(holder: RenderedRow, user: JSONObject) {
        val ip = user.optString("ip", "-")
        if (holder.ipView.text.toString() != ip) {
            holder.ipView.text = ip
        }

        val latencyMs = user.optDouble("latencyMs", 0.0).roundToInt()
        val latencyText = if (latencyMs > 0) "${latencyMs}ms" else "--"
        if (holder.latencyView.text.toString() != latencyText) {
            holder.latencyView.text = latencyText
        }

        val avatarB64 = user.optString("avatarBase64", "")
        if (avatarB64 == holder.avatarKey) return
        holder.avatarKey = avatarB64
        if (avatarB64.isEmpty()) {
            holder.avatarView.setImageDrawable(null)
            return
        }
        try {
            val bytes = Base64.decode(avatarB64, Base64.DEFAULT)
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            holder.avatarView.setImageBitmap(bitmap)
        } catch (_: Exception) {
            holder.avatarView.setImageDrawable(null)
        }
    }

    private fun createLayoutParams(context: Context): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
    }

    private fun applyPosition(context: Context, params: WindowManager.LayoutParams) {
        params.x = dp(context, MARGIN_START_DP)
        params.y = statusBarHeight(context) + dp(context, MARGIN_TOP_DP)
    }

    private fun registerConfigurationListener(context: Context) {
        if (componentCallbacks != null) return
        val callbacks = object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) {
                val wm = windowManager ?: return
                val view = overlayView ?: return
                val params = layoutParams ?: return
                applyPosition(context, params)
                try {
                    wm.updateViewLayout(view, params)
                } catch (_: Exception) {
                }
            }

            override fun onLowMemory() {}
        }
        context.registerComponentCallbacks(callbacks)
        componentCallbacks = callbacks
    }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).roundToInt()

    private fun statusBarHeight(context: Context): Int {
        val res: Resources = context.resources
        val id = res.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) {
            res.getDimensionPixelSize(id)
        } else {
            dp(context, 24)
        }
    }
}
