import 'dart:io';

import 'package:balochi_dictionary/data/database_service.dart';
import 'package:balochi_dictionary/data/dictionary_repository.dart';
import 'package:balochi_dictionary/data/word_of_the_day_service.dart';
import 'package:balochi_dictionary/models/dictionary_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the ported queries against the real bundled dictionary, so the
/// Flutter port is checked against the same data the Go app ships.
void main() {
  late Database db;
  late DictionaryRepository repository;

  late Directory workDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Deploy the asset the same way the app does -- copy it out and build the
    // indexes -- so the tests measure the database the app actually queries.
    final assetPath = Directory.current.uri
        .resolve('assets/db/balochi_dict.db')
        .toFilePath();

    workDir = await Directory.systemTemp.createTemp('balochi_dict_test');
    final dbPath = '${workDir.path}/balochi_dict.db';
    await File(assetPath).copy(dbPath);
    await DatabaseService.prepareDatabase(dbPath);

    db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    repository = DictionaryRepository(db);
  });

  tearDownAll(() async {
    await db.close();
    await workDir.delete(recursive: true);
  });

  group('normalizeForDefinitionSearch', () {
    test('lower-cases and strips punctuation to single spaces', () {
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('Hello, World!'),
        'hello world',
      );
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('  a--b/c  '),
        'a b c',
      );
      expect(DictionaryRepository.normalizeForDefinitionSearch('...'), '');
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('house of worship'),
        'house of worship',
      );
    });

    test('keeps digits and non-Latin letters', () {
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('top 10 (ten)'),
        'top 10 ten',
      );
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('بابا!'),
        'بابا',
      );
    });

    test('drops Arabic vowel marks, as the Go normalizer does', () {
      // Combining marks are not letters to Go's unicode.IsLetter either, so
      // they become spaces. Definition search only ever sees English glosses,
      // so this only matters for staying faithful to the original ranking.
      expect(
        DictionaryRepository.normalizeForDefinitionSearch('اَبا'),
        'ا با',
      );
    });
  });

  group('isNumericOnly', () {
    test('matches the Go helper, including the empty-string case', () {
      expect(DictionaryRepository.isNumericOnly('123'), isTrue);
      expect(DictionaryRepository.isNumericOnly('1a'), isFalse);
      expect(DictionaryRepository.isNumericOnly(''), isFalse);
      expect(DictionaryRepository.isNumericOnly('aba'), isFalse);
    });
  });

  group('deduplicateNumericVariants', () {
    DictionaryEntry entry(int id, String balochi, String normalized) =>
        DictionaryEntry(
          wordId: id,
          balochi: balochi,
          latin: normalized,
          normalizedLatin: normalized,
          definitions: const [Definition(partOfSpeech: 'n', text: 'water')],
        );

    test('promotes a transliterated variant into the numeric slot', () {
      final result = DictionaryRepository.deduplicateNumericVariants([
        entry(1, 'آپ', '1'),
        entry(2, 'آپ', 'ap'),
      ]);

      expect(result, hasLength(1));
      expect(result.single.normalizedLatin, 'ap');
    });

    test('drops extra numeric variants of the same headword', () {
      final result = DictionaryRepository.deduplicateNumericVariants([
        entry(1, 'آپ', 'ap'),
        entry(2, 'آپ', '2'),
      ]);

      expect(result, hasLength(1));
      expect(result.single.normalizedLatin, 'ap');
    });

    test('keeps distinct non-numeric transliterations', () {
      final result = DictionaryRepository.deduplicateNumericVariants([
        entry(1, 'آپ', 'ap'),
        entry(2, 'آپ', 'aap'),
      ]);

      expect(result, hasLength(2));
    });

    test('keeps entries whose definitions differ', () {
      final a = entry(1, 'آپ', 'ap');
      final b = DictionaryEntry(
        wordId: 2,
        balochi: 'آپ',
        latin: 'ap',
        normalizedLatin: 'ap',
        definitions: const [Definition(partOfSpeech: 'n', text: 'fire')],
      );

      expect(
        DictionaryRepository.deduplicateNumericVariants([a, b]),
        hasLength(2),
      );
    });
  });

  group('search', () {
    test('latin search puts the exact/shortest headword first', () async {
      final results = await repository.search('ap', SearchMethod.latin, 20);

      expect(results, isNotEmpty);
      expect(results.first.normalizedLatin, 'ap');

      // README: "queries like `ap` return the core headword before longer
      // forms such as `apsoz`, `appan`, or `aptar`."
      final order = results.map((r) => r.normalizedLatin).toList();
      for (final longer in ['apsoz', 'appan', 'aptar']) {
        if (order.contains(longer)) {
          expect(order.indexOf('ap'), lessThan(order.indexOf(longer)));
        }
      }
    });

    test('latin search is prefix-based', () async {
      final results = await repository.search('eba', SearchMethod.latin, 10);

      expect(results, isNotEmpty);
      expect(results.every((r) => r.normalizedLatin.startsWith('eba')), isTrue);
    });

    test('balochi search finds a known headword with its definitions',
        () async {
      final results = await repository.search('اَبا', SearchMethod.balochi, 10);

      expect(results, isNotEmpty);
      expect(results.first.balochi, 'اَبا');
      expect(results.first.latin, 'abá');
      expect(results.first.definitions.first.text, contains('father'));
    });

    test('definition search ranks whole-word matches', () async {
      final results =
          await repository.search('worship', SearchMethod.definition, 20);

      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.definitions.any((d) => d.text.contains('worship'))),
        isTrue,
      );
    });

    test('definition search falls back to substrings unless strict', () async {
      // "orshi" appears only inside "worship", never as a whole word.
      final loose =
          await repository.search('orshi', SearchMethod.definition, 10);
      final strict = await repository.search(
        'orshi',
        SearchMethod.definition,
        10,
        strictDefinition: true,
      );

      expect(loose, isNotEmpty);
      expect(strict, isEmpty);
    });

    test('respects the limit and rejects empty queries', () async {
      final limited = await repository.search('a', SearchMethod.latin, 5);
      expect(limited.length, lessThanOrEqualTo(5));

      expect(await repository.search('', SearchMethod.latin, 10), isEmpty);
      expect(await repository.search('   ', SearchMethod.balochi, 10), isEmpty);
      expect(
        await repository.search('!!!', SearchMethod.definition, 10),
        isEmpty,
      );
    });

    test('returns nothing for a query with no matches', () async {
      final results =
          await repository.search('zzzzqqq', SearchMethod.latin, 10);
      expect(results, isEmpty);
    });
  });

  group('browse', () {
    test('pages deterministically and reports whether more remain', () async {
      final first = await repository.browse(limit: 10, offset: 0);

      expect(first.items, hasLength(10));
      expect(first.hasMore, isTrue);
      expect(first.nextOffset, 10);

      final second =
          await repository.browse(limit: 10, offset: first.nextOffset);
      expect(second.items, hasLength(10));

      final firstIds = first.items.map((e) => e.wordId).toSet();
      final secondIds = second.items.map((e) => e.wordId).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
    });

    test('filters by first letter', () async {
      final page = await repository.browse(letter: 'آ', limit: 25);

      expect(page.items, isNotEmpty);
      expect(page.items.every((e) => e.balochi.startsWith('آ')), isTrue);
      expect(page.letter, 'آ');
    });

    test('loads definitions inline for browse rows', () async {
      final page = await repository.browse(limit: 50);

      expect(page.items.any((e) => e.definitions.isNotEmpty), isTrue);
    });

    test('reports the end of a letter without over-reading', () async {
      final letters = await repository.browseLetters();
      final smallest = letters.reduce((a, b) => a.count <= b.count ? a : b);

      final page = await repository.browse(
        letter: smallest.letter,
        limit: smallest.count + 5,
      );

      expect(page.hasMore, isFalse);
      expect(page.items, hasLength(smallest.count));
    });
  });

  group('browseLetters', () {
    test('returns first-letter buckets with positive counts', () async {
      final letters = await repository.browseLetters();

      expect(letters, isNotEmpty);
      expect(letters.every((l) => l.count > 0), isTrue);
      expect(letters.every((l) => l.letter.isNotEmpty), isTrue);
    });
  });

  group('word of the day', () {
    test('every eligible word has a definition and a real transliteration',
        () async {
      final poolSize = await repository.wordOfTheDayPoolSize();
      expect(poolSize, greaterThan(0));

      for (final index in [0, 1, 500, poolSize ~/ 2, poolSize - 1]) {
        final entry = await repository.wordOfTheDayAt(index);

        expect(entry, isNotNull, reason: 'index $index');
        expect(entry!.definitions, isNotEmpty, reason: 'index $index');
        expect(entry.balochi, isNotEmpty, reason: 'index $index');
        expect(
          DictionaryRepository.isNumericOnly(entry.normalizedLatin),
          isFalse,
          reason: 'index $index',
        );
      }
    });

    test('the same index always returns the same word', () async {
      final first = await repository.wordOfTheDayAt(1234);
      final second = await repository.wordOfTheDayAt(1234);

      expect(first!.wordId, second!.wordId);
    });

    test('an out-of-range index returns null', () async {
      final poolSize = await repository.wordOfTheDayPoolSize();

      expect(await repository.wordOfTheDayAt(poolSize), isNull);
      expect(await repository.wordOfTheDayAt(-1), isNull);
    });

    test('service returns a usable word for today and for past days', () async {
      final service = WordOfTheDayService(repository);

      final today = await service.today();
      expect(today, isNotNull);
      expect(today!.entry.definitions, isNotEmpty);

      final recent = await service.recentDays(5);
      expect(recent, hasLength(5));
      expect(recent.every((w) => w.entry.definitions.isNotEmpty), isTrue);

      // Distinct days should not collide with each other or with today.
      final ids = {today.entry.wordId, ...recent.map((w) => w.entry.wordId)};
      expect(ids, hasLength(6));
    });

    test('a fixed date resolves to a stable word', () async {
      final service = WordOfTheDayService(repository);

      final a = await service.forDate(DateTime(2026, 9, 8, 9));
      final b = await service.forDate(DateTime(2026, 9, 8, 21));

      expect(a!.entry.wordId, b!.entry.wordId);
    });
  });
}
