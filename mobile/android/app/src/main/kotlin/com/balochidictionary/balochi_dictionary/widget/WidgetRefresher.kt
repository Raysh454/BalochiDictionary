package com.balochidictionary.balochi_dictionary.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.concurrent.Executors

/**
 * Runs the Rekhta refreshes and pushes the results to the widgets.
 *
 * Shared by the scheduled job and by the app itself. The app path matters:
 * background execution is the fragile part of all this. Power management can
 * deny a widget's receiver the network and can stop scheduled jobs running at
 * all, and on a phone that does both the widgets never fill in. A foreground
 * process has neither restriction, so opening the app is a guaranteed way to
 * get current content onto the home screen.
 */
object WidgetRefresher {
    private const val TAG = "WidgetRefresher"

    private val EXECUTOR = Executors.newSingleThreadExecutor()

    /**
     * Refreshes whatever is stale on a background thread, then redraws the
     * widgets. Safe to call from the main thread.
     */
    fun refreshAsync(context: Context, onFinished: ((succeeded: Boolean) -> Unit)? = null) {
        val appContext = context.applicationContext

        EXECUTOR.execute {
            var attempted = 0
            var succeeded = 0

            try {
                if (RekhtaSource.isWordStale(appContext)) {
                    attempted++
                    if (RekhtaSource.refreshWord(appContext) != null) succeeded++
                }
                if (RekhtaSource.isVerseStale(appContext)) {
                    attempted++
                    if (RekhtaSource.refreshVerse(appContext) != null) succeeded++
                }

                // Redraw either way: a failure has to replace the placeholder
                // with its recorded reason.
                redrawAll(appContext)
            } catch (error: Exception) {
                Log.w(TAG, "Widget refresh failed", error)
            } finally {
                onFinished?.invoke(attempted == 0 || succeeded > 0)
            }
        }
    }

    /** Tells both providers to redraw from whatever is now cached. */
    fun redrawAll(context: Context) {
        redraw(context, WordOfTheDayWidget::class.java)
        redraw(context, VerseWidget::class.java)
    }

    /**
     * A dedicated action is used rather than APPWIDGET_UPDATE so that redrawing
     * cannot schedule more work and loop.
     */
    private fun redraw(context: Context, provider: Class<*>) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isEmpty()) return

        context.sendBroadcast(
            Intent(context, provider)
                .setAction(DailyWidgetProvider.ACTION_REDRAW)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
        )
    }
}
