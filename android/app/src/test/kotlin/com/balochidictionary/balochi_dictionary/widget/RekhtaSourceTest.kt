package com.balochidictionary.balochi_dictionary.widget

import org.jsoup.Jsoup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the Rekhta scrapers against markup drift.
 *
 * The fixtures are real fragments captured from the live homepages. If Rekhta
 * restructures their pages these tests keep passing (the fixture is frozen),
 * so they prove the selectors are correct rather than that the site is
 * unchanged — refresh the fixtures when the widgets start showing stale data.
 */
class RekhtaSourceTest {

    private fun fixture(name: String) =
        Jsoup.parse(
            checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) {
                "missing fixture $name"
            },
            "UTF-8",
            "https://rekhta.org/",
        )

    @Test
    fun `parses the dictionary word of the day`() {
        val word = RekhtaSource.parseWord(fixture("rekhta_dictionary_home.html"))

        assertNotNull(word)
        word!!
        assertEquals("mahsuul", word.latin)
        // The Urdu script is preferred over the Devanagari for display.
        assertEquals("مَحْصُول", word.script)
        assertEquals("tax, duty, excise duty, custom, postage", word.meaning)
        assertTrue("origin should mention Arabic", word.note.contains("Arabic"))
    }

    @Test
    fun `parses the verse of the day with its poet`() {
        val verse = RekhtaSource.parseVerse(fixture("rekhta_org_home.html"))

        assertNotNull(verse)
        verse!!
        assertEquals("baḳht-e-bad kī nā-rasā.ī kā gila kyā kījiye", verse.lineOne)
        assertEquals("kārvāñ manzil pe hai aur duur haiñ manzil se ham", verse.lineTwo)
        assertEquals("Bismil Sunsaharvi Gayawi", verse.poet)
        assertEquals("rasaa.ii", verse.word)
        assertEquals("reach, access, approach, influence, impact", verse.meaning)
    }

    @Test
    fun `prefers the diacritical couplet over the plain roman one`() {
        val verse = RekhtaSource.parseVerse(fixture("rekhta_org_home.html"))

        // The page carries both; the roman variant would read "baKHt-e-bad".
        assertTrue(verse!!.lineOne.contains("ḳh"))
    }

    @Test
    fun `returns null instead of throwing when the markup is unrecognised`() {
        val empty = Jsoup.parse("<html><body><p>nothing here</p></body></html>")

        assertNull(RekhtaSource.parseWord(empty))
        assertNull(RekhtaSource.parseVerse(empty))
    }

    @Test
    fun `returns null when the word block has no meaning`() {
        val partial = Jsoup.parse(
            """
            <html><body>
              <div class='rdDailywordBlok'>
                <h3><a href='/meaning-of-x'><span>x</span></a></h3>
                <h4><span>क्ष</span><strong>•</strong><span>خ</span></h4>
              </div>
            </body></html>
            """.trimIndent(),
        )

        assertNull(RekhtaSource.parseWord(partial))
    }
}

/** The date-to-word mapping the widget shares with the Dart implementation. */
class BalochiWordSourceTest {

    @Test
    fun `stride is coprime with the pool so every word appears before repeats`() {
        for (poolSize in intArrayOf(17640, 17928, 18345, 100, 7)) {
            val stride = BalochiWordSource.strideFor(poolSize)
            assertEquals("pool $poolSize", 1L, gcd(stride, poolSize.toLong()))
        }
    }

    @Test
    fun `a full cycle of days visits every index exactly once`() {
        val poolSize = 17640
        val seen = HashSet<Int>()

        for (day in 0 until poolSize) {
            assertTrue(
                "index repeated after $day days",
                seen.add(BalochiWordSource.indexForDay(day.toLong(), poolSize)),
            )
        }

        assertEquals(poolSize, seen.size)
    }

    @Test
    fun `indices stay inside the pool, including before the epoch`() {
        val poolSize = 17640

        for (day in longArrayOf(-20000, -1, 0, 1, 20704, 999999)) {
            val index = BalochiWordSource.indexForDay(day, poolSize)
            assertTrue("day $day gave $index", index in 0 until poolSize)
        }
    }

    @Test
    fun `an empty pool does not divide by zero`() {
        assertEquals(0, BalochiWordSource.indexForDay(20704, 0))
    }

    private fun gcd(a: Long, b: Long): Long {
        var x = a
        var y = b
        while (y != 0L) {
            val next = x % y
            x = y
            y = next
        }
        return x
    }
}
