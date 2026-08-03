package com.example.astral_game

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
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
            val views = RemoteViews(context.packageName, R.layout.widget_connect).apply {
                setTextViewText(
                    R.id.connect_title,
                    widgetData.widgetString(
                        "connect_room_label",
                        context.getString(R.string.widget_connect_default_title),
                    ),
                )
                setTextViewText(
                    R.id.connect_status,
                    widgetData.widgetString(
                        "connect_status",
                        context.getString(R.string.widget_connect_default_status),
                    ),
                )
                setTextViewText(
                    R.id.connect_code,
                    widgetData.widgetString("connect_room_code"),
                )
                setTextViewText(
                    R.id.connect_hint,
                    widgetData.widgetString("connect_hint"),
                )
            }
            WidgetThemeHelper.applyConnect(context, views, widgetData)
            WidgetClickHelper.attachLaunchIntent(context, views, R.id.widget_root)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
