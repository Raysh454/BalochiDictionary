package com.balochidictionary.balochi_dictionary.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Fetches Rekhta's pages away from the widget broadcast.
 *
 * A BroadcastReceiver, even one holding `goAsync()`, gets only about ten
 * seconds before the system may kill the process. Downloading a ~370 KB page
 * and parsing it can exceed that on a phone, and a process killed mid-fetch
 * stores neither content nor a failure, which leaves the widget showing its
 * "fetching" placeholder forever with nothing to explain it.
 *
 * WorkManager has no such deadline, waits for a usable network, and retries
 * with backoff, so all network work happens here and the providers only ever
 * render from cache.
 */
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        val target = inputData.getString(KEY_TARGET) ?: TARGET_BOTH
        var wanted = 0
        var got = 0

        if (target == TARGET_WORD || target == TARGET_BOTH) {
            if (RekhtaSource.isWordStale(applicationContext)) {
                wanted++
                if (RekhtaSource.refreshWord(applicationContext) != null) got++
            }
        }

        if (target == TARGET_VERSE || target == TARGET_BOTH) {
            if (RekhtaSource.isVerseStale(applicationContext)) {
                wanted++
                if (RekhtaSource.refreshVerse(applicationContext) != null) got++
            }
        }

        // Redraw either way: on failure the widgets need to swap the "fetching"
        // placeholder for the recorded reason.
        notify(WordOfTheDayWidget::class.java)
        notify(VerseWidget::class.java)

        // Let WorkManager back off and try again if nothing came back, unless
        // this has already been retried several times.
        return when {
            wanted == 0 || got == wanted -> Result.success()
            runAttemptCount < MAX_ATTEMPTS -> Result.retry()
            else -> Result.success()
        }
    }

    /**
     * Tells a provider to redraw from the freshly stored cache.
     *
     * A dedicated action is used rather than APPWIDGET_UPDATE so that redrawing
     * cannot enqueue this worker again and loop.
     */
    private fun notify(provider: Class<*>) {
        val manager = AppWidgetManager.getInstance(applicationContext)
        val ids = manager.getAppWidgetIds(ComponentName(applicationContext, provider))
        if (ids.isEmpty()) return

        applicationContext.sendBroadcast(
            Intent(applicationContext, provider)
                .setAction(DailyWidgetProvider.ACTION_REDRAW)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
        )
    }

    companion object {
        private const val KEY_TARGET = "target"
        private const val MAX_ATTEMPTS = 3

        const val TARGET_WORD = "word"
        const val TARGET_VERSE = "verse"
        const val TARGET_BOTH = "both"

        /**
         * Queues a refresh, keeping any run already pending for the same target
         * so repeated widget updates cannot pile up duplicate fetches.
         */
        fun enqueue(context: Context, target: String) {
            val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
                .setInputData(Data.Builder().putString(KEY_TARGET, target).build())
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "rekhta-refresh-$target",
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
