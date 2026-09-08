import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../data/dictionary_repository.dart';
import '../models/dictionary_models.dart';
import '../widgets/word_card.dart';

/// Port of `SearchTab.vue`.
///
/// The desktop UI searched on submit; on a phone the query is run as the user
/// types, debounced so each keystroke does not hit the database.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final DictionaryRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _limit = 100;
  static const Duration _debounce = Duration(milliseconds: 220);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  SearchMethod _method = SearchMethod.balochi;
  List<DictionaryEntry> _results = const [];
  bool _searching = false;
  bool _hasSearched = false;
  String? _error;

  /// Discards results from a query the user has already typed past.
  int _requestToken = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _runSearch);
  }

  void _onMethodChanged(SearchMethod method) {
    if (method == _method) return;

    setState(() => _method = method);
    _debounceTimer?.cancel();
    _runSearch();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    final token = ++_requestToken;

    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final results = await widget.repository.search(query, _method, _limit);
      if (!mounted || token != _requestToken) return;

      setState(() {
        _results = results;
        _searching = false;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;

      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = true;
        _error = 'Search failed.';
      });
    }
  }

  void _clear() {
    _controller.clear();
    _debounceTimer?.cancel();
    _runSearch();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          // Rebuilds only the field as the query changes, so the clear button
          // appears without re-rendering the result list on every keystroke.
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onQueryChanged,
              onSubmitted: (_) {
                _debounceTimer?.cancel();
                _runSearch();
              },
              textInputAction: TextInputAction.search,
              // Balochi headwords are typed in Arabic script, so the field
              // follows the selected search method's direction.
              textDirection: _method == SearchMethod.balochi
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: const TextStyle(fontSize: 16, color: AppColors.text),
              decoration: InputDecoration(
                hintText: _hintForMethod(_method),
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textMuted),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              for (final method in SearchMethod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(method.label),
                    selected: _method == method,
                    onSelected: (_) => _onMethodChanged(method),
                    showCheckmark: false,
                    backgroundColor: AppColors.surfaceMuted,
                    selectedColor: AppColors.accent,
                    side: BorderSide(
                      color: _method == method
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _method == method
                          ? Colors.white
                          : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Text(error, style: const TextStyle(color: AppColors.textMuted)),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _hasSearched
                ? 'No results.'
                : 'Search the dictionary by Balochi headword, Latin transliteration, or English definition.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => WordCard(entry: _results[index]),
    );
  }

  static String _hintForMethod(SearchMethod method) {
    switch (method) {
      case SearchMethod.balochi:
        return 'Search in Balochi script...';
      case SearchMethod.latin:
        return 'Search transliteration, e.g. "ap"...';
      case SearchMethod.definition:
        return 'Search English definitions, e.g. "water"...';
    }
  }
}
