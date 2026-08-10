package fan.astral.next.game

import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent

object WidgetClickHelper {
    fun attachLaunchIntent(
        context: Context,
        views: RemoteViews,
        rootId: Int,
        uri: Uri,
    ) {
        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            uri,
        )
        views.setOnClickPendingIntent(rootId, pendingIntent)
    }

    fun attachRefreshIntent(
        context: Context,
        views: RemoteViews,
        buttonId: Int,
    ) {
        val pendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("astralgame://widget/refresh"),
        )
        views.setOnClickPendingIntent(buttonId, pendingIntent)
    }

    fun connectUri(): Uri = Uri.parse("astralgame://widget/connect")

    fun roomsUri(): Uri = Uri.parse("astralgame://widget/rooms")

    fun membersUri(): Uri = Uri.parse("astralgame://widget/members")

    fun roomUri(code: String, id: Int?): Uri {
        val builder = Uri.parse("astralgame://widget/rooms").buildUpon()
        if (code.isNotEmpty()) builder.appendQueryParameter("code", code)
        if (id != null) builder.appendQueryParameter("id", id.toString())
        return builder.build()
    }
}
