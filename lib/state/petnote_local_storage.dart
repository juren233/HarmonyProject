import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:petnote/platform/petnote_app_directory.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PetNoteLocalTable {
  pets('pets_v1'),
  todos('todos_v1'),
  reminders('reminders_v1'),
  records('records_v1'),
  overviewConfig('overview_config_v1'),
  overviewAiReport('overview_ai_report_v1');

  const PetNoteLocalTable(this.storageKey);

  final String storageKey;
}

enum PetNoteLocalStorageBackend { memory, sharedPreferences, database }

class PetNoteLocalStorage {
  PetNoteLocalStorage._({
    SharedPreferences? preferences,
    Map<String, Object?>? memoryValues,
    Database? database,
    StoreRef<String, String>? store,
    PetNoteLocalStorageBackend? backend,
  })  : _preferences = preferences,
        _memoryValues = memoryValues,
        _database = database,
        _store = store,
        backend = backend ??
            (database != null
                ? PetNoteLocalStorageBackend.database
                : memoryValues != null
                    ? PetNoteLocalStorageBackend.memory
                    : PetNoteLocalStorageBackend.sharedPreferences);

  factory PetNoteLocalStorage.memory({
    Map<String, Object?> initialValues = const <String, Object?>{},
  }) {
    return PetNoteLocalStorage._(
      memoryValues: Map<String, Object?>.from(initialValues),
    );
  }

  static Future<PetNoteLocalStorage?> load({
    Future<SharedPreferences> Function()? preferencesLoader,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return await loadDatabase(
          legacyPreferencesLoader: preferencesLoader,
          timeout: timeout,
        ) ??
        loadSharedPreferences(
          preferencesLoader: preferencesLoader,
          timeout: timeout,
        );
  }

  static Future<PetNoteLocalStorage?> loadSharedPreferences({
    Future<SharedPreferences> Function()? preferencesLoader,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    try {
      final preferences = await loader().timeout(timeout);
      return PetNoteLocalStorage._(preferences: preferences);
    } on TimeoutException catch (error) {
      debugPrint('SharedPreferences timed out during startup: $error');
    } catch (error) {
      debugPrint('SharedPreferences unavailable on this platform: $error');
    }
    return null;
  }

  static Future<PetNoteLocalStorage?> loadDatabase({
    DatabaseFactory? databaseFactory,
    String? databasePath,
    Future<SharedPreferences> Function()? legacyPreferencesLoader,
    Future<String?> Function()? directoryLoader,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final factory = databaseFactory ?? databaseFactoryIo;
    try {
      final path = databasePath ?? await _resolveDatabasePath(directoryLoader);
      if (path == null || path.trim().isEmpty) {
        return null;
      }
      final database = await factory.openDatabase(path).timeout(timeout);
      final storage = PetNoteLocalStorage._(
        database: database,
        store: StoreRef<String, String>(_databaseStoreName),
      );
      await storage._migrateLegacyPreferences(
        legacyPreferencesLoader ?? SharedPreferences.getInstance,
      );
      return storage;
    } on TimeoutException catch (error) {
      debugPrint('PetNote local database timed out during startup: $error');
    } catch (error) {
      debugPrint('PetNote local database unavailable on this platform: $error');
    }
    return null;
  }

  static Future<PetNoteLocalStorage> openInMemoryDatabase({
    Future<SharedPreferences> Function()? legacyPreferencesLoader,
    Map<String, Object?> existingValues = const <String, Object?>{},
  }) async {
    final database = await databaseFactoryMemory.openDatabase(
      'petnote-memory-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final storage = PetNoteLocalStorage._(
      database: database,
      store: StoreRef<String, String>(_databaseStoreName),
    );
    for (final entry in existingValues.entries) {
      await storage._writeString(entry.key, entry.value.toString());
    }
    await storage._migrateLegacyPreferences(
      legacyPreferencesLoader ?? SharedPreferences.getInstance,
    );
    return storage;
  }

  static Future<String?> _resolveDatabasePath(
    Future<String?> Function()? directoryLoader,
  ) async {
    final baseDirectory = await (directoryLoader ?? PetNoteAppDirectory.load)();
    if (baseDirectory == null || baseDirectory.trim().isEmpty) {
      return null;
    }
    final directory = Directory(
      '${baseDirectory.trim()}${Platform.pathSeparator}petnote_database',
    );
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}petnote.sembast.db';
  }

  final SharedPreferences? _preferences;
  final Map<String, Object?>? _memoryValues;
  final Database? _database;
  final StoreRef<String, String>? _store;
  final PetNoteLocalStorageBackend backend;
  final Map<PetNoteLocalTable, int> _writeCounts = <PetNoteLocalTable, int>{};
  final Map<PetNoteLocalTable, int> _entityPutCounts = <PetNoteLocalTable, int>{};
  final Map<PetNoteLocalTable, int> _entityDeleteCounts =
      <PetNoteLocalTable, int>{};

  static const String _databaseStoreName = 'petnote_local_tables';
  static const String _databaseMigrationMarkerKey =
      'petnote_local_database_migrated_v1';

  Map<PetNoteLocalTable, int> get writeCounts =>
      Map<PetNoteLocalTable, int>.unmodifiable(_writeCounts);

  Map<PetNoteLocalTable, int> get debugEntityPutCounts =>
      Map<PetNoteLocalTable, int>.unmodifiable(_entityPutCounts);

  Map<PetNoteLocalTable, int> get debugEntityDeleteCounts =>
      Map<PetNoteLocalTable, int>.unmodifiable(_entityDeleteCounts);

  String? readTable(PetNoteLocalTable table) {
    if (_usesEntityRows(table)) {
      return _readEntityRows(table);
    }
    return _readString(table.storageKey);
  }

  Future<void> writeTable(PetNoteLocalTable table, String value) async {
    _writeCounts[table] = (_writeCounts[table] ?? 0) + 1;
    if (_usesEntityRows(table)) {
      await _writeEntityRows(table, value);
      return;
    }
    await _writeString(table.storageKey, value);
  }

  Future<void> removeTable(PetNoteLocalTable table) async {
    _writeCounts[table] = (_writeCounts[table] ?? 0) + 1;
    if (_usesEntityRows(table)) {
      await _removeEntityRows(table);
      return;
    }
    await _remove(table.storageKey);
  }

  bool? readBool(String key) {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      final value = memoryValues[key];
      return value is bool ? value : null;
    }
    if (_database != null) {
      final databaseValue = _readString(key);
      if (databaseValue != null) {
        return databaseValue == 'true';
      }
    }
    return _preferences?.getBool(key);
  }

  Future<void> writeBool(String key, bool value) async {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      memoryValues[key] = value;
      return;
    }
    if (_database != null) {
      await _writeString(key, value.toString());
      return;
    }
    await _preferences?.setBool(key, value);
  }

