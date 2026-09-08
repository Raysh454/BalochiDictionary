package com.balochidictionary.balochi_dictionary.widget

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle
import android.util.Log
import java.util.concurrent.Executors

/**
 * Fetches Rekhta's pages as a scheduled job rather than inside the widget
 * broadcast.
 *
 * A BroadcastReceiver gets roughly ten seconds even while holding
 * `goAsync()`, which forces timeouts short enough that a phone waking a cold
 * radio can miss them, and background network from a receiver is exactly what
 * aggressive power management restricts. A job with a network constraint is
 * the mechanism the platform expects: it is granted network, it is given a
 * generous window, and it simply waits rather than failing when the device is
 * offline.
 *
 * [JobScheduler] is used directly instead of WorkManager. WorkManager is a
 * wrapper over this same machinery whose persistence is backed by Room, and
 * Room's shrinker rules do not survive R8 full mode, which crashed the app at
 * startup. Nothing here is persisted across reboots, so the wrapper bought
 * nothing that would justify the risk.
 */
class WidgetRefreshJobService : JobService() {

    override fun onStartJob(params: JobParameters): Boolean {
        val target = params.extras.getString(KEY_TARGET) ?: TARGET_BOTH

        WidgetRefresher.refreshAsync(applicationContext) { succeeded ->
            // Ask to be run again only if the fetch actually failed; the
            // scheduler applies its own backoff.
            jobFinished(params, !succeeded)
        }

        // Work continues on the refresher's executor.
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true

    /**
     * Asks a provider to redraw from the freshly stored cache.
     *
     * A dedicated action is used rather than APPWIDGET_UPDATE so redrawing
     * cannot schedule another job and loop.
     */
    private fun redraw(provider: Class<*>) {
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
        private const val TAG = "WidgetRefreshJob"
        private const val KEY_TARGET = "target"

        /** onStartJob runs on the main thread, so the fetch is handed off. */
        private val EXECUTOR = Executors.newSingleThreadExecutor()

        const val TARGET_WORD = "word"
        const val TARGET_VERSE = "verse"
        const val TARGET_BOTH = "both"

        // Stable per target, so re-scheduling replaces a pending run rather
        // than stacking duplicates.
        private const val JOB_ID_WORD = 4101
        private const val JOB_ID_VERSE = 4102
        private const val JOB_ID_BOTH = 4103

        /**
         * Schedules a refresh to run as soon as the device has a network.
         * Replaces any pending run for the same target.
         */
        fun schedule(context: Context, target: String) {
            val scheduler =
                context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return

            val jobId = when (target) {
                TARGET_WORD -> JOB_ID_WORD
                TARGET_VERSE -> JOB_ID_VERSE
                else -> JOB_ID_BOTH
            }

            // An already-pending job for this target is left alone, so repeated
            // widget updates do not keep resetting its backoff.
            if (scheduler.allPendingJobs.any { it.id == jobId }) return

            val info = JobInfo.Builder(
                jobId,
                ComponentName(context, WidgetRefreshJobService::class.java),
            )
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setExtras(PersistableBundle().apply { putString(KEY_TARGET, target) })
                // Run promptly once there is a network, but do not demand it
                // this instant; the scheduler batches these sensibly.
                .setOverrideDeadline(REFRESH_DEADLINE_MS)
                .build()

            runCatching { scheduler.schedule(info) }
                .onFailure { Log.w(TAG, "Could not schedule the widget refresh", it) }
        }

        /** Upper bound before the job runs regardless of batching. */
        private const val REFRESH_DEADLINE_MS = 10 * 60 * 1000L
    }
}
