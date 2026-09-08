import 'package:sqflite/sqflite.dart';

import '../models/dictionary_models.dart';

/// Port of `internal/dictionary/balochi_dictionary.go` and
/// `internal/search/service.go`.
///
/// The SQL is kept deliberately close to the Go original so search ranking and
/// browse paging behave exactly as they do in the desktop/web build.
class DictionaryRepository {
  DictionaryRepository(this._db);

  final Database _db;

  /// Mirrors the `normalizedDefinitionExpr` constant in the Go searcher:
  /// lower-cases a definition and flattens punctuation to spaces so that
  /// whole-word matching can be done with `LIKE`.
  static const String _normalizedDefinitionExpr = """
    trim(
      replace(replace(replace(replace(replace(replace(replace(replace(lower(d.definition),
      ';', ' '), ',', ' '), '.', ' '), ':', ' '), '(', ' '), ')', ' '), '-', ' '), '/', ' ')
    )
  """;

  /// Port of `normalizeForDefinitionSearch`: lower-case, keep letters, digits
  /// and whitespace, turn everything else into a space, then collapse runs of
  /// whitespace into single spaces.
  static String normalizeForDefinitionSearch(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (_letterOrNumber.hasMatch(char) || _whitespace.hasMatch(char)) {
        buffer.write(char);
      } else {
        buffer.write(' ');
      }
    }

