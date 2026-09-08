package com.balochidictionary.balochi_dictionary.widget

import android.content.Context
import android.util.Log
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/**
 * Scrapes Rekhta's daily word and daily couplet.
 *
 * Rekhta publishes no public API, so both come from the server-rendered
 * homepages. That makes this the fragile part of the widgets: if Rekhta
 * changes their markup the selectors below stop matching. Every step degrades
 * to a cached value rather than throwing, so a failure shows stale content
 * instead of an error.
 *
 * The fetch deliberately uses [HttpURLConnection] rather than
 * `Jsoup.connect()`. jsoup ships as a multi-release jar whose HTTP helpers sit
 * under `META-INF/versions/9/`, and Android ignores versioned entries, so
 * jsoup's own networking is not dependable here. jsoup is used purely as a
 * parser, which is plain Java and safe on Android.
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

    /**
     * Kept well under the ten seconds or so a broadcast receiver gets before
     * the system may kill it, even if both timeouts are hit on one request.
     */
    private const val CONNECT_TIMEOUT_MS = 4_000
    private const val READ_TIMEOUT_MS = 5_000
    private const val MAX_REDIRECTS = 3

    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120.0.0.0 Mobile Safari/537.36"

    // --- cached reads; these never touch the network ------------------------

    fun cachedWord(context: Context): DailyWord? = WidgetPrefs.cachedRekhtaWord(context)

    fun cachedVerse(context: Context): DailyVerse? = WidgetPrefs.cachedVerse(context)

    fun isWordStale(context: Context): Boolean = !WidgetPrefs.isRekhtaWordFresh(context)

    fun isVerseStale(context: Context): Boolean = !WidgetPrefs.isVerseFresh(context)

    // --- network refreshes --------------------------------------------------

    /**
     * Fetches today's word, storing it on success. Falls back to the cached
     * value and records why it failed so the widget can say something useful.
     */
    fun refreshWord(context: Context): DailyWord? {
        try {
            val word = parseWord(Jsoup.parse(fetchHtml(DICTIONARY_URL), DICTIONARY_URL))
            if (word == null) {
                WidgetPrefs.storeFailure(context, FailureReason.MARKUP)
                Log.w(TAG, "Rekhta word markup no longer matches the expected selectors")
            } else {
                WidgetPrefs.storeRekhtaWord(context, word)
                return word
            }
        } catch (error: Exception) {
            WidgetPrefs.storeFailure(context, FailureReason.NETWORK)
            Log.w(TAG, "Rekhta word fetch failed", error)
        }

        return cachedWord(context)
    }

    /** Fetches today's couplet, with the same store-and-fall-back behaviour. */
    fun refreshVerse(context: Context): DailyVerse? {
        try {
            val verse = parseVerse(Jsoup.parse(fetchHtml(POETRY_URL), POETRY_URL))
            if (verse == null) {
                WidgetPrefs.storeFailure(context, FailureReason.MARKUP)
                Log.w(TAG, "Rekhta verse markup no longer matches the expected selectors")
            } else {
                WidgetPrefs.storeVerse(context, verse)
                return verse
            }
        } catch (error: Exception) {
            WidgetPrefs.storeFailure(context, FailureReason.NETWORK)
            Log.w(TAG, "Rekhta verse fetch failed", error)
        }

        return cachedVerse(context)
    }

    /**
     * Downloads a page as text.
     *
     * Redirects are followed by hand because [HttpURLConnection] will not
     * follow them across protocols, and gzip is requested explicitly since
     * these pages run to roughly 350 KB uncompressed.
     */
    internal fun fetchHtml(startUrl: String): String {
        var url = URL(startUrl)

        repeat(MAX_REDIRECTS + 1) {
            val connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", "text/html,application/xhtml+xml")
                setRequestProperty("Accept-Encoding", "gzip")
                setRequestProperty("Accept-Language", "ur,en;q=0.8")
            }

            try {
                val status = connection.responseCode

                if (status in 300..399) {
                    val location = connection.getHeaderField("Location")
                        ?: throw IllegalStateException("redirect $status carried no Location")
                    url = URL(url, location)
                    return@repeat
                }

                if (status != HttpURLConnection.HTTP_OK) {
                    throw IllegalStateException("HTTP $status from $url")
                }

                val stream: InputStream =
                    if (connection.contentEncoding.equals("gzip", ignoreCase = true)) {
                        GZIPInputStream(connection.inputStream)
                    } else {
                        connection.inputStream
                    }

                return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            } finally {
                connection.disconnect()
            }
        }

        throw IllegalStateException("too many redirects from $startUrl")
    }

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
     * </div>
     * <div class="sherDetail"><a href="/poets/...">بسمل سنسہاروی گیاوی</a></div>
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

/** Why the last Rekhta refresh produced nothing. */
enum class FailureReason {
    /** The request never completed: offline, blocked, or timed out. */
    NETWORK,

    /** The page loaded but no longer matches the selectors. */
    MARKUP,
}
