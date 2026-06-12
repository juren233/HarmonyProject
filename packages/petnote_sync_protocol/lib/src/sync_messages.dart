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
      'pair_create'; // owner→srv {householdId?, deviceId, deviceName}
  static const pairCreated =
      'pair_created'; // srv→owner {code, saltBase64, authToken, expiresAtMs, householdId}
  static const pairJoin = 'pair_join'; // pet→srv {code, deviceId, deviceName}
  static const pairJoined =
      'pair_joined'; // srv→pet {householdId, saltBase64, authToken}
  static const pairPeerJoined =
      'pair_peer_joined'; // srv→owner {deviceId, deviceName}
  static const pairError = 'pair_error'; // srv→client {message}
  // 会话
  static const hello =
      'hello'; // client→srv {householdId, deviceId, role, authToken, deviceName}
  static const helloAck = 'hello_ack'; // srv→client {snapshotVersion}
  // 快照同步
  static const snapshotPush =
      'snapshot_push'; // owner→srv {version, ciphertext}
  static const snapshot = 'snapshot'; // srv→pet {version, ciphertext}
  static const snapshotRequest = 'snapshot_request'; // pet→srv {}
  // 宠物端动作
  static const actionPush = 'action_push'; // pet→srv {actionId, ciphertext}
  static const action = 'action'; // srv→owner {actionId, ciphertext}
  static const actionAck = 'action_ack'; // owner→srv {actionId}
  // 设备管理
  static const devicesRequest = 'devices_request'; // owner→srv {}
  static const devices = 'devices'; // srv→owner {devices: [...]}
  static const deviceUpdate =
      'device_update'; // owner→srv {deviceId, name?, servedPetId?}
  static const deviceRemove = 'device_remove'; // owner→srv {deviceId}
  static const deviceConfig =
      'device_config'; // srv→pet {servedPetId?, removed?}
  // 二期视频信令（本期定义 + 服务器按 targetDeviceId 透传）
  static const callInvite =
      'call_invite'; // {callId, mode: call|watch, sdp, targetDeviceId}
  static const callAnswer = 'call_answer'; // {callId, sdp, targetDeviceId}
  static const callReject = 'call_reject'; // {callId, reason, targetDeviceId}
  static const callEnd = 'call_end'; // {callId, targetDeviceId}
  static const iceCandidate =
      'ice_candidate'; // {callId, candidate, targetDeviceId}
}

enum PetActionKind { markDone, postpone, skip }

/// 宠物端回传的操作（加密后放进 action_push.ciphertext）。
class PetAction {
  const PetAction(
      {required this.kind, required this.sourceType, required this.itemId});

  final PetActionKind kind;
  final String
      sourceType; // 'todo' | 'reminder'，与 PetNoteStore.markChecklistDone 一致
  final String itemId;

  Map<String, dynamic> toJson() =>
      {'kind': kind.name, 'sourceType': sourceType, 'itemId': itemId};

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
  final String role; // 'owner' | 'pet'
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
      role: json['role'] as String? ?? 'pet',
      servedPetId: json['servedPetId'] as String?,
      online: json['online'] == true,
      lastSeenMs: json['lastSeenMs'] as int?,
    );
  }
}
