package fan.astral.next.game

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MembersWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val count = widgetData.widgetString("members_count_text", "")
            .toIntOrNull()
            ?: widgetData.getInt("members_count", 0)
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_members).apply {
                setTextViewText(
                    R.id.members_room,
                    widgetData.widgetString(
                        "members_room_label",
                        context.getString(R.string.widget_members_default_room),
                    ),
                )
                setTextViewText(
                    R.id.members_count,
                    context.getString(R.string.widget_members_count_fmt, count),
                )
                setTextViewText(
                    R.id.members_preview,
                    widgetData.widgetString(
                        "members_preview",
                        context.getString(R.string.widget_members_empty_hint),
                    ),
                )
            }
            WidgetThemeHelper.applyMembers(context, views, widgetData)
            WidgetClickHelper.attachLaunchIntent(
                context,
                views,
                R.id.widget_root,
                WidgetClickHelper.membersUri(),
            )
            WidgetClickHelper.attachRefreshIntent(context, views, R.id.widget_refresh)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
