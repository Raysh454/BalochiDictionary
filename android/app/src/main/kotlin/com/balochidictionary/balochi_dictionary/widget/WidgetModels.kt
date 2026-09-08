package com.balochidictionary.balochi_dictionary.widget

import android.content.Context
import java.util.Calendar
import java.util.TimeZone

/** A dictionary word rendered by the 2x2 widget. */
data class DailyWord(
    /** Headword in its native script (Balochi or Urdu). */
    val script: String,
    /** Latin transliteration. */
    val latin: String,
    /** English gloss. */
    val meaning: String,
    /** Extra line: part of speech for Balochi, word origin for Rekhta. */
    val note: String = "",
)

/** The couplet rendered by the 4x2 widget. */
data class DailyVerse(
    val lineOne: String,
    val lineTwo: String,
    val poet: String,
    /** The rekhta.org word this couplet illustrates, if known. */
    val word: String = "",
    val meaning: String = "",
)

/** Which source the 2x2 widget is currently showing. */
enum class WordSource {
    BALOCHI,
    REKHTA;

    fun toggled(): WordSource = if (this == BALOCHI) REKHTA else BALOCHI
}

/**
 * Widget state and the Rekhta response cache.
 *
 * Rekhta is scraped at most once per calendar day per widget; everything else
 * renders from this cache so the home screen never waits on the network.
 */
object WidgetPrefs {
    private const val FILE = "balochi_widget_prefs"

    private const val KEY_SOURCE_PREFIX = "source_"
    private const val KEY_REKHTA_WORD = "rekhta_word"
    private const val KEY_REKHTA_LATIN = "rekhta_latin"
    private const val KEY_REKHTA_MEANING = "rekhta_meaning"
    private const val KEY_REKHTA_NOTE = "rekhta_note"
    private const val KEY_REKHTA_DAY = "rekhta_day"
    private const val KEY_VERSE_ONE = "verse_one"
    private const val KEY_VERSE_TWO = "verse_two"
    private const val KEY_VERSE_POET = "verse_poet"
    private const val KEY_VERSE_WORD = "verse_word"
    private const val KEY_VERSE_MEANING = "verse_meaning"
    private const val KEY_VERSE_DAY = "verse_day"
    private const val KEY_LAST_FAILURE = "last_failure"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Days since the Unix epoch for today's local calendar date.
     *
     * The local calendar fields are reinterpreted as UTC, matching
     * `WordOfTheDayService.daysSinceEpoch` in the Dart code so both sides pick
     * the same word on the same day.
     */
    fun todayEpochDay(): Long {
        val local = Calendar.getInstance()
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        utc.clear()
        utc.set(
            local.get(Calendar.YEAR),
            local.get(Calendar.MONTH),
            local.get(Calendar.DAY_OF_MONTH),
        )
        return utc.timeInMillis / 86_400_000L
    }

    // --- 2x2 toggle state, kept per widget instance -------------------------

    fun source(context: Context, widgetId: Int): WordSource {
        val name = prefs(context).getString(KEY_SOURCE_PREFIX + widgetId, null)
        return if (name == WordSource.REKHTA.name) WordSource.REKHTA else WordSource.BALOCHI
    }

    fun setSource(context: Context, widgetId: Int, source: WordSource) {
        prefs(context).edit().putString(KEY_SOURCE_PREFIX + widgetId, source.name).apply()
    }

    fun clearSource(context: Context, widgetId: Int) {
        prefs(context).edit().remove(KEY_SOURCE_PREFIX + widgetId).apply()
    }

    // --- Why the last refresh produced nothing ------------------------------

    fun storeFailure(context: Context, reason: FailureReason) {
        prefs(context).edit().putString(KEY_LAST_FAILURE, reason.name).apply()
    }

    fun lastFailure(context: Context): FailureReason? =
        prefs(context).getString(KEY_LAST_FAILURE, null)
            ?.let { name -> FailureReason.entries.firstOrNull { it.name == name } }

    private fun clearFailure(context: Context) {
        prefs(context).edit().remove(KEY_LAST_FAILURE).apply()
    }

    // --- Rekhta word cache --------------------------------------------------

    fun cachedRekhtaWord(context: Context): DailyWord? {
        val p = prefs(context)
        val script = p.getString(KEY_REKHTA_WORD, null) ?: return null
        return DailyWord(
            script = script,
            latin = p.getString(KEY_REKHTA_LATIN, "").orEmpty(),
            meaning = p.getString(KEY_REKHTA_MEANING, "").orEmpty(),
            note = p.getString(KEY_REKHTA_NOTE, "").orEmpty(),
        )
    }

    fun isRekhtaWordFresh(context: Context): Boolean =
        prefs(context).getLong(KEY_REKHTA_DAY, Long.MIN_VALUE) == todayEpochDay()

    fun storeRekhtaWord(context: Context, word: DailyWord) {
        prefs(context).edit()
            .putString(KEY_REKHTA_WORD, word.script)
            .putString(KEY_REKHTA_LATIN, word.latin)
            .putString(KEY_REKHTA_MEANING, word.meaning)
            .putString(KEY_REKHTA_NOTE, word.note)
            .putLong(KEY_REKHTA_DAY, todayEpochDay())
            .apply()
        clearFailure(context)
    }

    // --- Verse cache --------------------------------------------------------

    fun cachedVerse(context: Context): DailyVerse? {
        val p = prefs(context)
        val one = p.getString(KEY_VERSE_ONE, null) ?: return null
        return DailyVerse(
            lineOne = one,
            lineTwo = p.getString(KEY_VERSE_TWO, "").orEmpty(),
            poet = p.getString(KEY_VERSE_POET, "").orEmpty(),
            word = p.getString(KEY_VERSE_WORD, "").orEmpty(),
            meaning = p.getString(KEY_VERSE_MEANING, "").orEmpty(),
        )
    }

    fun isVerseFresh(context: Context): Boolean =
        prefs(context).getLong(KEY_VERSE_DAY, Long.MIN_VALUE) == todayEpochDay()

    fun storeVerse(context: Context, verse: DailyVerse) {
        prefs(context).edit()
            .putString(KEY_VERSE_ONE, verse.lineOne)
            .putString(KEY_VERSE_TWO, verse.lineTwo)
            .putString(KEY_VERSE_POET, verse.poet)
            .putString(KEY_VERSE_WORD, verse.word)
            .putString(KEY_VERSE_MEANING, verse.meaning)
            .putLong(KEY_VERSE_DAY, todayEpochDay())
            .apply()
        clearFailure(context)
    }
}
