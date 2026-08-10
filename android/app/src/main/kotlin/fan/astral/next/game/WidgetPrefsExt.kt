package fan.astral.next.game

import android.content.SharedPreferences

/** [SharedPreferences.getString] 在较�?API 上返回可空类型，统一回落默认值�?*/
fun SharedPreferences.widgetString(key: String, default: String = ""): String =
    getString(key, default) ?: default