    return buffer
        .toString()
        .split(_whitespaceRun)
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  static final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s');
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Searches the dictionary by [method], returning at most [limit] entries in
  /// ranked order.
  ///
  /// [strictDefinition] disables the substring fallback used by definition
  /// search, matching the `strict_definition=true` web API flag.
  Future<List<DictionaryEntry>> search(
    String query,
    SearchMethod method,
    int limit, {
    bool strictDefinition = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final ids = await _searchWordIds(
      trimmed,
      method,
      limit,
      strictDefinition: strictDefinition,
    );

    return _loadWordsFromIds(ids);
  }

  Future<List<int>> _searchWordIds(
    String query,
    SearchMethod method,
    int limit, {
    required bool strictDefinition,
  }) {
    switch (method) {
      case SearchMethod.balochi:
        return _searchPrefixWordIds('balochi', query, limit);
      case SearchMethod.latin:
        return _searchPrefixWordIds('normalized_latin', query, limit);
      case SearchMethod.definition:
        return _searchDefinitionWordIds(query, limit, strictDefinition);
    }
  }

  /// Exact match first, then prefix matches ordered shortest-first, with a
  /// deterministic lexical/id tie-break.
  Future<List<int>> _searchPrefixWordIds(
    String column,
    String query,
    int limit,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT id
      FROM words
      WHERE $column LIKE ?
      ORDER BY
        CASE WHEN $column = ? THEN 0 ELSE 1 END ASC,
        LENGTH($column) ASC,
        $column ASC,
        id ASC
      LIMIT ?
      ''',
      ['$query%', query, limit],
    );

    return _collectWordIds(rows);
  }

  /// Two-stage definition search: whole-word matching and ranking first, then
  /// a broad substring fallback when nothing matched (unless strict).
  Future<List<int>> _searchDefinitionWordIds(
    String query,
    int limit,
    bool strictDefinition,
  ) async {
    final normalizedQuery = normalizeForDefinitionSearch(query);
    if (normalizedQuery.isEmpty) return const [];

    final wholeWordPattern = '% $normalizedQuery %';
    final startPattern = ' $normalizedQuery %';
    final occurrenceToken = ' $normalizedQuery ';

    final wholeWordRows = await _db.rawQuery(
      '''
      SELECT w.id
      FROM words AS w
      JOIN word_definitions AS wd ON w.id = wd.word_id
      JOIN definitions AS d ON wd.definition_id = d.id
      WHERE (' ' || $_normalizedDefinitionExpr || ' ') LIKE ?
      GROUP BY w.id
      ORDER BY
        MAX(CASE
          WHEN $_normalizedDefinitionExpr = ? THEN 300
          WHEN (' ' || $_normalizedDefinitionExpr || ' ') LIKE ? THEN 200
          ELSE 100
        END) +
        MAX((LENGTH(' ' || $_normalizedDefinitionExpr || ' ')
          - LENGTH(REPLACE(' ' || $_normalizedDefinitionExpr || ' ', ?, '')))
          / LENGTH(?)) DESC,
        w.id ASC
      LIMIT ?
      ''',
      [
        wholeWordPattern,
        normalizedQuery,
        startPattern,
        occurrenceToken,
        occurrenceToken,
        limit,
      ],
    );

    final ids = _collectWordIds(wholeWordRows);
    if (ids.isNotEmpty || strictDefinition) return ids;

    final fallbackRows = await _db.rawQuery(
      '''
      SELECT DISTINCT w.id
      FROM words AS w
      JOIN word_definitions AS wd ON w.id = wd.word_id
      JOIN definitions AS d ON wd.definition_id = d.id
      WHERE lower(d.definition) LIKE ?
      LIMIT ?
      ''',
      ['%${query.toLowerCase()}%', limit],
    );

    return _collectWordIds(fallbackRows);
  }

  static List<int> _collectWordIds(List<Map<String, Object?>> rows) =>
      rows.map((row) => row['id'] as int).toList(growable: false);

  // ---------------------------------------------------------------------------
  // Word loading
  // ---------------------------------------------------------------------------

  /// Loads full entries for [ids], preserving the ranked order of the list.
  ///
  /// The Go version issues one query per id; here the words and their
  /// definitions are fetched in two batched queries and reordered in Dart,
  /// which produces the same output with far fewer round trips.
  Future<List<DictionaryEntry>> _loadWordsFromIds(List<int> ids) async {
    if (ids.isEmpty) return const [];

    final placeholders = List.filled(ids.length, '?').join(',');
    final wordRows = await _db.rawQuery(
      'SELECT id, balochi, latin, normalized_latin FROM words WHERE id IN ($placeholders)',
      ids,
    );

    final definitionsByWordId = await _loadDefinitionsByWordIds(ids);

    final byId = <int, DictionaryEntry>{
      for (final row in wordRows)
        row['id'] as int: DictionaryEntry.fromRow(
          row,
          definitions: definitionsByWordId[row['id'] as int] ?? const [],
        ),
    };

    final results = <DictionaryEntry>[];
    for (final id in ids) {
      final entry = byId[id];
      if (entry != null) results.add(entry);
    }

    return deduplicateNumericVariants(results);
  }

  /// Port of `loadDefinitionsByWordIDs`.
  Future<Map<int, List<Definition>>> _loadDefinitionsByWordIds(
    List<int> wordIds,
  ) async {
    final result = <int, List<Definition>>{
      for (final id in wordIds) id: <Definition>[],
    };
    if (wordIds.isEmpty) return result;

    final placeholders = List.filled(wordIds.length, '?').join(',');
    final rows = await _db.rawQuery(
      '''
      SELECT wd.word_id, d.part_of_speech, d.definition
      FROM word_definitions AS wd
      JOIN definitions AS d ON wd.definition_id = d.id
      WHERE wd.word_id IN ($placeholders)
      ORDER BY wd.word_id ASC, d.id ASC
      ''',
      wordIds,
    );

    for (final row in rows) {
      final wordId = row['word_id'] as int;
      (result[wordId] ??= <Definition>[]).add(Definition.fromRow(row));
    }

    return result;
  }

  /// Port of `deduplicateNumericVariants`.
  ///
  /// The source data contains transliteration variants whose
  /// `normalized_latin` is only digits (for example `1`). When such a variant
  /// duplicates a real transliteration of the same headword and definitions,
  /// the readable one is kept in the numeric one's rank position.
  static List<DictionaryEntry> deduplicateNumericVariants(
    List<DictionaryEntry> results,
  ) {
    final deduped = <DictionaryEntry>[];
    final seenCanonicalIndex = <String, int>{};

    for (final result in results) {
      final key =
          '${result.balochi}\u001d${_definitionsSignature(result.definitions)}';
      final existingIndex = seenCanonicalIndex[key];

      if (existingIndex == null) {
        seenCanonicalIndex[key] = deduped.length;
        deduped.add(result);
        continue;
      }

      final existingIsNumeric =
          isNumericOnly(deduped[existingIndex].normalizedLatin);
      final currentIsNumeric = isNumericOnly(result.normalizedLatin);

      // Replace a numeric variant with a transliterated variant while
      // preserving rank position.
      if (existingIsNumeric && !currentIsNumeric) {
        deduped[existingIndex] = result;
        continue;
      }

      // Hide extra numeric variants for the same headword+definition signature.
      if (currentIsNumeric) continue;

      // Keep distinct non-numeric transliteration variants visible.
      deduped.add(result);
    }

    return deduped;
  }

  static String _definitionsSignature(List<Definition> definitions) {
    final signatures = definitions.map((d) => d.signature).toList()..sort();
    return signatures.join('\u001e');
  }

  static bool isNumericOnly(String value) {
    if (value.isEmpty) return false;
    for (final unit in value.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Browse
  // ---------------------------------------------------------------------------

  /// Port of `Service.Browse`: one page of headwords in dictionary order,
  /// optionally filtered to a first-letter prefix.
  Future<BrowsePage> browse({
    String letter = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final args = <Object?>[];
    final where = letter.isEmpty ? '' : 'WHERE balochi LIKE ?';
    if (letter.isNotEmpty) args.add('$letter%');

    // One extra row is requested to detect whether another page exists.
    args.addAll([limit + 1, offset]);

    final rows = await _db.rawQuery(
      '''
      SELECT id, balochi, latin, normalized_latin
      FROM words
      $where
      ORDER BY balochi ASC, id ASC
      LIMIT ? OFFSET ?
      ''',
      args,
    );

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.sublist(0, limit) : rows;

    final wordIds = pageRows.map((row) => row['id'] as int).toList();
    final definitionsByWordId = await _loadDefinitionsByWordIds(wordIds);

    final items = pageRows
        .map((row) => DictionaryEntry.fromRow(
              row,
              definitions: definitionsByWordId[row['id'] as int] ?? const [],
            ))
        .toList(growable: false);

    return BrowsePage(
      items: items,
      offset: offset,
      limit: limit,
      nextOffset: offset + items.length,
      hasMore: hasMore,
      letter: letter,
    );
  }

  /// Port of `BrowseLetters`: first-letter buckets with counts.
  Future<List<BrowseLetter>> browseLetters() async {
    final rows = await _db.rawQuery(
      '''
      SELECT substr(balochi, 1, 1) AS letter, COUNT(*) AS count
      FROM words
      WHERE balochi IS NOT NULL AND balochi != ''
      GROUP BY letter
      ORDER BY letter ASC
      ''',
    );

    return rows
        .map((row) => BrowseLetter(
              letter: (row['letter'] as String?) ?? '',
              count: (row['count'] as int?) ?? 0,
            ))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Word of the day support
  // ---------------------------------------------------------------------------

  /// Words eligible to be a Word of the Day: they must have at least one
  /// definition to show, a headword to render, and a real transliteration
  /// rather than one of the digit-only placeholder variants.
  static const String _wordOfTheDayFilter = '''
    WHERE balochi IS NOT NULL AND balochi != ''
      AND EXISTS (SELECT 1 FROM word_definitions AS wd WHERE wd.word_id = words.id)
      AND (normalized_latin IS NULL OR normalized_latin = ''
           OR normalized_latin GLOB '*[^0-9]*')
  ''';

  /// Number of words that can be picked as a Word of the Day.
  Future<int> wordOfTheDayPoolSize() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM words $_wordOfTheDayFilter',
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Returns the eligible word at [index] in a stable id ordering, so a given
  /// index always maps to the same word.
  Future<DictionaryEntry?> wordOfTheDayAt(int index) async {
    if (index < 0) return null;

    final rows = await _db.rawQuery(
      '''
      SELECT id, balochi, latin, normalized_latin
      FROM words
      $_wordOfTheDayFilter
      ORDER BY id ASC
      LIMIT 1 OFFSET ?
      ''',
      [index],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final definitions = await _loadDefinitionsByWordIds([row['id'] as int]);

    return DictionaryEntry.fromRow(
      row,
      definitions: definitions[row['id'] as int] ?? const [],
    );
  }
}
