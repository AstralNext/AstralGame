package fan.astral.next.game

import android.content.SharedPreferences

/** Normalize SharedPreferences.getString nullability across API levels. */
fun SharedPreferences.widgetString(key: String, default: String = ""): String =
    getString(key, default) ?: default
