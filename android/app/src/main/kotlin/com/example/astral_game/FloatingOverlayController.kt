package com.example.astral_game

import android.content.Context
import android.content.Intent
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
    private const val CHANNEL = "com.example.astral_game/floating_overlay"

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var userListContainer: LinearLayout? = null
    private var emptyView: TextView? = null

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

    fun show(context: Context) {
        if (!canDrawOverlays(context)) return
        if (overlayView != null) return

        val appContext = context.applicationContext
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val inflater = LayoutInflater.from(appContext)
        val panel = inflater.inflate(R.layout.overlay_floating_panel, null)
        panel.setBackgroundColor(Color.TRANSPARENT)

        userListContainer = panel.findViewById(R.id.overlay_user_list)
        emptyView = panel.findViewById(R.id.overlay_empty)

        val params = WindowManager.LayoutParams(
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
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 120
        }

        wm.addView(panel, params)
        windowManager = wm
        overlayView = panel
    }

    fun hide() {
        val wm = windowManager ?: return
        val view = overlayView ?: return
        try {
            wm.removeView(view)
        } catch (_: Exception) {
        }
        overlayView = null
        userListContainer = null
        emptyView = null
        windowManager = null
    }

    fun update(context: Context, payloadJson: String) {
        if (overlayView == null) {
            show(context)
        }
        val list = userListContainer ?: return
        val empty = emptyView ?: return
        val inflater = LayoutInflater.from(context.applicationContext)

        val root = try {
            JSONObject(payloadJson)
        } catch (_: Exception) {
            JSONObject()
        }

        val connected = root.optBoolean("connected", false)
        val users = root.optJSONArray("users") ?: JSONArray()

        list.removeAllViews()
        if (!connected || users.length() == 0) {
            empty.visibility = View.VISIBLE
            empty.text = if (connected) {
                context.getString(R.string.overlay_empty)
            } else {
                context.getString(R.string.overlay_not_connected)
            }
            list.visibility = View.GONE
            return
        }

        empty.visibility = View.GONE
        list.visibility = View.VISIBLE

        for (i in 0 until users.length()) {
            val user = users.optJSONObject(i) ?: continue
            val row = inflater.inflate(R.layout.overlay_user_row, list, false)
            val ip = user.optString("ip", "—")
            val latencyMs = user.optDouble("latencyMs", 0.0).roundToInt()

            row.findViewById<TextView>(R.id.overlay_user_ip).text = ip
            row.findViewById<TextView>(R.id.overlay_user_latency).text = "${latencyMs}ms"

            val avatarView = row.findViewById<ImageView>(R.id.overlay_user_avatar)
            val avatarB64 = user.optString("avatarBase64", "")
            if (avatarB64.isNotEmpty()) {
                try {
                    val bytes = Base64.decode(avatarB64, Base64.DEFAULT)
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bitmap != null) {
                        avatarView.setImageBitmap(bitmap)
                    }
                } catch (_: Exception) {
                    avatarView.setImageDrawable(null)
                }
            } else {
                avatarView.setImageDrawable(null)
            }
            avatarView.setBackgroundResource(R.drawable.overlay_avatar_ring)

            list.addView(row)
        }
    }
}
