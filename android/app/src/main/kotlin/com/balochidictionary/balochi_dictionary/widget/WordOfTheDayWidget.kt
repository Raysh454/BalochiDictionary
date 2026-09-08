package com.balochidictionary.balochi_dictionary.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.balochidictionary.balochi_dictionary.R

/**
 * 2x2 widget showing a word of the day.
 *
 * Tapping it toggles between the offline Balochi dictionary and Rekhta's Urdu
 * word of the day. The choice is stored per widget instance, so two copies on
 * the home screen can show different sources.
 */
class WordOfTheDayWidget : DailyWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val widgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )
            if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                WidgetPrefs.setSource(
                    context,
                    widgetId,
                    WidgetPrefs.source(context, widgetId).toggled(),
                )
                renderAsync(context, intArrayOf(widgetId))
            }
            return
        }

        super.onReceive(context, intent)
    }

    /** Only fetches when a widget is actually showing the Rekhta side. */
    override fun refreshData(context: Context, widgetIds: IntArray): Boolean {
        val wantsRekhta = widgetIds.any {
            WidgetPrefs.source(context, it) == WordSource.REKHTA
        }
        if (!wantsRekhta || !RekhtaSource.isWordStale(context)) return false

        return RekhtaSource.refreshWord(context) != null
    }

    override fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_word)
        val source = WidgetPrefs.source(context, widgetId)

        val word = when (source) {
            WordSource.BALOCHI -> BalochiWordSource.wordOfTheDay(context)
            WordSource.REKHTA -> RekhtaSource.cachedWord(context)
        }

        views.setTextViewText(
            R.id.widget_label,
            context.getString(
                when (source) {
                    WordSource.BALOCHI -> R.string.widget_label_balochi
                    WordSource.REKHTA -> R.string.widget_label_urdu
                },
            ),
        )

        if (word == null) {
            views.setTextViewText(R.id.widget_script, "")
            views.setViewVisibility(R.id.widget_script, View.GONE)
            views.setViewVisibility(R.id.widget_latin, View.GONE)
            views.setTextViewText(R.id.widget_meaning, statusText(context, source))
            views.setTextViewText(R.id.widget_note, "")
            views.setViewVisibility(R.id.widget_note, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_script, View.VISIBLE)
            views.setTextViewText(R.id.widget_script, word.script)
            views.setTextViewText(R.id.widget_latin, word.latin)
            views.setTextViewText(R.id.widget_meaning, word.meaning)
            views.setTextViewText(R.id.widget_note, word.note)
            views.setViewVisibility(
                R.id.widget_latin,
                if (word.latin.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_note,
                if (word.note.isEmpty()) View.GONE else View.VISIBLE,
            )
        }

        // The whole surface is the toggle.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            broadcastIntent(context, ACTION_TOGGLE, widgetId),
        )

        return views
    }

    /**
     * Says what is going on when there is no word to show. Tapping switches
     * source rather than retrying, so this must not promise a retry.
     */
    private fun statusText(context: Context, source: WordSource): String {
        if (source == WordSource.BALOCHI) {
            return context.getString(R.string.widget_error_dictionary)
        }

        return context.getString(
            when (WidgetPrefs.lastFailure(context)) {
                FailureReason.NETWORK -> R.string.widget_status_offline
                FailureReason.MARKUP -> R.string.widget_status_markup
                null -> R.string.widget_status_loading
            },
        )
    }

    private companion object {
        const val ACTION_TOGGLE = "com.balochidictionary.balochi_dictionary.widget.TOGGLE_SOURCE"
    }
}
