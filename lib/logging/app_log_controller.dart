import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLogCategory {
  ai,
  dataStorage,
  crashDiagnostics,
  nativeBridge,
  notifications,
}

enum AppLogLevel {
  info,
  warning,
  error,
}

class AppLogEntry {
  const AppLogEntry({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.level,
    required this.title,
    required this.message,
    this.details,
  });

  final String id;
  final DateTime timestamp;
  final AppLogCategory category;
  final AppLogLevel level;
  final String title;
  final String message;
  final String? details;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'category': category.name,
      'level': level.name,
      'title': title,
      'message': message,
      'details': details,
    };
  }

  factory AppLogEntry.fromJson(Map<String, Object?> json) {
    return AppLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      category: _appLogCategoryFromName(json['category'] as String?),
      level: _appLogLevelFromName(json['level'] as String?),
      title: json['title'] as String? ?? '未命名日志',
      message: json['message'] as String? ?? '',
      details: json['details'] as String?,
    );
  }
}

class AppLogController extends ChangeNotifier {
  AppLogController._({
    required SharedPreferences? preferences,
    required DateTime Function() nowProvider,
  })  : _preferences = preferences,
        _nowProvider = nowProvider;

  static const String storageKey = 'app_logs_v1';
  static const String _sessionActiveKey = 'app_logs_crash_session_active_v1';
  static const String _sessionStartedAtKey =
      'app_logs_crash_session_started_at_v1';
  static const String _sessionLastHeartbeatAtKey =
      'app_logs_crash_session_last_heartbeat_at_v1';
  static const String _sessionEndedAtKey = 'app_logs_crash_session_ended_at_v1';
  static const int maxEntries = 300;

  final SharedPreferences? _preferences;
  final DateTime Function() _nowProvider;
  final List<AppLogEntry> _entries = <AppLogEntry>[];
  bool _sessionActive = false;

  List<AppLogEntry> get entries => List<AppLogEntry>.unmodifiable(_entries);
  List<AppLogEntry> get crashDiagnosticEntries => _entries
      .where((entry) => entry.category == AppLogCategory.crashDiagnostics)
      .toList(growable: false);

  bool get isEmpty => _entries.isEmpty;
  CrashDiagnosticsStatus get crashDiagnosticsStatus =>
      CrashDiagnosticsStatus.fromEntries(crashDiagnosticEntries);

  static Future<AppLogController> load({
    Future<SharedPreferences> Function()? preferencesLoader,
    DateTime Function()? nowProvider,
  }) async {
    final preferences = await _loadPreferences(preferencesLoader);
    final controller = AppLogController._(
      preferences: preferences,
      nowProvider: nowProvider ?? DateTime.now,
    );
    controller._restore(
      preferences?.getString(storageKey),
    );
    controller._restoreCrashSessionState();
    return controller;
  }

  factory AppLogController.memory({
    DateTime Function()? nowProvider,
  }) {
    return AppLogController._(
      preferences: null,
      nowProvider: nowProvider ?? DateTime.now,
    );
  }

  void log(
    AppLogLevel level, {
    required AppLogCategory category,
    required String title,
    required String message,
    String? details,
  }) {
    final entry = AppLogEntry(
      id: 'log_${_nowProvider().microsecondsSinceEpoch}_${_entries.length}',
      timestamp: _nowProvider(),
      category: category,
      level: level,
      title: title,
      message: message,
      details: _normalizeDetails(details),
    );
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    _persist();
  }

  void info({
    required AppLogCategory category,
    required String title,
    required String message,
    String? details,
  }) {
    log(
      AppLogLevel.info,
      category: category,
      title: title,
      message: message,
      details: details,
    );
  }

  void warning({
    required AppLogCategory category,
    required String title,
    required String message,
    String? details,
  }) {
    log(
      AppLogLevel.warning,
      category: category,
      title: title,
      message: message,
      details: details,
    );
  }

  void error({
    required AppLogCategory category,
    required String title,
    required String message,
    String? details,
  }) {
    log(
      AppLogLevel.error,
      category: category,
      title: title,
      message: message,
      details: details,
    );
  }

