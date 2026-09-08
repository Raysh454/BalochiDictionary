package com.balochidictionary.balochi_dictionary.widget

import android.content.Context
import android.util.Log
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/**
 * Scrapes Rekhta's daily word and daily couplet.
 *
 * Rekhta publishes no public API, so both come from the server-rendered
 * homepages. That makes this the fragile part of the widgets: if Rekhta
 * changes their markup the selectors below stop matching. Every parse step
 * therefore degrades to null rather than throwing, and the widgets fall back to
 * the last cached value, so a markup change shows stale content instead of an
 * error.
 *
 * Each page is fetched at most once per calendar day.
 */
object RekhtaSource {
    private const val TAG = "RekhtaSource"

    const val DICTIONARY_URL = "https://rekhtadictionary.com/"

    /**
     * The Urdu edition of the homepage. It serves the identical DOM to the
     * default page but with the couplet, the word and the poet in Urdu script
     * rather than Roman transliteration, so the same selectors work.
     */
    const val POETRY_URL = "https://www.rekhta.org/?lang=ur"

    private const val TIMEOUT_MS = 15_000
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120.0.0.0 Mobile Safari/537.36"

    /**
     * Today's Rekhta word, fetching only if the cache is stale.
     * Returns the cached value on any network or parse failure.
     */
    fun wordOfTheDay(context: Context): DailyWord? {
        if (WidgetPrefs.isRekhtaWordFresh(context)) {
            WidgetPrefs.cachedRekhtaWord(context)?.let { return it }
        }

        val fetched = runCatching { parseWord(fetch(DICTIONARY_URL)) }
            .onFailure { Log.w(TAG, "Rekhta word fetch failed", it) }
            .getOrNull()

        if (fetched != null) {
            WidgetPrefs.storeRekhtaWord(context, fetched)
            return fetched
        }

        return WidgetPrefs.cachedRekhtaWord(context)
    }

    /** Today's Rekhta couplet, with the same cache-and-fallback behaviour. */
    fun verseOfTheDay(context: Context): DailyVerse? {
        if (WidgetPrefs.isVerseFresh(context)) {
            WidgetPrefs.cachedVerse(context)?.let { return it }
        }

        val fetched = runCatching { parseVerse(fetch(POETRY_URL)) }
            .onFailure { Log.w(TAG, "Rekhta verse fetch failed", it) }
            .getOrNull()

        if (fetched != null) {
            WidgetPrefs.storeVerse(context, fetched)
            return fetched
        }

        return WidgetPrefs.cachedVerse(context)
    }

    private fun fetch(url: String): Document =
        Jsoup.connect(url)
            .userAgent(USER_AGENT)
            .timeout(TIMEOUT_MS)
            .followRedirects(true)
            .get()

    /**
     * rekhtadictionary.com markup:
     *
     * ```
     * <div class='rdDailywordBlok'>
     *   <h3><a href='/meaning-of-mahsuul'><span>mahsuul</span></a></h3>
     *   <h4><span>महसूल</span><strong>•</strong><span>مَحْصُول</span></h4>
     *   <p><span class='rdWrdOrigin'>Origin</span> - Arabic</p>
     *   <div class='rdDailymeaningBlock'><p>Meaning</p><h3>tax, duty, ...</h3></div>
     * </div>
     * ```
     */
    internal fun parseWord(document: Document): DailyWord? {
        val block = document.selectFirst("div.rdDailywordBlok") ?: return null

        val latin = block.selectFirst("h3 a span")?.text()?.trim().orEmpty()
        // The h4 holds Devanagari then Urdu, separated by a bullet; take the last
        // span so the Urdu script is what the widget shows.
        val scripts = block.select("h4 span").map { it.text().trim() }.filter { it.isNotEmpty() }
        val urdu = scripts.lastOrNull().orEmpty()

        val meaning = document.selectFirst("div.rdDailymeaningBlock h3")?.text()?.trim().orEmpty()
        if (latin.isEmpty() && urdu.isEmpty()) return null
        if (meaning.isEmpty()) return null

        // "Origin - Arabic" arrives as a label span plus a trailing text node.
        val origin = block.selectFirst("span.rdWrdOrigin")?.parent()?.text()?.trim().orEmpty()

        return DailyWord(
            script = urdu.ifEmpty { latin },
            latin = latin,
            meaning = meaning,
            note = origin,
        )
    }

    /**
     * rekhta.org markup: the word of the day is illustrated by a couplet.
     *
     * ```
     * <span class="h1-word">رسائی</span>
     * <div class="engMeaning"><p>معنی</p><h3>پہنچ، باریابی، ...</h3></div>
     * <div class="wordInSher">
     *   <div class='pMC' data-roman='off'>... <p data-l='1'>..</p><p data-l='2'>..</p></div>
     *   <div class='pMC' data-roman='on'> ... plain roman ... </div>
     *   <div class="sherDetail"><a href="/poets/...">Bismil Sunsaharvi Gayawi</a></div>
     * </div>
     * ```
     */
    internal fun parseVerse(document: Document): DailyVerse? {
        val sher = document.selectFirst("div.wordInSher") ?: return null

        // Prefer the diacritical transliteration (data-roman='off'); fall back to
        // whichever block is present.
        val couplet = sher.selectFirst("div.pMC[data-roman=off]")
            ?: sher.selectFirst("div.pMC")
            ?: return null

        val lines = couplet.select("p[data-l]").map { it.text().trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return null

        // The attribution sits alongside the couplet rather than inside it, so
        // it is looked up in the surrounding word-of-the-day section. Scoping
        // matters: the homepage carries other couplets with their own poets.
        // The attribute value must be quoted -- jsoup cannot parse an unquoted
        // selector value containing a slash.
        val scope = document.selectFirst("section.sectionWord") ?: sher.parent() ?: document
        val poet = scope.selectFirst("div.sherDetail a[href^='/poets/']")?.text()?.trim()
            ?: scope.selectFirst("div.sherDetail a")?.text()?.trim()
            ?: ""

        return DailyVerse(
            lineOne = lines.getOrElse(0) { "" },
            lineTwo = lines.getOrElse(1) { "" },
            poet = poet,
            word = document.selectFirst("span.h1-word")?.text()?.trim().orEmpty(),
            meaning = document.selectFirst("div.engMeaning h3")?.text()?.trim().orEmpty(),
        )
    }
}
