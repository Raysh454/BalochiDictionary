import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../data/dictionary_repository.dart';
import '../data/word_of_the_day_service.dart';
import 'browse_screen.dart';
import 'search_screen.dart';
import 'word_of_the_day_screen.dart';

/// Tabbed shell for the three views.
///
/// The Wails UI used top tabs for Browse and Search; on Android these become
/// bottom navigation destinations, with Word of the Day added alongside them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.wordOfTheDayService,
  });

  final DictionaryRepository repository;
  final WordOfTheDayService wordOfTheDayService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _titles = [
    'Word of the Day',
    'Browse',
    'Search',
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_index],
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          WordOfTheDayScreen(service: widget.wordOfTheDayService),
          BrowseScreen(repository: widget.repository),
          SearchScreen(repository: widget.repository),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}

/// Full-screen states shown while the bundled database is being opened.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = error;

    return Scaffold(
      body: Center(
        child: failure == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.textMuted, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'The dictionary could not be opened.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$failure',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