  void beginCrashMonitoringSession() {
    if (_sessionActive) {
      _updateSessionHeartbeat(reason: 'session_resumed');
      return;
    }
    _sessionActive = true;
    final now = _nowProvider().toIso8601String();
    _preferences?.setBool(_sessionActiveKey, true);
    _preferences?.setString(_sessionStartedAtKey, now);
    _preferences?.setString(_sessionLastHeartbeatAtKey, now);
    _preferences?.remove(_sessionEndedAtKey);
    info(
      category: AppLogCategory.crashDiagnostics,
      title: '应用会话已启动',
      message: '已开始记录异常退出与未处理异常线索。',
      details: 'startedAt=$now',
    );
  }

  void updateCrashMonitoringHeartbeat({
    required String reason,
  }) {
    if (!_sessionActive) {
      return;
    }
    _updateSessionHeartbeat(reason: reason);
  }

  void endCrashMonitoringSession({
    required String reason,
  }) {
    if (!_sessionActive) {
      return;
    }
    _sessionActive = false;
    final now = _nowProvider().toIso8601String();
    _preferences?.setBool(_sessionActiveKey, false);
    _preferences?.setString(_sessionEndedAtKey, now);
    _preferences?.setString(_sessionLastHeartbeatAtKey, now);
    info(
      category: AppLogCategory.crashDiagnostics,
      title: '应用会话已结束',
      message: '已记录本次会话的正常结束路径。',
      details: 'reason=$reason\nendedAt=$now',
    );
  }

  void captureUnhandledFlutterError(FlutterErrorDetails details) {
    error(
      category: AppLogCategory.crashDiagnostics,
      title: '捕获未处理 Flutter 异常',
      message: details.exceptionAsString(),
      details: _normalizeDetails(
        <String>[
          if (details.library != null) 'library: ${details.library}',
          if (details.context != null) 'context: ${details.context}',
          if (details.stack != null) details.stack.toString(),
        ].join('\n'),
      ),
    );
  }

  void captureUnhandledDartError(
    Object errorValue,
    StackTrace stackTrace, {
    required String source,
  }) {
    error(
      category: AppLogCategory.crashDiagnostics,
      title: '捕获未处理 Dart 异常',
      message: errorValue.toString(),
      details: _normalizeDetails(
        'source=$source\n${stackTrace.toString()}',
      ),
    );
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _preferences?.remove(storageKey);
  }

  String exportText({
    AppLogCategory? category,
  }) {
    final filtered = category == null
        ? _entries
        : _entries.where((item) => item.category == category).toList();
    if (filtered.isEmpty) {
      return '暂无日志';
    }
    return filtered.map(_formatEntry).join('\n\n');
  }

  void _restore(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return;
      }
      _entries
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map(
                (item) => AppLogEntry.fromJson(
                  item.map(
                    (key, value) => MapEntry('$key', value),
                  ),
                ),
              ),
        );
    } catch (_) {
      _entries.clear();
    }
  }

  void _restoreCrashSessionState() {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }
    final hadOpenSession = preferences.getBool(_sessionActiveKey) ?? false;
    _sessionActive = false;
    if (!hadOpenSession) {
      return;
    }
    final startedAt = preferences.getString(_sessionStartedAtKey);
    final lastHeartbeatAt = preferences.getString(_sessionLastHeartbeatAtKey);
    warning(
      category: AppLogCategory.crashDiagnostics,
      title: '检测到上次疑似异常退出',
      message: '上次会话没有记录到正常结束，应用可能发生了闪退或被异常终止。',
      details: _normalizeDetails(
        <String>[
          if (startedAt != null) 'startedAt=$startedAt',
          if (lastHeartbeatAt != null) 'lastHeartbeatAt=$lastHeartbeatAt',
        ].join('\n'),
      ),
    );
    preferences.setBool(_sessionActiveKey, false);
    preferences.remove(_sessionEndedAtKey);
  }

  void _updateSessionHeartbeat({
    required String reason,
  }) {
    final now = _nowProvider().toIso8601String();
    _preferences?.setBool(_sessionActiveKey, true);
    _preferences?.setString(_sessionLastHeartbeatAtKey, now);
    _preferences?.setString(
      _sessionStartedAtKey,
      _preferences.getString(_sessionStartedAtKey) ?? now,
    );
    if (reason == 'resumed' || reason == 'inactive' || reason == 'paused') {
      _preferences?.remove(_sessionEndedAtKey);
    }
  }

  void _persist() {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }
    final payload = jsonEncode(
      _entries.map((entry) => entry.toJson()).toList(),
    );
    preferences.setString(storageKey, payload);
  }

  static Future<SharedPreferences?> _loadPreferences(
    Future<SharedPreferences> Function()? preferencesLoader,
  ) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }
}

