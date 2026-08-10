package fan.astral.next.game

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class RoomsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rooms = parseRooms(widgetData.widgetString("rooms_json", "[]"))
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_rooms).apply {
                setTextViewText(
                    R.id.rooms_title,
                    context.getString(R.string.widget_rooms_title),
                )
                setTextViewText(
                    R.id.rooms_summary,
                    widgetData.widgetString(
                        "rooms_summary",
                        context.getString(R.string.widget_rooms_empty),
                    ),
                )
                bindLine(context, this, 1, rooms.getOrNull(0))
                bindLine(context, this, 2, rooms.getOrNull(1))
                bindLine(context, this, 3, rooms.getOrNull(2))
                val hasRooms = rooms.isNotEmpty()
                setViewVisibility(R.id.rooms_empty, if (hasRooms) View.GONE else View.VISIBLE)
                setTextViewText(
                    R.id.rooms_empty,
                    context.getString(R.string.widget_rooms_empty),
                )
            }
            WidgetThemeHelper.applyRooms(context, views, widgetData)
            WidgetClickHelper.attachLaunchIntent(
                context,
                views,
                R.id.widget_root,
                WidgetClickHelper.roomsUri(),
            )
            WidgetClickHelper.attachRefreshIntent(context, views, R.id.widget_refresh)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindLine(
        context: Context,
        views: RemoteViews,
        index: Int,
        room: RoomLine?,
    ) {
        val labelId = when (index) {
            1 -> R.id.rooms_line1
            2 -> R.id.rooms_line2
            else -> R.id.rooms_line3
        }
        val codeId = when (index) {
            1 -> R.id.rooms_line1_code
            2 -> R.id.rooms_line2_code
            else -> R.id.rooms_line3_code
        }
        val rowId = when (index) {
            1 -> R.id.rooms_row1
            2 -> R.id.rooms_row2
            else -> R.id.rooms_row3
        }
        if (room == null) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(labelId, room.label)
        views.setTextViewText(
            codeId,
            room.code.ifEmpty { context.getString(R.string.widget_rooms_no_code) },
        )
        WidgetClickHelper.attachLaunchIntent(
            context,
            views,
            rowId,
            WidgetClickHelper.roomUri(room.code.ifEmpty { room.networkName }, room.id),
        )
    }

    private fun parseRooms(json: String): List<RoomLine> {
        return try {
            val array = JSONArray(json)
            buildList {
                for (i in 0 until array.length().coerceAtMost(3)) {
                    val obj = array.getJSONObject(i)
                    add(
                        RoomLine(
                            label = obj.optString("label", "-"),
                            code = obj.optString("code", ""),
                            networkName = obj.optString("network", ""),
                            id = obj.optInt("id", -1).takeIf { it > 0 },
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private data class RoomLine(
        val label: String,
        val code: String,
        val networkName: String,
        val id: Int?,
    )
}
