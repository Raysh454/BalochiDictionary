package com.balochidictionary.balochi_dictionary.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import java.util.Calendar
import java.util.concurrent.Executors

/**
 * Shared plumbing for the daily widgets.
 *
 * Rendering can touch SQLite or the network, neither of which may run on the
 * main thread, so every update is moved onto a background executor and the
 * broadcast is kept alive with `goAsync()` until it finishes.
 *
 * Content rolls over at local midnight, so each update also schedules an
 * inexact alarm for the next midnight. `updatePeriodMillis` in the widget XML
 * is the safety net if that alarm is delayed or dropped.
 */
abstract class DailyWidgetProvider : AppWidgetProvider() {

    /**
     * Builds the views for one widget instance from data already on disk.
     * Must not touch the network: it runs before any refresh so the widget
     * paints immediately.
     */
    protected abstract fun buildViews(context: Context, widgetId: Int): RemoteViews

    /**
     * Schedules any network refresh this widget needs, after the cached views
     * are already on screen. Implementations must not fetch inline: a receiver
     * has only about ten seconds and is a poor place to ask for the network.
     * The work belongs in [WidgetRefreshJobService].
     */
    protected open fun scheduleRefresh(context: Context, widgetIds: IntArray) = Unit

    /** Action used for this provider's midnight alarm. */
    private val midnightAction: String
        get() = "${javaClass.name}.MIDNIGHT"

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        renderAsync(context, appWidgetIds)
        scheduleMidnight(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REDRAW) {
            val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            if (ids != null && ids.isNotEmpty()) renderAsync(context, ids, refresh = false)
            return
        }

        super.onReceive(context, intent)

        if (intent.action == midnightAction) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, javaClass),
            )
            renderAsync(context, ids)
            scheduleMidnight(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetPrefs.clearSource(context, it) }
    }

    /** Draws from cache, and schedules a fetch when [refresh] is set. */
    protected fun renderAsync(
        context: Context,
        widgetIds: IntArray,
        refresh: Boolean = true,
    ) {
        if (widgetIds.isEmpty()) return

        val pendingResult = goAsync()
        val appContext = context.applicationContext

        EXECUTOR.execute {
            try {
                val manager = AppWidgetManager.getInstance(appContext)

                // Paint what is already cached first, so the widget never sits
                // blank or stale while a fetch is in flight.
                draw(manager, appContext, widgetIds)

                if (refresh) scheduleRefresh(appContext, widgetIds)
            } catch (error: Exception) {
                Log.w(TAG, "Widget update failed", error)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun draw(
        manager: AppWidgetManager,
        context: Context,
        widgetIds: IntArray,
    ) {
        for (widgetId in widgetIds) {
            try {
                manager.updateAppWidget(widgetId, buildViews(context, widgetId))
            } catch (error: Exception) {
                Log.w(TAG, "Widget $widgetId failed to render", error)
            }
        }
    }

    /** Schedules the next refresh just after local midnight. */
    private fun scheduleMidnight(context: Context) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 30)
            set(Calendar.MILLISECOND, 0)
        }

        val intent = Intent(context, javaClass).setAction(midnightAction)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pending = PendingIntent.getBroadcast(context, javaClass.name.hashCode(), intent, flags)

        // Inexact on purpose: it needs no special permission and a few minutes
        // of drift on a once-a-day word does not matter.
        alarmManager.set(AlarmManager.RTC, next.timeInMillis, pending)
    }

    /** Builds a PendingIntent that broadcasts [action] back to this provider. */
    protected fun broadcastIntent(context: Context, action: String, widgetId: Int): PendingIntent {
        val intent = Intent(context, javaClass)
            .setAction(action)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // The widget id keeps the PendingIntents for separate instances distinct.
        return PendingIntent.getBroadcast(context, widgetId, intent, flags)
    }

    companion object {
        private const val TAG = "DailyWidgetProvider"

        /** Redraw from cache only; sent by [WidgetRefreshJobService]. */
        const val ACTION_REDRAW = "com.balochidictionary.balochi_dictionary.widget.REDRAW"
        private val EXECUTOR = Executors.newSingleThreadExecutor()
    }
}
