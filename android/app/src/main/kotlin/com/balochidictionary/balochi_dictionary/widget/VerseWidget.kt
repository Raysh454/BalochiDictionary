package com.balochidictionary.balochi_dictionary.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.balochidictionary.balochi_dictionary.R

/**
 * 4x2 widget showing Rekhta's couplet of the day with its poet.
 *
 * Tapping it opens rekhta.org, since the couplet is theirs and the full poem
 * is worth reading in context.
 */
class VerseWidget : DailyWidgetProvider() {

    override fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_verse)
        val verse = RekhtaSource.verseOfTheDay(context)

        views.setTextViewText(R.id.verse_label, context.getString(R.string.widget_label_verse))

        if (verse == null) {
            views.setTextViewText(R.id.verse_line_one, context.getString(R.string.widget_error_network))
            views.setTextViewText(R.id.verse_line_two, "")
            views.setTextViewText(R.id.verse_poet, "")
            views.setViewVisibility(R.id.verse_meaning, View.GONE)
        } else {
            views.setTextViewText(R.id.verse_line_one, verse.lineOne)
            views.setTextViewText(R.id.verse_line_two, verse.lineTwo)
            views.setTextViewText(
                R.id.verse_poet,
                if (verse.poet.isEmpty()) "" else "— ${verse.poet}",
            )

            // The couplet illustrates Rekhta's word of the day; show it when there
            // is something to show.
            val gloss = when {
                verse.word.isEmpty() -> ""
                verse.meaning.isEmpty() -> verse.word
                else -> "${verse.word} · ${verse.meaning}"
            }
            views.setTextViewText(R.id.verse_meaning, gloss)
            views.setViewVisibility(
                R.id.verse_meaning,
                if (gloss.isEmpty()) View.GONE else View.VISIBLE,
            )
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
