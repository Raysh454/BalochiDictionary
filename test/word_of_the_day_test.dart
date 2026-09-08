import 'package:balochi_dictionary/data/word_of_the_day_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WordOfTheDayService.indexForDate', () {
    const poolSize = 17928;

    test('is stable for every moment within the same calendar day', () {
      final morning = DateTime(2026, 9, 8, 0, 0, 1);
      final evening = DateTime(2026, 9, 8, 23, 59, 59);

      expect(
        WordOfTheDayService.indexForDate(morning, poolSize),
        WordOfTheDayService.indexForDate(evening, poolSize),
      );
    });

    test('changes from one day to the next', () {
      final today = WordOfTheDayService.indexForDate(
        DateTime(2026, 9, 8),
        poolSize,
      );
      final tomorrow = WordOfTheDayService.indexForDate(
        DateTime(2026, 9, 9),
        poolSize,
      );

      expect(today, isNot(tomorrow));
    });

    test('always lands inside the pool', () {
      for (var day = 0; day < 3000; day++) {
        final date = DateTime(2026, 1, 1 + day);
        final index = WordOfTheDayService.indexForDate(date, poolSize);

        expect(index, inInclusiveRange(0, poolSize - 1));
      }
    });

    test('handles dates before the epoch without going negative', () {
      final index = WordOfTheDayService.indexForDate(
        DateTime(1965, 3, 4),
        poolSize,
      );

      expect(index, inInclusiveRange(0, poolSize - 1));
    });

    test('visits every word before repeating any of them', () {
      // The stride is coprime with the pool size, so consecutive days walk a
      // full cycle of the pool. Sampling one whole cycle must yield each index
      // exactly once.
      final seen = <int>{};
      for (var day = 0; day < poolSize; day++) {
        final date = DateTime(2026, 1, 1 + day);
        expect(
          seen.add(WordOfTheDayService.indexForDate(date, poolSize)),
          isTrue,
          reason: 'index repeated after $day days',
        );
      }

      expect(seen.length, poolSize);
    });

    test('degrades safely when the pool is empty', () {
      expect(WordOfTheDayService.indexForDate(DateTime(2026, 9, 8), 0), 0);
    });

    test('picks a stride that is coprime with the pool size', () {
      for (final size in [17928, 18345, 1000003, 7, 100, 999983]) {
        final stride = WordOfTheDayService.strideFor(size);
        expect(_gcd(stride, size), 1, reason: 'pool size $size');
      }
    });
  });

  group('WordOfTheDayService.daysSinceEpoch', () {
    test('counts whole days from the Unix epoch', () {
      expect(WordOfTheDayService.daysSinceEpoch(DateTime(1970, 1, 1)), 0);
      expect(WordOfTheDayService.daysSinceEpoch(DateTime(1970, 1, 2)), 1);
      expect(WordOfTheDayService.daysSinceEpoch(DateTime(2026, 9, 8)), 20704);
    });

    test('ignores the time of day', () {
      expect(
        WordOfTheDayService.daysSinceEpoch(DateTime(2026, 9, 8, 23, 30)),
        WordOfTheDayService.daysSinceEpoch(DateTime(2026, 9, 8, 0, 30)),
      );
    });
  });
}

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final next = x % y;
    x = y;
    y = next;
  }
  return x;
}
