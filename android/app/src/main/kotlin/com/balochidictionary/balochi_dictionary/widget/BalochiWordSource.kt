package com.balochidictionary.balochi_dictionary.widget

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File

/**
 * Reads the Balochi word of the day straight from the bundled dictionary.
 *
 * The widget cannot rely on the Flutter engine being alive, so this is a
 * deliberate Kotlin mirror of `WordOfTheDayService` and the deployment logic in
 * `DatabaseService`. Both sides use the same file, the same indexes and the
 * same date-to-index mapping, so they always agree on the day's word.
 *
 * If either side changes, the other must change with it:
 *  - [STRIDE_CANDIDATES] mirrors `WordOfTheDayService._strideCandidates`
 *  - [ELIGIBLE_FILTER] mirrors `DictionaryRepository._wordOfTheDayFilter`
 *  - [INDEX_STATEMENTS] mirrors `DatabaseService.indexStatements`
 *  - [DEPLOYMENT_VERSION] mirrors `DatabaseService.deploymentVersion`
 */
object BalochiWordSource {
    private const val TAG = "BalochiWordSource"

    /** Asset path inside the APK; `assets/` in pubspec lands under flutter_assets. */
    private const val ASSET_PATH = "flutter_assets/assets/db/balochi_dict.db"

    /**
     * path_provider's getApplicationSupportDirectory() maps to filesDir on
     * Android, so this is the same file the Flutter side deploys.
     */
    private const val DB_NAME = "balochi_dict.db"
    private const val VERSION_NAME = "balochi_dict.db.version"
    private const val DEPLOYMENT_VERSION = 1

    private val INDEX_STATEMENTS = listOf(
        "CREATE INDEX IF NOT EXISTS idx_word_definitions_word_id ON word_definitions(word_id)",
        "CREATE INDEX IF NOT EXISTS idx_words_balochi ON words(balochi)",
        "CREATE INDEX IF NOT EXISTS idx_words_normalized_latin ON words(normalized_latin)",
    )

    private val STRIDE_CANDIDATES = longArrayOf(1000003, 999983, 2000003, 15485863, 32452843)

    private const val ELIGIBLE_FILTER = """
        WHERE balochi IS NOT NULL AND balochi != ''
          AND EXISTS (SELECT 1 FROM word_definitions AS wd WHERE wd.word_id = words.id)
          AND (normalized_latin IS NULL OR normalized_latin = ''
               OR normalized_latin GLOB '*[^0-9]*')
    """

    /** Returns today's Balochi word, or null if the dictionary is unreadable. */
    fun wordOfTheDay(context: Context): DailyWord? {
        return try {
            val path = ensureDatabase(context) ?: return null
            SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                val poolSize = queryPoolSize(db)
                if (poolSize <= 0) return null
                loadWord(db, indexForDay(WidgetPrefs.todayEpochDay(), poolSize))
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read the Balochi word of the day", error)
            null
        }
    }

    /**
     * Maps a day number onto `[0, poolSize)` using a stride coprime with the
     * pool, so every word appears before any repeats.
     */
    fun indexForDay(epochDay: Long, poolSize: Int): Int {
        if (poolSize <= 0) return 0
        val index = (epochDay * strideFor(poolSize)) % poolSize
        return (if (index < 0) index + poolSize else index).toInt()
    }

    fun strideFor(poolSize: Int): Long {
        for (candidate in STRIDE_CANDIDATES) {
            if (gcd(candidate, poolSize.toLong()) == 1L) return candidate
        }
        return 1L
    }

    private fun gcd(a: Long, b: Long): Long {
        var x = Math.abs(a)
        var y = Math.abs(b)
        while (y != 0L) {
            val next = x % y
            x = y
            y = next
        }
        return x
    }

    private fun queryPoolSize(db: SQLiteDatabase): Int =
        db.rawQuery("SELECT COUNT(*) FROM words $ELIGIBLE_FILTER", null).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }

    private fun loadWord(db: SQLiteDatabase, index: Int): DailyWord? {
        val sql = "SELECT id, balochi, latin FROM words $ELIGIBLE_FILTER " +
            "ORDER BY id ASC LIMIT 1 OFFSET ?"

        val (wordId, script, latin) = db.rawQuery(sql, arrayOf(index.toString())).use { cursor ->
            if (!cursor.moveToFirst()) return null
            Triple(cursor.getInt(0), cursor.getString(1).orEmpty(), cursor.getString(2).orEmpty())
        }

        val definitions = db.rawQuery(
            """
            SELECT d.part_of_speech, d.definition
            FROM word_definitions AS wd
            JOIN definitions AS d ON wd.definition_id = d.id
            WHERE wd.word_id = ?
            ORDER BY d.id ASC
            """,
            arrayOf(wordId.toString()),
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.getString(0).orEmpty() to cursor.getString(1).orEmpty())
                }
            }
        }

        if (definitions.isEmpty()) return null

        return DailyWord(
            script = script,
            latin = latin,
            // Widgets are small: join the senses so more than one is visible.
            meaning = definitions.joinToString("; ") { it.second },
            note = definitions.first().first,
        )
    }

    /**
     * Copies the dictionary out of the APK and indexes it if that has not been
     * done yet, mirroring `DatabaseService._deployDatabase`.
     */
    private fun ensureDatabase(context: Context): String? {
        val dbFile = File(context.filesDir, DB_NAME)
        val versionFile = File(context.filesDir, VERSION_NAME)

        val current = dbFile.exists() &&
            versionFile.exists() &&
            versionFile.readText().trim().toIntOrNull() == DEPLOYMENT_VERSION
        if (current) return dbFile.absolutePath

        return try {
            val temp = File(context.filesDir, "$DB_NAME.tmp")
            context.assets.open(ASSET_PATH).use { input ->
                temp.outputStream().use { output -> input.copyTo(output) }
            }
            if (dbFile.exists()) dbFile.delete()
            temp.renameTo(dbFile)

            SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE,
            ).use { db -> INDEX_STATEMENTS.forEach(db::execSQL) }

            versionFile.writeText(DEPLOYMENT_VERSION.toString())
            dbFile.absolutePath
        } catch (error: Exception) {
            Log.w(TAG, "Could not deploy the dictionary for the widget", error)
            if (dbFile.exists()) dbFile.absolutePath else null
        }
    }
}
