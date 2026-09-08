import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the bundled dictionary database.
///
/// This is the Flutter counterpart of `App.deployDatabase` /
/// `App.initializeDatabase` in `app.go`: the dictionary ships as a read-only
/// asset and is copied once into the app's private storage, because SQLite
/// needs a real file path rather than an asset handle.
class DatabaseService {
  DatabaseService._();

  static const String _assetPath = 'assets/db/balochi_dict.db';
  static const String _fileName = 'balochi_dict.db';

  /// Bumped whenever the bundled asset changes so an installed copy of an
  /// older database gets replaced on the next launch.
  static const int assetVersion = 1;
  static const String _versionFileName = 'balochi_dict.db.version';

  static Database? _database;
  static Future<Database>? _opening;

  /// Returns the shared database handle, deploying the asset on first use.
  /// Concurrent callers share a single open operation.
  static Future<Database> instance() {
    final existing = _database;
    if (existing != null) return Future.value(existing);

    return _opening ??= _open().then((db) {
      _database = db;
      _opening = null;
      return db;
    }, onError: (Object error, StackTrace stack) {
      _opening = null;
      throw error;
    });
  }

  static Future<Database> _open() async {
    _initFfiForDesktop();

    final dbPath = await _deployDatabase();
    return openDatabase(dbPath, readOnly: true);
  }

  /// Desktop runs need the FFI implementation; Android and iOS use the
  /// platform SQLite that `sqflite` binds by default.
  static void _initFfiForDesktop() {
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// Copies the asset into app storage if it is missing or out of date.
  static Future<String> _deployDatabase() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    final dbPath = p.join(directory.path, _fileName);
    final dbFile = File(dbPath);
    final versionFile = File(p.join(directory.path, _versionFileName));

    if (await dbFile.exists() && await _isCurrentVersion(versionFile)) {
      return dbPath;
    }

    final data = await rootBundle.load(_assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Write to a temporary file first so an interrupted copy cannot leave a
    // truncated database behind.
    final tempFile = File('$dbPath.tmp');
    await tempFile.writeAsBytes(bytes, flush: true);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempFile.rename(dbPath);
    await versionFile.writeAsString('$assetVersion', flush: true);

    return dbPath;
  }

  static Future<bool> _isCurrentVersion(File versionFile) async {
    if (!await versionFile.exists()) return false;
    final contents = (await versionFile.readAsString()).trim();
    return int.tryParse(contents) == assetVersion;
  }

  /// Test hook: opens the bundled asset from a caller-provided path.
  @visibleForTesting
  static Future<Database> openAt(String path) {
    _initFfiForDesktop();
    return openDatabase(path, readOnly: true);
  }
}
