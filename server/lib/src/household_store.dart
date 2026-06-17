import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class HouseholdDevice {
  HouseholdDevice({
    required this.deviceId,
    required this.name,
    this.servedPetId,
    this.lastSeenMs,
  });

  final String deviceId;
  String name;
  String? servedPetId;
  int? lastSeenMs;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'servedPetId': servedPetId,
        'lastSeenMs': lastSeenMs,
      };

  factory HouseholdDevice.fromJson(Map<String, dynamic> json) =>
      HouseholdDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        servedPetId: json['servedPetId'] as String?,
        lastSeenMs: json['lastSeenMs'] as int?,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'saltBase64': saltBase64,
        'authToken': authToken,
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

    return household;
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
    Set<String>? receivedByDeviceIds,
  }) : receivedByDeviceIds = receivedByDeviceIds ?? <String>{};

  final String syncId;
  final String originDeviceId;
  final String messageType;
  final Map<String, dynamic> payload;
  final Set<String> receivedByDeviceIds;

  Map<String, dynamic> toJson() => {
        'syncId': syncId,
        'originDeviceId': originDeviceId,
        'messageType': messageType,
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

  File get _file => File('${dataDirectory.path}/households.json');

  Household? household(String? id) => id == null ? null : _households[id];

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

  Future<void> flush() async {
    if (!await dataDirectory.exists()) {
      await dataDirectory.create(recursive: true);
    }
    await _file.writeAsString(
      jsonEncode({
        'households': _households.map(
          (id, household) => MapEntry(id, household.toJson()),
        ),
      }),
    );
  }
}