  Map<String, Object?> debugExportTables() {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      return Map<String, Object?>.from(memoryValues);
    }
    final database = _database;
    final store = _store;
    if (database == null || store == null) {
      return <String, Object?>{};
    }
    final records = store.findSync(database);
    return <String, Object?>{
      for (final record in records) record.key: record.value,
    };
  }

  String? _readString(String key) {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      final value = memoryValues[key];
      return value is String ? value : null;
    }
    final database = _database;
    final store = _store;
    if (database != null && store != null) {
      return store.record(key).getSync(database);
    }
    return _preferences?.getString(key);
  }

  Future<void> _writeString(String key, String value) async {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      memoryValues[key] = value;
      return;
    }
    final database = _database;
    final store = _store;
    if (database != null && store != null) {
      await store.record(key).put(database, value);
      return;
    }
    await _preferences?.setString(key, value);
  }

  Future<void> _remove(String key) async {
    final memoryValues = _memoryValues;
    if (memoryValues != null) {
      memoryValues.remove(key);
      return;
    }
    final database = _database;
    final store = _store;
    if (database != null && store != null) {
      await store.record(key).delete(database);
      return;
    }
    await _preferences?.remove(key);
  }

  bool _usesEntityRows(PetNoteLocalTable table) {
    return _database != null && _entityRowTables.contains(table);
  }

  String? _readEntityRows(PetNoteLocalTable table) {
    final database = _database;
    final store = _store;
    if (database == null || store == null) {
      return null;
    }
    final records = _findEntityRecordsSync(database, store, table);
    if (records.isEmpty) {
      return _readString(table.storageKey);
    }
    final rows = <_EntityRow>[];
    for (final record in records) {
      final row = _decodeEntityRow(record.value);
      if (row != null) {
        rows.add(row);
      }
    }
    rows.sort((left, right) => left.order.compareTo(right.order));
    return jsonEncode(rows.map((row) => row.data).toList());
  }

  Future<void> _writeEntityRows(PetNoteLocalTable table, String value) async {
    final database = _database;
    final store = _store;
    if (database == null || store == null) {
      await _writeString(table.storageKey, value);
      return;
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      await _writeString(table.storageKey, value);
      return;
    }
    final nextRows = <String, String>{};
    for (var index = 0; index < decoded.length; index += 1) {
      final item = decoded[index];
      if (item is! Map) {
        continue;
      }
      final json = Map<String, Object?>.from(item);
      final id = json['id'] as String?;
      final rowKey = id == null || id.trim().isEmpty
          ? '${table.storageKey}/row_$index'
          : '${table.storageKey}/${id.trim()}';
      final row = <String, Object?>{
        'order': index,
        'data': json,
      };
      nextRows[rowKey] = jsonEncode(row);
    }
    await database.transaction((transaction) async {
      final pendingRows = Map<String, String>.from(nextRows);
      final existingRecords = await store.find(
        transaction,
        finder: _entityRowsFinder(table),
      );
      for (final record in existingRecords) {
        final nextValue = pendingRows.remove(record.key);
        if (nextValue == null) {
          await store.record(record.key).delete(transaction);
          _incrementEntityDeleteCount(table);
          continue;
        }
        if (record.value != nextValue) {
          await store.record(record.key).put(transaction, nextValue);
          _incrementEntityPutCount(table);
        }
      }
      for (final entry in pendingRows.entries) {
        await store.record(entry.key).put(transaction, entry.value);
        _incrementEntityPutCount(table);
      }
      await store.record(table.storageKey).delete(transaction);
    });
  }

  Future<void> _removeEntityRows(PetNoteLocalTable table) async {
    final database = _database;
    final store = _store;
    if (database == null || store == null) {
      await _remove(table.storageKey);
      return;
    }
    await database.transaction((transaction) async {
      await _deleteEntityRows(transaction, store, table);
      await store.record(table.storageKey).delete(transaction);
    });
  }

  Future<void> _deleteEntityRows(
    DatabaseClient database,
    StoreRef<String, String> store,
    PetNoteLocalTable table,
  ) async {
    final deletedCount = await store.delete(
      database,
      finder: _entityRowsFinder(table),
    );
    if (deletedCount > 0) {
      _entityDeleteCounts[table] =
          (_entityDeleteCounts[table] ?? 0) + deletedCount;
    }
  }

  void _incrementEntityPutCount(PetNoteLocalTable table) {
    _entityPutCounts[table] = (_entityPutCounts[table] ?? 0) + 1;
  }

  void _incrementEntityDeleteCount(PetNoteLocalTable table) {
    _entityDeleteCounts[table] = (_entityDeleteCounts[table] ?? 0) + 1;
  }

  List<RecordSnapshot<String, String>> _findEntityRecordsSync(
    DatabaseClient database,
    StoreRef<String, String> store,
    PetNoteLocalTable table,
  ) {
    return store.findSync(database, finder: _entityRowsFinder(table));
  }

  Finder _entityRowsFinder(PetNoteLocalTable table) {
    final prefix = '${table.storageKey}/';
    return Finder(
      filter: Filter.custom((record) {
        final key = record.key;
        return key is String && key.startsWith(prefix);
      }),
    );
  }

  _EntityRow? _decodeEntityRow(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final data = decoded['data'];
        final order = decoded['order'];
        if (data is Map && order is int) {
          return _EntityRow(
            order: order,
            data: Map<String, Object?>.from(data),
          );
        }
        if (decoded.containsKey('id')) {
          return _EntityRow(
            order: 0,
            data: Map<String, Object?>.from(decoded),
          );
        }
      }
    } catch (error) {
      debugPrint('PetNote local database row decode failed: $error');
    }
    return null;
  }

  Future<void> _migrateLegacyPreferences(
    Future<SharedPreferences> Function() preferencesLoader,
  ) async {
    if (_database == null ||
        _readString(_databaseMigrationMarkerKey) == 'true') {
      return;
    }
    final preferences = await preferencesLoader();
    for (final table in PetNoteLocalTable.values) {
      final value = preferences.getString(table.storageKey);
      if (value != null && _readString(table.storageKey) == null) {
        await _writeString(table.storageKey, value);
      }
    }
    for (final key in _legacyBoolKeys) {
      final value = preferences.getBool(key);
      if (value != null && _readString(key) == null) {
        await _writeString(key, value.toString());
      }
    }
    await _writeString(_databaseMigrationMarkerKey, 'true');
  }
}

class _EntityRow {
  const _EntityRow({required this.order, required this.data});

  final int order;
  final Map<String, Object?> data;
}

const Set<PetNoteLocalTable> _entityRowTables = <PetNoteLocalTable>{
  PetNoteLocalTable.pets,
  PetNoteLocalTable.todos,
  PetNoteLocalTable.reminders,
  PetNoteLocalTable.records,
};

const List<String> _legacyBoolKeys = <String>[
  'first_launch_intro_auto_enabled_v1',
];
