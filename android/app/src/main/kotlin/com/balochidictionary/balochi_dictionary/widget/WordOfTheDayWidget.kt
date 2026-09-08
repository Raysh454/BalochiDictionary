package com.balochidictionary.balochi_dictionary.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
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

    override fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_word)
        val source = WidgetPrefs.source(context, widgetId)

        val word = when (source) {
            WordSource.BALOCHI -> BalochiWordSource.wordOfTheDay(context)
            WordSource.REKHTA -> RekhtaSource.wordOfTheDay(context)
        }

        val label = when (source) {
            WordSource.BALOCHI -> context.getString(R.string.widget_label_balochi)
            WordSource.REKHTA -> context.getString(R.string.widget_label_urdu)
        }
        views.setTextViewText(R.id.widget_label, label)

        if (word == null) {
            views.setTextViewText(R.id.widget_script, "—")
            views.setTextViewText(R.id.widget_latin, "")
            views.setTextViewText(
                R.id.widget_meaning,
                context.getString(
                    if (source == WordSource.REKHTA) {
                        R.string.widget_error_network
                    } else {
                        R.string.widget_error_dictionary
                    },
                ),
            )
            views.setTextViewText(R.id.widget_note, "")
        } else {
            views.setTextViewText(R.id.widget_script, word.script)
            views.setTextViewText(R.id.widget_latin, word.latin)
            views.setTextViewText(R.id.widget_meaning, word.meaning)
            views.setTextViewText(R.id.widget_note, word.note)
            views.setViewVisibility(
                R.id.widget_note,
                if (word.note.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_latin,
                if (word.latin.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
            )
        }

        // The whole surface is the toggle.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            broadcastIntent(context, ACTION_TOGGLE, widgetId),
        )

        return views
    }

    private companion object {
        const val ACTION_TOGGLE = "com.balochidictionary.balochi_dictionary.widget.TOGGLE_SOURCE"
    }
}