String appLogCategoryLabel(AppLogCategory category) => switch (category) {
      AppLogCategory.ai => 'AI',
      AppLogCategory.dataStorage => '数据与存储',
      AppLogCategory.crashDiagnostics => '异常退出',
      AppLogCategory.nativeBridge => '原生桥接',
      AppLogCategory.notifications => '通知',
    };

String appLogLevelLabel(AppLogLevel level) => switch (level) {
      AppLogLevel.info => '信息',
      AppLogLevel.warning => '警告',
      AppLogLevel.error => '错误',
    };

AppLogCategory _appLogCategoryFromName(String? value) => switch (value) {
      'dataStorage' => AppLogCategory.dataStorage,
      'crashDiagnostics' => AppLogCategory.crashDiagnostics,
      'nativeBridge' => AppLogCategory.nativeBridge,
      'notifications' => AppLogCategory.notifications,
      _ => AppLogCategory.ai,
    };

AppLogLevel _appLogLevelFromName(String? value) => switch (value) {
      'warning' => AppLogLevel.warning,
      'error' => AppLogLevel.error,
      _ => AppLogLevel.info,
    };

String _formatEntry(AppLogEntry entry) {
  final timestamp = entry.timestamp.toIso8601String();
  final header =
      '[$timestamp] ${appLogCategoryLabel(entry.category)} · ${appLogLevelLabel(entry.level)} · ${entry.title}';
  final details = entry.details == null || entry.details!.isEmpty
      ? ''
      : '\n${entry.details}';
  return '$header\n${entry.message}$details';
}

String? _normalizeDetails(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.length <= 2000) {
    return trimmed;
  }
  return '${trimmed.substring(0, 2000)}…';
}

class CrashDiagnosticsStatus {
  const CrashDiagnosticsStatus({
    required this.diagnosticEntryCount,
    required this.unhandledExceptionCount,
    required this.hasSuspectedAbnormalExit,
    required this.latestSignalAt,
    required this.latestSignalTitle,
  });

  final int diagnosticEntryCount;
  final int unhandledExceptionCount;
  final bool hasSuspectedAbnormalExit;
  final DateTime? latestSignalAt;
  final String? latestSignalTitle;

  bool get hasSignals =>
      hasSuspectedAbnormalExit || unhandledExceptionCount > 0;

  factory CrashDiagnosticsStatus.fromEntries(List<AppLogEntry> entries) {
    var diagnosticEntryCount = 0;
    var unhandledExceptionCount = 0;
    var hasSuspectedAbnormalExit = false;
    DateTime? latestSignalAt;
    String? latestSignalTitle;

    for (final entry in entries) {
      diagnosticEntryCount += 1;
      if (entry.title.contains('疑似异常退出')) {
        hasSuspectedAbnormalExit = true;
      }
      if (entry.level == AppLogLevel.error) {
        unhandledExceptionCount += 1;
      }
      final isSignal = entry.level != AppLogLevel.info;
      if (isSignal && latestSignalAt == null) {
        latestSignalAt = entry.timestamp;
        latestSignalTitle = entry.title;
      }
    }

    return CrashDiagnosticsStatus(
      diagnosticEntryCount: diagnosticEntryCount,
      unhandledExceptionCount: unhandledExceptionCount,
      hasSuspectedAbnormalExit: hasSuspectedAbnormalExit,
      latestSignalAt: latestSignalAt,
      latestSignalTitle: latestSignalTitle,
    );
  }
}
