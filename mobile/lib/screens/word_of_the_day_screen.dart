import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../data/word_of_the_day_service.dart';
import '../widgets/word_card.dart';

/// Shows the word chosen for today, plus the words from the previous few days.
class WordOfTheDayScreen extends StatefulWidget {
  const WordOfTheDayScreen({super.key, required this.service});

  final WordOfTheDayService service;

  @override
  State<WordOfTheDayScreen> createState() => _WordOfTheDayScreenState();
}

class _WordOfTheDayScreenState extends State<WordOfTheDayScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _recentDayCount = 5;

  WordOfTheDay? _today;
  List<WordOfTheDay> _recent = const [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final today = await widget.service.today();
      final recent = await widget.service.recentDays(_recentDayCount);
      if (!mounted) return;

      setState(() {
        _today = today;
        _recent = recent;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the word of the day.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: _load);
    }

    final today = _today;
    if (today == null) {
      return const Center(
        child: Text(
          'No words available.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _TodayHeader(date: today.date),
          const SizedBox(height: 12),
          WordCard(entry: today.entry, headwordFontSize: 34),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'PREVIOUS DAYS',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final word in _recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PreviousDayTile(word: word),
              ),
          ],
        ],
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.accentLight),
            const SizedBox(width: 6),
            Text(
              'WORD OF THE DAY',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.accentLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          formatFullDate(date),
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _PreviousDayTile extends StatelessWidget {
  const _PreviousDayTile({required this.word});

  final WordOfTheDay word;

  @override
  Widget build(BuildContext context) {
    final firstDefinition =
        word.entry.definitions.isEmpty ? null : word.entry.definitions.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                formatShortDate(word.date),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BalochiText(
                    word.entry.balochi,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textStrong,
                    ),
                  ),
                  if (word.entry.latin.isNotEmpty)
                    Text(
                      word.entry.latin,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.partOfSpeech,
                      ),
                    ),
                  if (firstDefinition != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        firstDefinition.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats a date as `Monday, 8 September 2026` without pulling in `intl`.
String formatFullDate(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  final month = _monthNames[date.month - 1];
  return '$weekday, ${date.day} $month ${date.year}';
}

/// Formats a date as `8 Sep` for the compact history list.
String formatShortDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1].substring(0, 3)}';
