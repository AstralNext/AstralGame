package com.example.astral_game

import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * 从 home_widget 写入的主题色动态着色（与 Flutter AppThemePalette 一致）。
 */
object WidgetThemeHelper {
    private const val KEY_CARD = "theme_card"
    private const val KEY_CANVAS = "theme_canvas"
    private const val KEY_TEXT_PRIMARY = "theme_text_primary"
    private const val KEY_TEXT_SECONDARY = "theme_text_secondary"
    private const val KEY_ACCENT = "theme_accent"

    private const val DEFAULT_CARD = 0xFFFFFFFF.toInt()
    private const val DEFAULT_CANVAS = 0xFFF8F5F2.toInt()
    private const val DEFAULT_TEXT_PRIMARY = 0xFF3D3835.toInt()
    private const val DEFAULT_TEXT_SECONDARY = 0xFF9A918C.toInt()
    private const val DEFAULT_ACCENT = 0xFFBFA89E.toInt()

    data class Colors(
        val card: Int,
        val canvas: Int,
        val textPrimary: Int,
        val textSecondary: Int,
        val accent: Int,
    )

    fun read(prefs: SharedPreferences): Colors = Colors(
        card = readColor(prefs, KEY_CARD, DEFAULT_CARD),
        canvas = readColor(prefs, KEY_CANVAS, DEFAULT_CANVAS),
        textPrimary = readColor(prefs, KEY_TEXT_PRIMARY, DEFAULT_TEXT_PRIMARY),
        textSecondary = readColor(prefs, KEY_TEXT_SECONDARY, DEFAULT_TEXT_SECONDARY),
        accent = readColor(prefs, KEY_ACCENT, DEFAULT_ACCENT),
    )

    private fun readColor(prefs: SharedPreferences, key: String, fallback: Int): Int {
        if (!prefs.contains(key)) return fallback
        return when (val raw = prefs.all[key]) {
            is Int -> raw
            is Long -> raw.toInt()
            is String -> raw.toLongOrNull()?.toInt() ?: fallback
            else -> prefs.getInt(key, fallback)
        }
    }

    fun applyConnect(context: Context, views: RemoteViews, prefs: SharedPreferences) {
        val colors = read(prefs)
        paintCard(context, views, colors)
        tintSecondary(views, colors, R.id.widget_brand)
        tintPrimary(views, colors, R.id.connect_title)
        tintAccent(views, colors, R.id.connect_status)
        tintSecondary(views, colors, R.id.connect_code)
        paintChip(context, views, R.id.connect_hint_bg, colors.canvas)
        tintPrimary(views, colors, R.id.connect_hint)
    }

    fun applyRooms(context: Context, views: RemoteViews, prefs: SharedPreferences) {
        val colors = read(prefs)
        paintCard(context, views, colors)
        tintSecondary(views, colors, R.id.widget_brand)
        tintPrimary(views, colors, R.id.rooms_title)
        tintSecondary(views, colors, R.id.rooms_summary)
        tintPrimary(views, colors, R.id.rooms_line1)
        tintSecondary(views, colors, R.id.rooms_line1_code)
        tintPrimary(views, colors, R.id.rooms_line2)
        tintSecondary(views, colors, R.id.rooms_line2_code)
        tintPrimary(views, colors, R.id.rooms_line3)
        tintSecondary(views, colors, R.id.rooms_line3_code)
        tintSecondary(views, colors, R.id.rooms_empty)
    }

    fun applyMembers(context: Context, views: RemoteViews, prefs: SharedPreferences) {
        val colors = read(prefs)
        paintCard(context, views, colors)
        tintSecondary(views, colors, R.id.widget_brand)
        tintSecondary(views, colors, R.id.members_room)
        tintPrimary(views, colors, R.id.members_title)
        tintAccent(views, colors, R.id.members_count)
        paintChip(context, views, R.id.members_preview_bg, colors.canvas)
        tintPrimary(views, colors, R.id.members_preview)
    }

    private fun paintCard(context: Context, views: RemoteViews, colors: Colors) {
        views.setImageViewBitmap(
            R.id.widget_bg,
            WidgetBitmapFactory.cardBackground(context, colors.card),
        )
    }

    private fun paintChip(context: Context, views: RemoteViews, bgId: Int, color: Int) {
        views.setImageViewBitmap(
            bgId,
            WidgetBitmapFactory.chipBackground(context, color),
        )
    }

    private fun tintPrimary(views: RemoteViews, colors: Colors, viewId: Int) {
        views.setInt(viewId, "setTextColor", colors.textPrimary)
    }

    private fun tintSecondary(views: RemoteViews, colors: Colors, viewId: Int) {
        views.setInt(viewId, "setTextColor", colors.textSecondary)
    }

    private fun tintAccent(views: RemoteViews, colors: Colors, viewId: Int) {
        views.setInt(viewId, "setTextColor", colors.accent)
    }
}
