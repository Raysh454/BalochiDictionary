import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../data/dictionary_repository.dart';
import '../models/dictionary_models.dart';
import '../widgets/letter_jump_rail.dart';
import '../widgets/word_card.dart';

/// Port of `BrowseTab.vue`: headwords in dictionary order with letter
/// filtering and paged loading as the list is scrolled.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.repository});

  final DictionaryRepository repository;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final List<DictionaryEntry> _items = [];
  final Set<int> _seenWordIds = {};

  Map<String, int> _letterCounts = const {};
  String _letter = '';
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  /// Guards against a stale in-flight page overwriting a newer request, the
  /// role played by `browseRequestToken` in the Vue component.
  int _requestToken = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLetters();
    _loadBrowse(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadBrowse(reset: false);
    }
  }

  Future<void> _loadLetters() async {
    try {
      final letters = await widget.repository.browseLetters();
      if (!mounted) return;

      setState(() {
        _letterCounts = {
          for (final letter in letters) letter.letter: letter.count,
        };
      });
    } catch (_) {
      // The rail simply stays empty if letter counts cannot be read; browsing
      // still works without it.
    }
  }

  Future<void> _loadBrowse({required bool reset}) async {
    if (reset) {
      if (_loading) return;
    } else if (_loading || _loadingMore || !_hasMore) {
      return;
    }

    final token = ++_requestToken;
    final offset = reset ? 0 : _nextOffset;

    setState(() {
      _error = null;
      if (reset) {
        _loading = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final page = await widget.repository.browse(
        letter: _letter,
        limit: _pageSize,
        offset: offset,
      );

      if (!mounted || token != _requestToken) return;

      setState(() {
        if (reset) {
          _items.clear();
          _seenWordIds.clear();
        }

        // De-duplicate by word id, mirroring `appendUniqueItems`.
        for (final item in page.items) {
          if (_seenWordIds.add(item.wordId)) _items.add(item);
        }

        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;

      setState(() {
        _error = 'Browse is unavailable right now.';
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _items.clear();
          _seenWordIds.clear();
          _nextOffset = 0;
          _hasMore = false;
        }
      });
    }
  }

  void _onLetterSelected(String letter) {
    if (letter == _letter) return;

    setState(() => _letter = letter);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadBrowse(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Row(
      children: [
        Expanded(child: _buildList()),
        LetterJumpRail(
          activeLetter: _letter,
          letterCounts: _letterCounts,
          onLetterSelected: _onLetterSelected,
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadBrowse(reset: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No words for this letter.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 24),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _items.length) return _buildFooter();
        return WordCard(entry: _items[index], showCopyButton: false);
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'End of list',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return const SizedBox(height: 20);
  }
}
