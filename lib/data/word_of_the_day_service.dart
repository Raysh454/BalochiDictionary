import '../models/dictionary_models.dart';
import 'dictionary_repository.dart';

/// A dated Word of the Day.
class WordOfTheDay {
  const WordOfTheDay({required this.date, required this.entry});

  /// Local calendar day this word belongs to.
  final DateTime date;
  final DictionaryEntry entry;
}

/// Picks one word per calendar day.
///
/// The choice is a pure function of the date, so it needs no stored state:
/// the app shows the same word all day, on every launch and on every device,
/// and yesterday's word can always be recomputed.
///
/// The date is mapped to a pool index by multiplying the day number by a
/// stride that is coprime with the pool size. Because that mapping is a
/// bijection over the pool, every word is shown exactly once before any word
/// repeats — roughly a 49-year cycle for the ~18k eligible headwords.
class WordOfTheDayService {
  WordOfTheDayService(this._repository);

  final DictionaryRepository _repository;

  int? _poolSize;
  final Map<int, WordOfTheDay> _cache = {};

  /// Candidate strides, tried in order until one is coprime with the pool
  /// size. They are large primes so consecutive days land far apart in the
  /// id ordering rather than walking the dictionary alphabetically.
  static const List<int> _strideCandidates = [
    1000003,
    999983,
    2000003,
    15485863,
    32452843,
  ];

  static final DateTime _epoch = DateTime.utc(1970, 1, 1);

  /// Whole days between the Unix epoch and [date]'s calendar day.
  ///
  /// The calendar fields are reinterpreted as UTC so that daylight-saving
  /// transitions cannot shift the day number.
  static int daysSinceEpoch(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

  /// The stride used for a given [poolSize]: the first candidate that shares
  /// no factor with it, falling back to 1 if none qualifies.
  static int strideFor(int poolSize) {
    for (final candidate in _strideCandidates) {
      if (_gcd(candidate, poolSize) == 1) return candidate;
    }
    return 1;
  }

  /// Maps a calendar day onto an index in `[0, poolSize)`.
  static int indexForDate(DateTime date, int poolSize) {
    if (poolSize <= 0) return 0;

    final index = (daysSinceEpoch(date) * strideFor(poolSize)) % poolSize;
    return index < 0 ? index + poolSize : index;
  }

  static int _gcd(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final next = x % y;
      x = y;
      y = next;
    }
    return x;
  }

  /// The word for today's local calendar day.
  Future<WordOfTheDay?> today() => forDate(DateTime.now());

  /// The word for the calendar day containing [date].
  Future<WordOfTheDay?> forDate(DateTime date) async {
    final day = daysSinceEpoch(date);
    final cached = _cache[day];
    if (cached != null) return cached;

    final poolSize = _poolSize ??= await _repository.wordOfTheDayPoolSize();
    if (poolSize <= 0) return null;

    final entry = await _repository.wordOfTheDayAt(
      indexForDate(date, poolSize),
    );
    if (entry == null) return null;

    final result = WordOfTheDay(
      date: DateTime(date.year, date.month, date.day),
      entry: entry,
    );
    _cache[day] = result;

    return result;
  }

  /// The [count] days immediately before [from], most recent first.
  Future<List<WordOfTheDay>> recentDays(int count, {DateTime? from}) async {
    final start = from ?? DateTime.now();
    final results = <WordOfTheDay>[];

    for (var back = 1; back <= count; back++) {
      final day = DateTime(start.year, start.month, start.day - back);
      final word = await forDate(day);
      if (word != null) results.add(word);
    }

    return results;
  }
}
