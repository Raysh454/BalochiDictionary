/// Data models mirroring the Go structs in
/// `internal/dictionary/balochi_dictionary.go`.
library;

/// A single sense of a headword.
class Definition {
  const Definition({required this.partOfSpeech, required this.text});

  final String partOfSpeech;
  final String text;

  factory Definition.fromRow(Map<String, Object?> row) => Definition(
        partOfSpeech: (row['part_of_speech'] as String?) ?? '',
        text: (row['definition'] as String?) ?? '',
      );

  /// Matches the Go `definitionsSignature` element format.
  String get signature => '$partOfSpeech\u001f$text';
}

/// A headword plus its definitions. Covers both `Result` and `BrowseRow`,
/// which are structurally identical in the Go code.
class DictionaryEntry {
  const DictionaryEntry({
    required this.wordId,
    required this.balochi,
    required this.latin,
    required this.normalizedLatin,
    this.definitions = const [],
  });

  final int wordId;
  final String balochi;
  final String latin;
  final String normalizedLatin;
  final List<Definition> definitions;

  factory DictionaryEntry.fromRow(
    Map<String, Object?> row, {
    List<Definition> definitions = const [],
  }) =>
      DictionaryEntry(
        wordId: row['id'] as int,
        balochi: (row['balochi'] as String?) ?? '',
        latin: (row['latin'] as String?) ?? '',
        normalizedLatin: (row['normalized_latin'] as String?) ?? '',
        definitions: definitions,
      );

  DictionaryEntry copyWith({List<Definition>? definitions}) => DictionaryEntry(
        wordId: wordId,
        balochi: balochi,
        latin: latin,
        normalizedLatin: normalizedLatin,
        definitions: definitions ?? this.definitions,
      );
}

/// A first-letter bucket for the browse sidebar.
class BrowseLetter {
  const BrowseLetter({required this.letter, required this.count});

  final String letter;
  final int count;
}

/// One page of browse results, mirroring the Go `BrowsePage`.
class BrowsePage {
  const BrowsePage({
    required this.items,
    required this.offset,
    required this.limit,
    required this.nextOffset,
    required this.hasMore,
    required this.letter,
  });

  final List<DictionaryEntry> items;
  final int offset;
  final int limit;
  final int nextOffset;
  final bool hasMore;
  final String letter;
}

/// The search fields supported by the dictionary, matching the `method`
/// values accepted by the Go searcher.
enum SearchMethod {
  balochi('balochi', 'Balochi'),
  latin('latin', 'Latin'),
  definition('definition', 'Definition');

  const SearchMethod(this.wireName, this.label);

  final String wireName;
  final String label;
}
