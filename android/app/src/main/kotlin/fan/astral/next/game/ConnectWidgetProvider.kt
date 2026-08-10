package fan.astral.next.game

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ConnectWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val status = widgetData.widgetString(
                "connect_status",
                context.getString(R.string.widget_connect_default_status),
            )
            val connected = status == "???"
            val views = RemoteViews(context.packageName, R.layout.widget_connect).apply {
                setTextViewText(
                    R.id.connect_title,
                    widgetData.widgetString(
                        "connect_room_label",
                        context.getString(R.string.widget_connect_default_title),
                    ),
                )
                setTextViewText(R.id.connect_status, status)
                setTextViewText(
                    R.id.connect_code,
                    widgetData.widgetString("connect_room_code"),
                )
                setTextViewText(
                    R.id.connect_hint,
                    widgetData.widgetString(
                        "connect_hint",
                        context.getString(R.string.widget_connect_tap_hint),
                    ),
                )
                setTextViewText(
                    R.id.connect_action,
                    if (connected) {
                        context.getString(R.string.widget_connect_action_open)
                    } else {
                        context.getString(R.string.widget_connect_action_join)
                    },
                )
            }
            WidgetThemeHelper.applyConnect(context, views, widgetData)
            if (connected) {
                views.setInt(R.id.connect_status, "setTextColor", Color.parseColor("#4CAF50"))
            }
            WidgetClickHelper.attachLaunchIntent(
                context,
                views,
                R.id.widget_root,
                WidgetClickHelper.connectUri(),
            )
            WidgetClickHelper.attachRefreshIntent(context, views, R.id.widget_refresh)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
