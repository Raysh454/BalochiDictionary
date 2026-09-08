package com.balochidictionary.balochi_dictionary.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import com.balochidictionary.balochi_dictionary.R

/**
 * 4x2 widget showing Rekhta's couplet of the day in Urdu, with its poet.
 *
 * The layout carries no header and no tags: the sher and the attribution are
 * the whole design. Tapping opens rekhta.org, where the couplet sits in
 * context.
 */
class VerseWidget : DailyWidgetProvider() {

    override fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_verse)
        val verse = RekhtaSource.verseOfTheDay(context)

        if (verse == null) {
            views.setTextViewText(
                R.id.verse_line_one,
                context.getString(R.string.widget_error_network),
            )
            views.setTextViewText(R.id.verse_line_two, "")
            views.setTextViewText(R.id.verse_poet, "")
        } else {
            views.setTextViewText(R.id.verse_line_one, verse.lineOne)
            views.setTextViewText(R.id.verse_line_two, verse.lineTwo)
            views.setTextViewText(R.id.verse_poet, verse.poet)
        }

        views.setOnClickPendingIntent(R.id.verse_root, openRekhta(context))
        return views
    }

    private fun openRekhta(context: Context): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(RekhtaSource.POETRY_URL))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        return PendingIntent.getActivity(context, 0, intent, flags)
    }
}
