import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class HouseholdDevice {
  HouseholdDevice({
    required this.deviceId,
    required this.name,
    this.role,
    this.servedPetId,
    this.lastSeenMs,
    this.lastAckServerSeq,
  });

  final String deviceId;
  String name;
  String? role;
  String? servedPetId;
  int? lastSeenMs;
  int? lastAckServerSeq;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'role': role,
        'servedPetId': servedPetId,
        'lastSeenMs': lastSeenMs,
        'lastAckServerSeq': lastAckServerSeq,
      };

  factory HouseholdDevice.fromJson(Map<String, dynamic> json) =>
      HouseholdDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        role: json['role'] as String?,
        servedPetId: json['servedPetId'] as String?,
        lastSeenMs: json['lastSeenMs'] as int?,
        lastAckServerSeq: (json['lastAckServerSeq'] as num?)?.toInt(),
      );
}

class Household {
  Household({
    required this.id,
    required this.saltBase64,
    required this.authToken,
  });

  final String id;
  final String saltBase64;
  final String authToken;
  final Map<String, HouseholdDevice> devices = <String, HouseholdDevice>{};
  final Map<String, Map<String, dynamic>> completedActions =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> appliedChecklistActions =
      <String, Map<String, dynamic>>{};
  final Set<String> completedItemKeys = <String>{};
  final Map<String, SyncEventReceipt> syncEvents = <String, SyncEventReceipt>{};
  final Map<String, String> actionSyncEventIds = <String, String>{};
  final Map<String, String> mutationSyncEventIds = <String, String>{};
  int nextServerSeq = 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'saltBase64': saltBase64,
        'authToken': authToken,
        'nextServerSeq': nextServerSeq,
        'devices': devices.map(
          (deviceId, device) => MapEntry(deviceId, device.toJson()),
        ),
        'completedActions': completedActions,
        'appliedChecklistActions': appliedChecklistActions,
        'completedItemKeys': completedItemKeys.toList(growable: false),
        'syncEvents': syncEvents.map(
          (syncId, event) => MapEntry(syncId, event.toJson()),
        ),
        'actionSyncEventIds': actionSyncEventIds,
        'mutationSyncEventIds': mutationSyncEventIds,
      };

  factory Household.fromJson(Map<String, dynamic> json) {
    final household = Household(
      id: json['id'] as String,
      saltBase64: json['saltBase64'] as String,
      authToken: json['authToken'] as String? ?? _newAuthToken(),
    );
    household.nextServerSeq = ((json['nextServerSeq'] as num?)?.toInt() ?? 1)
        .clamp(1, 1 << 62)
        .toInt();

    final devicesJson =
        json['devices'] as Map<String, dynamic>? ?? <String, dynamic>{};
    for (final entry in devicesJson.entries) {
      household.devices[entry.key] = HouseholdDevice.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    final completedActionsJson =
        json['completedActions'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    for (final entry in completedActionsJson.entries) {
      final value = entry.value;
      if (value is Map) {
        household.completedActions[entry.key] =
            Map<String, dynamic>.from(value);
        household.rememberAppliedChecklistAction(
          household.completedActions[entry.key]!,
        );
        household.completedItemKeys.add(entry.key);
      }
    }
    final appliedChecklistActionsJson =
        json['appliedChecklistActions'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    for (final entry in appliedChecklistActionsJson.entries) {
      final value = entry.value;
      if (value is Map) {
        household.rememberAppliedChecklistAction(
          Map<String, dynamic>.from(value),
        );
      }
    }
    household.completedItemKeys.addAll(
      ((json['completedItemKeys'] as List?) ?? const <dynamic>[])
          .whereType<String>(),
    );
    household._migrateLegacySnapshot(json);
    household._migrateLegacyPendingActions(json);
    final syncEventsJson =
        json['syncEvents'] as Map<String, dynamic>? ?? <String, dynamic>{};
    for (final entry in syncEventsJson.entries) {
      final value = entry.value;
      if (value is Map) {
        final event =
            SyncEventReceipt.fromJson(Map<String, dynamic>.from(value));
        household.syncEvents[event.syncId] = event;
      }
    }
    household._restoreSyncEventIndexes(json);
    household._backfillSyncEventSequences();

    return household;
  }

  int allocateServerSeq() => nextServerSeq++;

  void _backfillSyncEventSequences() {
    var maxServerSeq = 0;
    for (final event in syncEvents.values) {
      if (event.serverSeq <= 0) {
        event.serverSeq = allocateServerSeq();
      }
      event.payload.putIfAbsent('serverSeq', () => event.serverSeq);
      if (event.serverSeq > maxServerSeq) {
        maxServerSeq = event.serverSeq;
      }
    }
    if (nextServerSeq <= maxServerSeq) {
      nextServerSeq = maxServerSeq + 1;
    }
  }

  void _restoreSyncEventIndexes(Map<String, dynamic> json) {
    final actionSyncEventIdsJson =
        json['actionSyncEventIds'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    for (final entry in actionSyncEventIdsJson.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        final event = syncEvents[value];
        if (event != null &&
            (event.messageType != SyncMessageTypes.action ||
                event.payload['actionId'] != entry.key)) {
          continue;
        }
        actionSyncEventIds[entry.key] = value;
      }
    }
    final mutationSyncEventIdsJson =
        json['mutationSyncEventIds'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    for (final entry in mutationSyncEventIdsJson.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        final event = syncEvents[value];
        if (event != null &&
            (event.messageType != SyncMessageTypes.mutation ||
                event.payload['mutationId'] != entry.key)) {
          continue;
        }
        mutationSyncEventIds[entry.key] = value;
      }
    }
    for (final event in syncEvents.values) {
      if (event.messageType == SyncMessageTypes.action) {
        final actionId = event.payload['actionId'];
        if (actionId is String && actionId.isNotEmpty) {
          actionSyncEventIds.putIfAbsent(actionId, () => event.syncId);
        }
        rememberAppliedChecklistAction(event.payload);
      } else if (event.messageType == SyncMessageTypes.mutation) {
        final mutationId = event.payload['mutationId'];
        if (mutationId is String && mutationId.isNotEmpty) {
          mutationSyncEventIds.putIfAbsent(mutationId, () => event.syncId);
        }
      }
    }
  }

  void _migrateLegacySnapshot(Map<String, dynamic> json) {
    final ciphertext = json['snapshotCiphertext'];
    if (ciphertext is! String || ciphertext.isEmpty) {
      return;
    }
    final version = (json['snapshotVersion'] as num?)?.toInt() ?? 0;
    final syncId = 'legacy-snapshot-$version';
    syncEvents.putIfAbsent(
      syncId,
      () => SyncEventReceipt(
        syncId: syncId,
        originDeviceId: '',
        messageType: SyncMessageTypes.snapshot,
        serverSeq: allocateServerSeq(),
        payload: {
          'syncId': syncId,
          'originDeviceId': '',
          'version': version,
          'ciphertext': ciphertext,
        },
      ),
    );
  }

  void _migrateLegacyPendingActions(Map<String, dynamic> json) {
    final pendingActions = json['pendingActions'];
    if (pendingActions is! List) {
      return;
    }
    for (var index = 0; index < pendingActions.length; index += 1) {
      final value = pendingActions[index];
      if (value is! Map) {
        continue;
      }
      final payload = Map<String, dynamic>.from(value);
      final actionId = payload['actionId'] as String?;
      final syncId = 'legacy-action-${actionId ?? index}';
      payload
        ..putIfAbsent('syncId', () => syncId)
        ..putIfAbsent('originDeviceId', () => '');
      syncEvents.putIfAbsent(
        payload['syncId'] as String,
        () => SyncEventReceipt(
          syncId: payload['syncId'] as String,
          originDeviceId: payload['originDeviceId'] as String? ?? '',
          messageType: SyncMessageTypes.action,
          serverSeq: allocateServerSeq(),
          payload: payload,
        ),
      );
    }
  }

  String checklistActionKey({
    required String sourceType,
    required String itemId,
    required String kind,
  }) {
    return '$sourceType:$itemId:$kind';
  }

  Map<String, dynamic>? appliedChecklistAction({
    required String sourceType,
    required String itemId,
    required String kind,
  }) {
    return appliedChecklistActions[checklistActionKey(
      sourceType: sourceType,
      itemId: itemId,
      kind: kind,
    )];
  }

  void rememberAppliedChecklistAction(Map<String, dynamic> payload) {
    final sourceType = payload['sourceType'];
    final itemId = payload['itemId'];
    final kind = payload['kind'];
    final syncId = payload['syncId'];
    if (sourceType is! String ||
        sourceType.isEmpty ||
        itemId is! String ||
        itemId.isEmpty ||
        kind is! String ||
        kind.isEmpty ||
        syncId is! String ||
        syncId.isEmpty) {
      return;
    }
    final actionKey = checklistActionKey(
      sourceType: sourceType,
      itemId: itemId,
      kind: kind,
    );
    removeAppliedChecklistActionsForItem(
      '$sourceType:$itemId',
      exceptActionKey: actionKey,
    );
    appliedChecklistActions[actionKey] = Map<String, dynamic>.from(payload);
  }

  void removeAppliedChecklistActionsForItem(
    String itemKey, {
    String? exceptActionKey,
  }) {
    appliedChecklistActions.removeWhere(
      (key, _) => key.startsWith('$itemKey:') && key != exceptActionKey,
    );
  }

  void retainAppliedChecklistActionsForCompletedItems(Set<String> itemKeys) {
    appliedChecklistActions.removeWhere((_, payload) {
      final sourceType = payload['sourceType'];
      final itemId = payload['itemId'];
      if (sourceType is! String || itemId is! String) {
        return true;
      }
      return !itemKeys.contains('$sourceType:$itemId');
    });
  }

  Map<String, dynamic>? latestAppliedChecklistActionForItem(String itemKey) {
    Map<String, dynamic>? latest;
    for (final entry in appliedChecklistActions.entries) {
      if (!entry.key.startsWith('$itemKey:')) {
        continue;
      }
      if (latest == null ||
          _payloadOccurredAtMs(entry.value) > _payloadOccurredAtMs(latest)) {
        latest = entry.value;
      }
    }
    return latest;
  }

  bool isOlderChecklistAction(
    String itemKey,
    Map<String, dynamic> payload,
  ) {
    final latest = latestAppliedChecklistActionForItem(itemKey);
    if (latest == null) {
      return false;
    }
    final latestSyncId = latest['syncId'];
    final payloadSyncId = payload['syncId'];
    if (latestSyncId is String &&
        payloadSyncId is String &&
        latestSyncId == payloadSyncId) {
      return false;
    }
    return _payloadOccurredAtMs(payload) < _payloadOccurredAtMs(latest);
  }

  int _payloadOccurredAtMs(Map<String, dynamic> payload) {
    return (payload['occurredAtMs'] as num?)?.toInt() ?? -1;
  }

  static String _newAuthToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class SyncEventReceipt {
  SyncEventReceipt({
    required this.syncId,
    required this.originDeviceId,
    required this.messageType,
    required this.payload,
    required this.serverSeq,
    Set<String>? receivedByDeviceIds,
  }) : receivedByDeviceIds = receivedByDeviceIds ?? <String>{};

  final String syncId;
  final String originDeviceId;
  final String messageType;
  final Map<String, dynamic> payload;
  int serverSeq;
  final Set<String> receivedByDeviceIds;

  Map<String, dynamic> toJson() => {
        'syncId': syncId,
        'originDeviceId': originDeviceId,
        'messageType': messageType,
        'serverSeq': serverSeq,
        'payload': payload,
        'receivedByDeviceIds': receivedByDeviceIds.toList(growable: false),
      };

  factory SyncEventReceipt.fromJson(Map<String, dynamic> json) {
    final syncId = json['syncId'] as String;
    final originDeviceId = json['originDeviceId'] as String? ?? '';
    return SyncEventReceipt(
      syncId: syncId,
      originDeviceId: originDeviceId,
      messageType: json['messageType'] as String,
      serverSeq: (json['serverSeq'] as num?)?.toInt() ?? 0,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      receivedByDeviceIds: {
        ...((json['receivedByDeviceIds'] as List?) ?? const <dynamic>[])
            .whereType<String>(),
      },
    );
  }
}

class HouseholdStore {
  HouseholdStore(this.dataDirectory);

  final Directory dataDirectory;
  final Map<String, Household> _households = <String, Household>{};
  Future<void> _flushQueue = Future<void>.value();

  File get _file => File('${dataDirectory.path}/households.json');
  Iterable<Household> get households => _households.values;

  Household? household(String? id) => id == null ? null : _households[id];

  Household adoptExisting(
    String id,
    String saltBase64,
    String authToken, {
    List<HouseholdDevice> devices = const <HouseholdDevice>[],
  }) {
    final household = Household(
      id: id,
      saltBase64: saltBase64,
      authToken: authToken,
    );
    for (final device in devices) {
      household.devices[device.deviceId] = device;
    }
    _households[id] = household;
    return household;
  }

  Household create(String id, String saltBase64, String authToken) {
    final household =
        Household(id: id, saltBase64: saltBase64, authToken: authToken);
    _households[id] = household;
    return household;
  }

  Future<void> load() async {
    _households.clear();
    if (!await _file.exists()) {
      return;
    }

    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    final householdsJson =
        json['households'] as Map<String, dynamic>? ?? <String, dynamic>{};
    for (final entry in householdsJson.entries) {
      _households[entry.key] =
          Household.fromJson(entry.value as Map<String, dynamic>);
    }
  }

  Future<void> flush() {
    final nextFlush = _flushQueue.then((_) => _flushNow());
    _flushQueue = nextFlush.catchError((_) {});
    return nextFlush;
  }

  Future<void> _flushNow() async {
    if (!await dataDirectory.exists()) {
      await dataDirectory.create(recursive: true);
    }
    final payload = jsonEncode({
      'households': _households.map(
        (id, household) => MapEntry(id, household.toJson()),
      ),
    });
    final tempFile = File('${_file.path}.tmp');
    final backupFile = File('${_file.path}.bak');
    await tempFile.writeAsString(payload, flush: true);
    if (await backupFile.exists()) {
      await _deleteIfExists(backupFile);
    }
    var oldFileMoved = false;
    try {
      if (await _file.exists()) {
        await _file.rename(backupFile.path);
        oldFileMoved = true;
      }
      await tempFile.rename(_file.path);
      if (await backupFile.exists()) {
        await _deleteIfExists(backupFile);
      }
    } on Object {
      if (oldFileMoved && !await _file.exists() && await backupFile.exists()) {
        await backupFile.rename(_file.path);
      }
      if (await tempFile.exists()) {
        await _deleteIfExists(tempFile);
      }
      rethrow;
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on PathNotFoundException {
      // Another filesystem actor already removed it. The desired state holds.
    }
  }
}
