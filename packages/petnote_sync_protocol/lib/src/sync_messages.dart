import 'dart:convert';

/// WebSocket 消息信封：{"type": "...", "payload": {...}}
class SyncMessage {
  const SyncMessage(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;

  String encode() => jsonEncode({'type': type, 'payload': payload});

  factory SyncMessage.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> || json['type'] is! String) {
      throw const FormatException('invalid sync message');
    }
    return SyncMessage(
      json['type'] as String,
      Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    );
  }
}

/// 协议消息类型。二期信令消息（call*/ice）本期仅定义并由服务器透传。
class SyncMessageTypes {
  // 配对
  static const pairCreate =
      'pair_create'; // device→srv {householdId?, authToken?, sharedKeyBase64?, deviceId, deviceName, role?}
  static const pairCreated =
      'pair_created'; // srv→device {code, saltBase64, authToken, expiresAtMs, householdId, restoredHousehold?}
  static const pairJoin =
      'pair_join'; // device→srv {code, deviceId, deviceName, role?}
  static const pairJoined =
      'pair_joined'; // srv→device {householdId, saltBase64, authToken, sharedKeyBase64?}
  static const pairPeerJoined =
      'pair_peer_joined'; // srv→已在线设备 {deviceId, deviceName}
  static const pairError = 'pair_error'; // srv→client {message}
  // 会话
  static const hello =
      'hello'; // client→srv {householdId, deviceId, role, authToken?, deviceName}
  static const helloAck =
      'hello_ack'; // srv→client {snapshotVersion, authToken?, restoredHousehold?, restoredDevice?}
  // 快照同步
  static const snapshotPush =
      'snapshot_push'; // device→srv {version, ciphertext, completedItemKeys?}
  static const snapshot = 'snapshot'; // srv→device {version, ciphertext}
  static const snapshotRequest = 'snapshot_request'; // device→srv {}
  // 设备动作
  static const actionPush =
      'action_push'; // device→srv {actionId, ciphertext, kind, sourceType, itemId}
  static const action =
      'action'; // srv→device {actionId, ciphertext, kind?, sourceType?, itemId?}
  static const actionAck = 'action_ack'; // device→srv {actionId}
  static const mutationPush =
      'mutation_push'; // device→srv {mutationId, ciphertext, entityType, entityId, kind}
  static const mutation =
      'mutation'; // srv→device {mutationId, ciphertext, entityType, entityId, kind}
  static const syncReceived =
      'sync_received'; // device↔srv {syncId, originDeviceId?, receivedDeviceId?, actionId?, kind?, sourceType?, itemId?}
  // 设备管理
  static const devicesRequest = 'devices_request'; // device→srv {}
  static const devices = 'devices'; // srv→device {devices: [...]}
  static const deviceUpdate =
      'device_update'; // owner→srv {deviceId, name?, servedPetId?}
  static const deviceRemove = 'device_remove'; // owner→srv {deviceId}
  static const deviceConfig =
      'device_config'; // srv→device {servedPetId?, removed?}
  // 二期视频信令（本期定义 + 服务器按 targetDeviceId 透传）
  static const callInvite =
      'call_invite'; // {callId, mode: call|watch, callerDeviceId, sdp, targetDeviceId}
  static const callAnswer = 'call_answer'; // {callId, sdp, targetDeviceId}
  static const callReject = 'call_reject'; // {callId, reason, targetDeviceId}
  static const callEnd = 'call_end'; // {callId, targetDeviceId}
  static const iceCandidate =
      'ice_candidate'; // {callId, candidate, targetDeviceId}
}

enum PetActionKind { markDone, postpone, skip }

enum SyncDataPolicy { remoteWins, localWins, merge }

enum PetNoteEntityType { pet, todo, reminder, record }

enum PetNoteMutationKind { upsert, delete, checklistAction }

/// 设备回传的操作（加密后放进 action_push.ciphertext）。
class PetAction {
  const PetAction({
    required this.kind,
    required this.sourceType,
    required this.itemId,
    this.occurredAtMs,
  });

  final PetActionKind kind;
  final String
      sourceType; // 'todo' | 'reminder'，与 PetNoteStore.markChecklistDone 一致
  final String itemId;
  final int? occurredAtMs;

  String get dedupeKey => '$sourceType:$itemId:${kind.name}';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'sourceType': sourceType,
        'itemId': itemId,
        if (occurredAtMs != null) 'occurredAtMs': occurredAtMs,
      };

  factory PetAction.fromJson(Map<String, dynamic> json) {
    final sourceType = json['sourceType'];
    final itemId = json['itemId'];
    if (sourceType is! String || itemId is! String) {
      throw const FormatException('invalid PetAction fields');
    }
    return PetAction(
      kind: PetActionKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => throw const FormatException('unknown PetAction kind'),
      ),
      sourceType: sourceType,
      itemId: itemId,
      occurredAtMs: (json['occurredAtMs'] as num?)?.toInt(),
    );
  }
}

class PetNoteMutation {
  const PetNoteMutation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.kind,
    this.data,
    this.actionKind,
    this.occurredAtMs,
  });

  final String id;
  final PetNoteEntityType entityType;
  final String entityId;
  final PetNoteMutationKind kind;
  final Map<String, dynamic>? data;
  final PetActionKind? actionKind;
  final int? occurredAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType.name,
        'entityId': entityId,
        'kind': kind.name,
        if (data != null) 'data': data,
        if (actionKind != null) 'actionKind': actionKind!.name,
        if (occurredAtMs != null) 'occurredAtMs': occurredAtMs,
      };

  factory PetNoteMutation.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final entityId = json['entityId'];
    if (id is! String || id.isEmpty || entityId is! String || entityId.isEmpty) {
      throw const FormatException('invalid PetNoteMutation fields');
    }
    final data = json['data'];
    return PetNoteMutation(
      id: id,
      entityType: PetNoteEntityType.values.firstWhere(
        (type) => type.name == json['entityType'],
        orElse: () => throw const FormatException('unknown entity type'),
      ),
      entityId: entityId,
      kind: PetNoteMutationKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => throw const FormatException('unknown mutation kind'),
      ),
      data: data is Map ? Map<String, dynamic>.from(data) : null,
      actionKind: json['actionKind'] == null
          ? null
          : PetActionKind.values.firstWhere(
              (kind) => kind.name == json['actionKind'],
              orElse: () => throw const FormatException('unknown action kind'),
            ),
      occurredAtMs: (json['occurredAtMs'] as num?)?.toInt(),
    );
  }
}

/// 设备目录条目（服务器维护，devices 消息返回）。
class SyncedDeviceInfo {
  const SyncedDeviceInfo({
    required this.deviceId,
    required this.name,
    required this.role,
    this.servedPetId,
    this.online = false,
    this.lastSeenMs,
  });

  final String deviceId;
  final String name;
  final String role; // 'owner' | 'pet' | 'unknown'
  final String? servedPetId;
  final bool online;
  final int? lastSeenMs;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'role': role,
        'servedPetId': servedPetId,
        'online': online,
        'lastSeenMs': lastSeenMs,
      };

  factory SyncedDeviceInfo.fromJson(Map<String, dynamic> json) {
    return SyncedDeviceInfo(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String? ?? '未命名设备',
      role: json['role'] as String? ?? 'unknown',
      servedPetId: json['servedPetId'] as String?,
      online: json['online'] == true,
      lastSeenMs: json['lastSeenMs'] as int?,
    );
  }
}
