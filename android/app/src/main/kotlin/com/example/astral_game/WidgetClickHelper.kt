package com.example.astral_game

import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

object WidgetClickHelper {
    fun attachLaunchIntent(
        context: Context,
        views: RemoteViews,
        rootId: Int,
    ) {
        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
        )
        views.setOnClickPendingIntent(rootId, pendingIntent)
    }
}
