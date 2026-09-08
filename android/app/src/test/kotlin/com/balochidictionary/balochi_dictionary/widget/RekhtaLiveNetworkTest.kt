package com.balochidictionary.balochi_dictionary.widget

import java.net.InetAddress
import org.jsoup.Jsoup
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Hits Rekhta for real and checks the selectors still match today's pages.
 *
 * The fixture-based tests prove the parsers are correct against frozen markup;
 * this one is the early warning that the live site has moved. It skips rather
 * than fails when there is no network, so an offline build stays green.
 *
 * It also exercises [RekhtaSource.fetchHtml] itself, which is the code the
 * widgets rely on: plain HttpURLConnection, since jsoup's own networking lives
 * in multi-release jar entries that Android ignores.
 */
class RekhtaLiveNetworkTest {

    private fun online(): Boolean = runCatching {
        InetAddress.getByName("rekhta.org").hostAddress != null
    }.getOrDefault(false)

    @Test
    fun `fetches and parses the live word of the day`() {
        assumeTrue("no network", online())

        val html = RekhtaSource.fetchHtml(RekhtaSource.DICTIONARY_URL)
        assertTrue("page looks too small: ${html.length} chars", html.length > 10_000)

        val word = RekhtaSource.parseWord(Jsoup.parse(html, RekhtaSource.DICTIONARY_URL))

        assertTrue("selectors no longer match rekhtadictionary.com", word != null)
        assertTrue("word has no meaning", word!!.meaning.isNotBlank())
        println("live word: ${word.script} / ${word.latin} = ${word.meaning}")
    }

    @Test
    fun `fetches and parses the live verse of the day in Urdu`() {
        assumeTrue("no network", online())

        val html = RekhtaSource.fetchHtml(RekhtaSource.POETRY_URL)
        assertTrue("page looks too small: ${html.length} chars", html.length > 10_000)

        val verse = RekhtaSource.parseVerse(Jsoup.parse(html, RekhtaSource.POETRY_URL))

        assertTrue("selectors no longer match rekhta.org", verse != null)
        verse!!

        val arabic = Regex("[؀-ۿ]")
        assertTrue("line one is not Urdu: ${verse.lineOne}", arabic.containsMatchIn(verse.lineOne))
        assertTrue("poet is empty", verse.poet.isNotBlank())
        println("live verse: ${verse.lineOne} / ${verse.lineTwo} -- ${verse.poet}")
    }
}
