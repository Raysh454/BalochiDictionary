import 'package:flutter/material.dart';

import 'constants/app_theme.dart';
import 'data/database_service.dart';
import 'data/dictionary_repository.dart';
import 'data/word_of_the_day_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BalochiDictionaryApp());
}

class BalochiDictionaryApp extends StatelessWidget {
  const BalochiDictionaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balochi Dictionary',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _AppBootstrap(),
    );
  }
}

/// Opens the database once at startup and hands the repository to the UI.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<DictionaryRepository> _repositoryFuture;

  @override
  void initState() {
    super.initState();
    _repositoryFuture = _openRepository();
  }

  Future<DictionaryRepository> _openRepository() async {
    final database = await DatabaseService.instance();
    return DictionaryRepository(database);
  }

  void _retry() {
    setState(() => _repositoryFuture = _openRepository());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DictionaryRepository>(
      future: _repositoryFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StartupScreen(error: snapshot.error, onRetry: _retry);
        }

        final repository = snapshot.data;
        if (repository == null) return const StartupScreen();

        return HomeScreen(
          repository: repository,
          wordOfTheDayService: WordOfTheDayService(repository),
        );
      },
    );
  }
}
