# 一期：设备角色 + 配对同步 + 宠物端看板 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现设备角色选择（爱宠/主人）、自建 Dart 中继服务器的无账号配对与端到端加密同步、宠物端贴纸看板与三端保活、爱宠页副标题三态、远程视频入口 UI。

**Architecture:** 单写者快照同步——主人端为唯一权威数据源，复用 `PetNoteDataState` 整体加密推送；宠物端经 `replaceAllData` 写入本地副本。新增纯 Dart 协议包（App/服务器共享）+ shelf WebSocket 中继服务器。角色路由在 `PetNoteApp` 的 home 分支处切换主人壳层 / 宠物端看板。

**Tech Stack:** Flutter（Android/iOS/ohos）、sembast、shared_preferences、`cryptography`（HKDF + AES-GCM，纯 Dart）、shelf + shelf_web_socket（服务器）、Docker Compose 部署。

**项目纪律（来自全局约束，每个任务都必须遵守）：**
- 测试只能定向跑单个文件（`flutter test test/<file>.dart` / 包内 `dart test`），**禁止全量 `flutter test`**；
- 不操作真机/模拟器，客户端验证止于构建成功；
- pub 源用镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；
- ohpm install 期间确保 codegraph 文件监视器不在运行（历史 EPERM 卡死问题）。

**规格文档：** `docs/superpowers/specs/2026-06-11-device-roles-pairing-sync-design.md`

---

## Part A：协议包与服务器（纯 Dart，可独立闭环验证）

### Task 1: 协议包骨架与加密模块

**Files:**
- Create: `packages/petnote_sync_protocol/pubspec.yaml`
- Create: `packages/petnote_sync_protocol/lib/petnote_sync_protocol.dart`
- Create: `packages/petnote_sync_protocol/lib/src/sync_crypto.dart`
- Test: `packages/petnote_sync_protocol/test/sync_crypto_test.dart`

- [ ] **Step 1: 创建包骨架**

`packages/petnote_sync_protocol/pubspec.yaml`：

```yaml
name: petnote_sync_protocol
description: PetNote multi-device sync protocol shared by app and server.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.6.2

dependencies:
  cryptography: ^2.7.0

dev_dependencies:
  test: ^1.25.0
```

`packages/petnote_sync_protocol/lib/petnote_sync_protocol.dart`：

```dart
export 'src/sync_crypto.dart';
export 'src/sync_messages.dart';
```

（`sync_messages.dart` 在 Task 2 创建，此时先建空文件 `lib/src/sync_messages.dart` 内容为空注释 `// Task 2`，保证 export 不报错。）

- [ ] **Step 2: 写加密模块失败测试**

`packages/petnote_sync_protocol/test/sync_crypto_test.dart`：

```dart
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('同一配对码与盐派生的密钥可以加解密往返', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final b = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final cipher = await a.encryptString('{"pets":[]}');
    expect(await b.decryptString(cipher), '{"pets":[]}');
  });

  test('错误配对码解密失败', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final wrong = await SyncCrypto.deriveFromPairingCode(code: '654321', saltBase64: salt);
    final cipher = await a.encryptString('secret');
    expect(() => wrong.decryptString(cipher), throwsA(anything));
  });

  test('密钥可导出并恢复', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final restored = SyncCrypto.fromKeyBase64(await a.exportKeyBase64());
    expect(await restored.decryptString(await a.encryptString('hi')), 'hi');
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd packages/petnote_sync_protocol
PUB_HOSTED_URL=https://pub.flutter-io.cn dart pub get
dart test
```
预期：编译失败（SyncCrypto 未定义）。

- [ ] **Step 4: 实现 `sync_crypto.dart`**

```dart
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 同步数据端到端加密：HKDF-SHA256 从配对码+盐派生 AES-256-GCM 密钥。
class SyncCrypto {
  SyncCrypto(this._secretKey);

  final SecretKey _secretKey;
  static final AesGcm _aes = AesGcm.with256bits();

  static String generateSaltBase64() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  static Future<SyncCrypto> deriveFromPairingCode({
    required String code,
    required String saltBase64,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: base64Decode(saltBase64),
      info: utf8.encode('petnote-sync-v1'),
    );
    return SyncCrypto(key);
  }

  static SyncCrypto fromKeyBase64(String keyBase64) {
    return SyncCrypto(SecretKey(base64Decode(keyBase64)));
  }

  Future<String> exportKeyBase64() async {
    return base64Encode(await _secretKey.extractBytes());
  }

  Future<String> encryptString(String plaintext) async {
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: _secretKey);
    return base64Encode(box.concatenation());
  }

  Future<String> decryptString(String payloadBase64) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(payloadBase64),
      nonceLength: 12,
      macLength: 16,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _secretKey));
  }
}
```

- [ ] **Step 5: 运行测试通过后提交**

```bash
dart test   # 预期 3 个测试全部 PASS
git add packages/petnote_sync_protocol
git commit -m "feat(sync): add sync protocol package with HKDF/AES-GCM crypto"
```

### Task 2: 同步消息模型

**Files:**
- Modify: `packages/petnote_sync_protocol/lib/src/sync_messages.dart`
- Test: `packages/petnote_sync_protocol/test/sync_messages_test.dart`

- [ ] **Step 1: 写编解码失败测试**

```dart
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('消息 JSON 编解码往返', () {
    final message = SyncMessage(SyncMessageTypes.snapshotPush, {
      'version': 3,
      'ciphertext': 'abc',
    });
    final decoded = SyncMessage.decode(message.encode());
    expect(decoded.type, SyncMessageTypes.snapshotPush);
    expect(decoded.payload['version'], 3);
  });

  test('PetAction 编解码往返', () {
    final action = PetAction(kind: PetActionKind.markDone, sourceType: 'todo', itemId: 't1');
    final decoded = PetAction.fromJson(action.toJson());
    expect(decoded.kind, PetActionKind.markDone);
    expect(decoded.sourceType, 'todo');
    expect(decoded.itemId, 't1');
  });

  test('非法 JSON 抛 FormatException', () {
    expect(() => SyncMessage.decode('not json'), throwsFormatException);
  });
}
```

- [ ] **Step 2: 运行 `dart test test/sync_messages_test.dart` 确认失败**

- [ ] **Step 3: 实现 `sync_messages.dart`**

```dart
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
  static const pairCreate = 'pair_create'; // owner→srv {householdId?, deviceId, deviceName}
  static const pairCreated = 'pair_created'; // srv→owner {code, saltBase64, expiresAtMs, householdId}
  static const pairJoin = 'pair_join'; // pet→srv {code, deviceId, deviceName}
  static const pairJoined = 'pair_joined'; // srv→pet {householdId, saltBase64}
  static const pairPeerJoined = 'pair_peer_joined'; // srv→owner {deviceId, deviceName}
  static const pairError = 'pair_error'; // srv→client {message}
  // 会话
  static const hello = 'hello'; // client→srv {householdId, deviceId, role, deviceName}
  static const helloAck = 'hello_ack'; // srv→client {snapshotVersion}
  // 快照同步
  static const snapshotPush = 'snapshot_push'; // owner→srv {version, ciphertext}
  static const snapshot = 'snapshot'; // srv→pet {version, ciphertext}
  static const snapshotRequest = 'snapshot_request'; // pet→srv {}
  // 宠物端动作
  static const actionPush = 'action_push'; // pet→srv {actionId, ciphertext}
  static const action = 'action'; // srv→owner {actionId, ciphertext}
  static const actionAck = 'action_ack'; // owner→srv {actionId}
  // 设备管理
  static const devicesRequest = 'devices_request'; // owner→srv {}
  static const devices = 'devices'; // srv→owner {devices: [...]}
  static const deviceUpdate = 'device_update'; // owner→srv {deviceId, name?, servedPetId?}
  static const deviceRemove = 'device_remove'; // owner→srv {deviceId}
  static const deviceConfig = 'device_config'; // srv→pet {servedPetId?, removed?}
  // 二期视频信令（本期定义 + 服务器按 targetDeviceId 透传）
  static const callInvite = 'call_invite'; // {callId, mode: call|watch, sdp, targetDeviceId}
  static const callAnswer = 'call_answer'; // {callId, sdp, targetDeviceId}
  static const callReject = 'call_reject'; // {callId, reason, targetDeviceId}
  static const callEnd = 'call_end'; // {callId, targetDeviceId}
  static const iceCandidate = 'ice_candidate'; // {callId, candidate, targetDeviceId}
}

enum PetActionKind { markDone, postpone, skip }

/// 宠物端回传的操作（加密后放进 action_push.ciphertext）。
class PetAction {
  const PetAction({required this.kind, required this.sourceType, required this.itemId});

  final PetActionKind kind;
  final String sourceType; // 'todo' | 'reminder'，与 PetNoteStore.markChecklistDone 一致
  final String itemId;

  Map<String, dynamic> toJson() =>
      {'kind': kind.name, 'sourceType': sourceType, 'itemId': itemId};

  factory PetAction.fromJson(Map<String, dynamic> json) {
    return PetAction(
      kind: PetActionKind.values.firstWhere((k) => k.name == json['kind']),
      sourceType: json['sourceType'] as String,
      itemId: json['itemId'] as String,
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
```

- [ ] **Step 4: `dart test` 全包通过**

- [ ] **Step 5: 提交**

```bash
git add packages/petnote_sync_protocol
git commit -m "feat(sync): define sync/pairing/action/signaling message protocol"
```

### Task 3: 服务器骨架（shelf + WebSocket Hub）

**Files:**
- Create: `server/pubspec.yaml`
- Create: `server/bin/petnote_sync_server.dart`
- Create: `server/lib/src/server_app.dart`
- Create: `server/lib/src/ws_hub.dart`
- Test: `server/test/server_app_test.dart`

- [ ] **Step 1: 包骨架**

`server/pubspec.yaml`：

```yaml
name: petnote_sync_server
description: Self-hosted relay server for PetNote pairing, sync and signaling.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.6.2

dependencies:
  petnote_sync_protocol:
    path: ../packages/petnote_sync_protocol
  shelf: ^1.4.2
  shelf_web_socket: ^2.0.1
  web_socket_channel: ^3.0.2

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 2: 写失败测试（健康检查 + WS hello 收到 pair_error 之外的有效响应）**

`server/test/server_app_test.dart`：

```dart
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  late SyncServerApp app;
  late HttpServer server;

  setUp(() async {
    app = SyncServerApp(dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'));
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    await app.close();
    await server.close(force: true);
  });

  test('healthz 返回 ok', () async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/healthz'));
    final response = await request.close();
    expect(response.statusCode, 200);
    client.close();
  });

  test('未知 household 的 hello 收到 pair_error', () async {
    final ws = IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}/ws');
    ws.sink.add(SyncMessage(SyncMessageTypes.hello, {
      'householdId': 'nope',
      'deviceId': 'd1',
      'role': 'pet',
      'deviceName': 'tablet',
    }).encode());
    final reply = SyncMessage.decode(await ws.stream.first as String);
    expect(reply.type, SyncMessageTypes.pairError);
    await ws.sink.close();
  });
}
```

- [ ] **Step 3: `cd server && dart pub get && dart test` 确认失败**

- [ ] **Step 4: 实现骨架**

`server/lib/src/ws_hub.dart`：

```dart
import 'package:web_socket_channel/web_socket_channel.dart';

/// 按 household/device 维护活动连接，提供定向发送。
class WsHub {
  final Map<String, Map<String, WebSocketChannel>> _connections = {};

  void register(String householdId, String deviceId, WebSocketChannel channel) {
    _connections.putIfAbsent(householdId, () => {})[deviceId] = channel;
  }

  void unregister(String householdId, String deviceId, WebSocketChannel channel) {
    final household = _connections[householdId];
    if (household != null && identical(household[deviceId], channel)) {
      household.remove(deviceId);
      if (household.isEmpty) _connections.remove(householdId);
    }
  }

  bool isOnline(String householdId, String deviceId) =>
      _connections[householdId]?.containsKey(deviceId) ?? false;

  void sendTo(String householdId, String deviceId, String encodedMessage) {
    _connections[householdId]?[deviceId]?.sink.add(encodedMessage);
  }

  Iterable<String> onlineDevices(String householdId) =>
      _connections[householdId]?.keys ?? const Iterable.empty();

  Future<void> closeAll() async {
    for (final household in _connections.values) {
      for (final channel in household.values) {
        await channel.sink.close();
      }
    }
    _connections.clear();
  }
}
```

`server/lib/src/server_app.dart`（本任务先实现骨架：healthz、WS 升级、对未知消息/未知 household 回 `pair_error`；会话状态机在 Task 5 完成）：

```dart
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'pairing_service.dart';
import 'session_handler.dart';
import 'ws_hub.dart';

class SyncServerApp {
  SyncServerApp({required Directory dataDirectory})
      : store = HouseholdStore(dataDirectory),
        hub = WsHub() {
    pairing = PairingService(store);
  }

  final HouseholdStore store;
  final WsHub hub;
  late final PairingService pairing;

  Future<HttpServer> serve({required InternetAddress address, required int port}) async {
    await store.load();
    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(_route);
    return shelf_io.serve(handler, address, port);
  }

  Future<Response> _route(Request request) async {
    if (request.url.path == 'healthz') {
      return Response.ok('ok');
    }
    if (request.url.path == 'ws') {
      return webSocketHandler((WebSocketChannel channel, _) {
        SessionHandler(app: this, channel: channel).bind();
      })(request);
    }
    return Response.notFound('not found');
  }

  Future<void> close() async {
    await hub.closeAll();
    await store.flush();
  }
}
```

`server/lib/src/session_handler.dart` 本任务版本（Task 5 扩展）：

```dart
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server_app.dart';

/// 每条 WebSocket 连接一个会话。hello/pair 之后才进入已认证状态。
class SessionHandler {
  SessionHandler({required this.app, required this.channel});

  final SyncServerApp app;
  final WebSocketChannel channel;

  String? householdId;
  String? deviceId;

  void bind() {
    channel.stream.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
  }

  void _onData(dynamic raw) {
    final SyncMessage message;
    try {
      message = SyncMessage.decode(raw as String);
    } on FormatException {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    handle(message);
  }

  void handle(SyncMessage message) {
    switch (message.type) {
      case SyncMessageTypes.hello:
        _handleHello(message);
      default:
        _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'unsupported'}));
    }
  }

  void _handleHello(SyncMessage message) {
    final household = app.store.household(message.payload['householdId'] as String?);
    if (household == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'unknown household'}));
      return;
    }
    householdId = household.id;
    deviceId = message.payload['deviceId'] as String;
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.helloAck, {'snapshotVersion': household.snapshotVersion}));
  }

  void _onDone() {
    if (householdId != null && deviceId != null) {
      app.hub.unregister(householdId!, deviceId!, channel);
    }
  }

  void _send(SyncMessage message) => channel.sink.add(message.encode());
}
```

`server/bin/petnote_sync_server.dart`：

```dart
import 'dart:io';

import 'package:petnote_sync_server/src/server_app.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;
  final dataDir = Directory(Platform.environment['DATA_DIR'] ?? './data')..createSync(recursive: true);
  final app = SyncServerApp(dataDirectory: dataDir);
  final server = await app.serve(address: InternetAddress.anyIPv4, port: port);
  stdout.writeln('petnote sync server listening on :${server.port}');
}
```

注意：本任务还需创建 Task 4/5 的最小占位实现 `household_store.dart`（`HouseholdStore.load/flush/household()` 返回 null）与 `pairing_service.dart`（空类），保证编译通过；其完整实现与测试在 Task 4、5。占位实现必须可编译且 `household()` 对任何 id 返回 `null`（满足本任务测试）。

- [ ] **Step 5: `dart test` 通过后提交**

```bash
git add server
git commit -m "feat(server): shelf websocket relay skeleton with hello session"
```

### Task 4: 配对服务与 Household 持久化

**Files:**
- Modify: `server/lib/src/household_store.dart`
- Modify: `server/lib/src/pairing_service.dart`
- Test: `server/test/pairing_test.dart`

- [ ] **Step 1: 写失败测试**

`server/test/pairing_test.dart`：

```dart
import 'dart:io';

import 'package:petnote_sync_server/src/household_store.dart';
import 'package:petnote_sync_server/src/pairing_service.dart';
import 'package:test/test.dart';

void main() {
  late HouseholdStore store;
  late PairingService pairing;

  setUp(() async {
    store = HouseholdStore(Directory.systemTemp.createTempSync('petnote_pair_'));
    await store.load();
    pairing = PairingService(store);
  });

  test('创建配对码并兑换建立 household 与设备', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      ownerDeviceId: 'owner-1',
      ownerDeviceName: '我的手机',
    );
    expect(created.code.length, 6);
    final joined = pairing.redeem(
      code: created.code,
      petDeviceId: 'pet-1',
      petDeviceName: '客厅平板',
    );
    expect(joined, isNotNull);
    expect(joined!.householdId, created.householdId);
    expect(joined.saltBase64, created.saltBase64);
    final household = store.household(created.householdId)!;
    expect(household.devices.keys, containsAll(['owner-1', 'pet-1']));
  });

  test('配对码只能兑换一次且过期失效', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      ownerDeviceId: 'owner-1',
      ownerDeviceName: '我的手机',
      now: DateTime.utc(2026, 1, 1),
    );
    expect(
      pairing.redeem(code: created.code, petDeviceId: 'p', petDeviceName: 'p',
          now: DateTime.utc(2026, 1, 1, 0, 6)),
      isNull, // 超过 5 分钟
    );
  });

  test('快照与设备信息可持久化重载', () async {
    final created = pairing.createCode(
        existingHouseholdId: null, ownerDeviceId: 'o', ownerDeviceName: 'o');
    store.household(created.householdId)!
      ..snapshotVersion = 7
      ..snapshotCiphertext = 'cipher';
    await store.flush();
    final reloaded = HouseholdStore(store.dataDirectory);
    await reloaded.load();
    expect(reloaded.household(created.householdId)!.snapshotVersion, 7);
    expect(reloaded.household(created.householdId)!.snapshotCiphertext, 'cipher');
  });
}
```

- [ ] **Step 2: `dart test test/pairing_test.dart` 确认失败**

- [ ] **Step 3: 实现**

`server/lib/src/household_store.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class HouseholdDevice {
  HouseholdDevice({required this.deviceId, required this.name, required this.role,
      this.servedPetId, this.lastSeenMs});

  final String deviceId;
  String name;
  final String role;
  String? servedPetId;
  int? lastSeenMs;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId, 'name': name, 'role': role,
        'servedPetId': servedPetId, 'lastSeenMs': lastSeenMs,
      };

  factory HouseholdDevice.fromJson(Map<String, dynamic> json) => HouseholdDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        servedPetId: json['servedPetId'] as String?,
        lastSeenMs: json['lastSeenMs'] as int?,
      );
}

class Household {
  Household({required this.id, required this.saltBase64});

  final String id;
  final String saltBase64;
  int snapshotVersion = 0;
  String? snapshotCiphertext;
  final Map<String, HouseholdDevice> devices = {};
  final List<Map<String, dynamic>> pendingActions = []; // {actionId, ciphertext}

  Map<String, dynamic> toJson() => {
        'id': id, 'saltBase64': saltBase64,
        'snapshotVersion': snapshotVersion,
        'snapshotCiphertext': snapshotCiphertext,
        'devices': devices.map((k, v) => MapEntry(k, v.toJson())),
        'pendingActions': pendingActions,
      };

  factory Household.fromJson(Map<String, dynamic> json) {
    final household = Household(id: json['id'] as String, saltBase64: json['saltBase64'] as String)
      ..snapshotVersion = json['snapshotVersion'] as int? ?? 0
      ..snapshotCiphertext = json['snapshotCiphertext'] as String?;
    (json['devices'] as Map? ?? {}).forEach((key, value) {
      household.devices[key as String] =
          HouseholdDevice.fromJson(Map<String, dynamic>.from(value as Map));
    });
    for (final action in (json['pendingActions'] as List? ?? [])) {
      household.pendingActions.add(Map<String, dynamic>.from(action as Map));
    }
    return household;
  }
}

/// 文件持久化的 household 仓库（<dataDir>/households.json）。
class HouseholdStore {
  HouseholdStore(this.dataDirectory);

  final Directory dataDirectory;
  final Map<String, Household> _households = {};

  File get _file => File('${dataDirectory.path}/households.json');

  Household? household(String? id) => id == null ? null : _households[id];

  Household create(String id, String saltBase64) =>
      _households[id] = Household(id: id, saltBase64: saltBase64);

  Future<void> load() async {
    if (!_file.existsSync()) return;
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    (json['households'] as Map? ?? {}).forEach((key, value) {
      _households[key as String] =
          Household.fromJson(Map<String, dynamic>.from(value as Map));
    });
  }

  Future<void> flush() async {
    await _file.writeAsString(jsonEncode({
      'households': _households.map((k, v) => MapEntry(k, v.toJson())),
    }));
  }
}
```

`server/lib/src/pairing_service.dart`：

```dart
import 'dart:math';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

import 'household_store.dart';

class PairingCodeTicket {
  PairingCodeTicket({required this.code, required this.householdId,
      required this.saltBase64, required this.expiresAt});

  final String code;
  final String householdId;
  final String saltBase64;
  final DateTime expiresAt;
}

class PairingJoinResult {
  PairingJoinResult({required this.householdId, required this.saltBase64});

  final String householdId;
  final String saltBase64;
}

class PairingService {
  PairingService(this._store);

  static const Duration codeTtl = Duration(minutes: 5);

  final HouseholdStore _store;
  final Map<String, PairingCodeTicket> _activeCodes = {};
  final Random _random = Random.secure();

  PairingCodeTicket createCode({
    required String? existingHouseholdId,
    required String ownerDeviceId,
    required String ownerDeviceName,
    DateTime? now,
  }) {
    final issuedAt = now ?? DateTime.now().toUtc();
    final code = List.generate(6, (_) => _random.nextInt(10)).join();
    final household = _store.household(existingHouseholdId) ??
        _store.create(_newId(), SyncCrypto.generateSaltBase64());
    household.devices.putIfAbsent(
      ownerDeviceId,
      () => HouseholdDevice(deviceId: ownerDeviceId, name: ownerDeviceName, role: 'owner'),
    );
    final ticket = PairingCodeTicket(
      code: code,
      householdId: household.id,
      saltBase64: household.saltBase64,
      expiresAt: issuedAt.add(codeTtl),
    );
    _activeCodes[code] = ticket;
    return ticket;
  }

  PairingJoinResult? redeem({
    required String code,
    required String petDeviceId,
    required String petDeviceName,
    DateTime? now,
  }) {
    final ticket = _activeCodes.remove(code);
    final at = now ?? DateTime.now().toUtc();
    if (ticket == null || at.isAfter(ticket.expiresAt)) return null;
    final household = _store.household(ticket.householdId);
    if (household == null) return null;
    household.devices[petDeviceId] =
        HouseholdDevice(deviceId: petDeviceId, name: petDeviceName, role: 'pet');
    return PairingJoinResult(householdId: household.id, saltBase64: household.saltBase64);
  }

  String _newId() =>
      DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36) +
      _random.nextInt(1 << 32).toRadixString(36);
}
```

- [ ] **Step 4: `dart test test/pairing_test.dart` 通过；再跑 `dart test` 全包不回归**

- [ ] **Step 5: 提交**

```bash
git add server
git commit -m "feat(server): pairing codes and persistent household store"
```

### Task 5: 会话状态机：快照转发、Action 队列、设备管理

**Files:**
- Modify: `server/lib/src/session_handler.dart`
- Test: `server/test/sync_flow_test.dart`

- [ ] **Step 1: 写端到端失败测试**（起真实服务器，两个 WS 客户端走完整流程）

`server/test/sync_flow_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

class TestClient {
  TestClient(int port)
      : channel = IOWebSocketChannel.connect('ws://127.0.0.1:$port/ws') {
    channel.stream.listen((raw) => _controller.add(SyncMessage.decode(raw as String)));
  }

  final IOWebSocketChannel channel;
  final StreamController<SyncMessage> _controller = StreamController.broadcast();

  void send(String type, Map<String, dynamic> payload) =>
      channel.sink.add(SyncMessage(type, payload).encode());

  Future<SyncMessage> expectType(String type) =>
      _controller.stream.firstWhere((m) => m.type == type).timeout(const Duration(seconds: 5));

  Future<void> close() => channel.sink.close();
}

void main() {
  late SyncServerApp app;
  late HttpServer server;

  setUp(() async {
    app = SyncServerApp(dataDirectory: Directory.systemTemp.createTempSync('petnote_flow_'));
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    await app.close();
    await server.close(force: true);
  });

  test('配对 → 快照转发 → action 转发 → 设备管理 全流程', () async {
    final owner = TestClient(server.port);
    final pet = TestClient(server.port);

    // 1. 配对
    owner.send(SyncMessageTypes.pairCreate,
        {'deviceId': 'o1', 'deviceName': '手机'});
    final created = await owner.expectType(SyncMessageTypes.pairCreated);
    final code = created.payload['code'] as String;
    final householdId = created.payload['householdId'] as String;

    pet.send(SyncMessageTypes.pairJoin,
        {'code': code, 'deviceId': 'p1', 'deviceName': '平板'});
    final joined = await pet.expectType(SyncMessageTypes.pairJoined);
    expect(joined.payload['householdId'], householdId);
    await owner.expectType(SyncMessageTypes.pairPeerJoined);

    // 2. 双方 hello
    owner.send(SyncMessageTypes.hello,
        {'householdId': householdId, 'deviceId': 'o1', 'role': 'owner', 'deviceName': '手机'});
    await owner.expectType(SyncMessageTypes.helloAck);
    pet.send(SyncMessageTypes.hello,
        {'householdId': householdId, 'deviceId': 'p1', 'role': 'pet', 'deviceName': '平板'});
    await pet.expectType(SyncMessageTypes.helloAck);

    // 3. 快照推送 → 宠物端收到
    owner.send(SyncMessageTypes.snapshotPush, {'version': 1, 'ciphertext': 'c1'});
    final snapshot = await pet.expectType(SyncMessageTypes.snapshot);
    expect(snapshot.payload['version'], 1);
    expect(snapshot.payload['ciphertext'], 'c1');

    // 4. 宠物端 action → 主人端收到
    pet.send(SyncMessageTypes.actionPush, {'actionId': 'a1', 'ciphertext': 'ac1'});
    final action = await owner.expectType(SyncMessageTypes.action);
    expect(action.payload['actionId'], 'a1');
    owner.send(SyncMessageTypes.actionAck, {'actionId': 'a1'});

    // 5. 设备列表与改绑
    owner.send(SyncMessageTypes.devicesRequest, {});
    final devices = await owner.expectType(SyncMessageTypes.devices);
    expect((devices.payload['devices'] as List).length, 2);
    owner.send(SyncMessageTypes.deviceUpdate, {'deviceId': 'p1', 'servedPetId': 'pet-cat'});
    final config = await pet.expectType(SyncMessageTypes.deviceConfig);
    expect(config.payload['servedPetId'], 'pet-cat');

    await owner.close();
    await pet.close();
  });

  test('主人端离线时 action 入队，hello 后补发', () async {
    final owner = TestClient(server.port);
    owner.send(SyncMessageTypes.pairCreate, {'deviceId': 'o1', 'deviceName': '手机'});
    final created = await owner.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final code = created.payload['code'] as String;

    final pet = TestClient(server.port);
    pet.send(SyncMessageTypes.pairJoin,
        {'code': code, 'deviceId': 'p1', 'deviceName': '平板'});
    await pet.expectType(SyncMessageTypes.pairJoined);
    await owner.close(); // 主人端下线

    pet.send(SyncMessageTypes.hello,
        {'householdId': householdId, 'deviceId': 'p1', 'role': 'pet', 'deviceName': '平板'});
    await pet.expectType(SyncMessageTypes.helloAck);
    pet.send(SyncMessageTypes.actionPush, {'actionId': 'a2', 'ciphertext': 'x'});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final ownerBack = TestClient(server.port);
    ownerBack.send(SyncMessageTypes.hello,
        {'householdId': householdId, 'deviceId': 'o1', 'role': 'owner', 'deviceName': '手机'});
    await ownerBack.expectType(SyncMessageTypes.helloAck);
    final queued = await ownerBack.expectType(SyncMessageTypes.action);
    expect(queued.payload['actionId'], 'a2');

    await ownerBack.close();
    await pet.close();
  });
}
```

- [ ] **Step 2: `dart test test/sync_flow_test.dart` 确认失败**

- [ ] **Step 3: 扩展 `session_handler.dart` 的 `handle()`**

```dart
  void handle(SyncMessage message) {
    switch (message.type) {
      case SyncMessageTypes.pairCreate:
        _handlePairCreate(message);
      case SyncMessageTypes.pairJoin:
        _handlePairJoin(message);
      case SyncMessageTypes.hello:
        _handleHello(message);
      case SyncMessageTypes.snapshotPush:
        _handleSnapshotPush(message);
      case SyncMessageTypes.snapshotRequest:
        _sendSnapshotIfAny();
      case SyncMessageTypes.actionPush:
        _handleActionPush(message);
      case SyncMessageTypes.actionAck:
        _handleActionAck(message);
      case SyncMessageTypes.devicesRequest:
        _sendDevices();
      case SyncMessageTypes.deviceUpdate:
        _handleDeviceUpdate(message);
      case SyncMessageTypes.deviceRemove:
        _handleDeviceRemove(message);
      case SyncMessageTypes.callInvite:
      case SyncMessageTypes.callAnswer:
      case SyncMessageTypes.callReject:
      case SyncMessageTypes.callEnd:
      case SyncMessageTypes.iceCandidate:
        _relayToTarget(message); // 二期信令：原样透传给 targetDeviceId
      default:
        _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'unsupported'}));
    }
  }

  void _handlePairCreate(SyncMessage message) {
    final ticket = app.pairing.createCode(
      existingHouseholdId: message.payload['householdId'] as String?,
      ownerDeviceId: message.payload['deviceId'] as String,
      ownerDeviceName: message.payload['deviceName'] as String? ?? '主人设备',
    );
    // 创建配对码的连接立即按 owner 入会，便于接收 pair_peer_joined。
    householdId = ticket.householdId;
    deviceId = message.payload['deviceId'] as String;
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.pairCreated, {
      'code': ticket.code,
      'saltBase64': ticket.saltBase64,
      'expiresAtMs': ticket.expiresAt.millisecondsSinceEpoch,
      'householdId': ticket.householdId,
    }));
    unawaited(app.store.flush());
  }

  void _handlePairJoin(SyncMessage message) {
    final result = app.pairing.redeem(
      code: message.payload['code'] as String? ?? '',
      petDeviceId: message.payload['deviceId'] as String,
      petDeviceName: message.payload['deviceName'] as String? ?? '宠物端设备',
    );
    if (result == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': '配对码无效或已过期'}));
      return;
    }
    householdId = result.householdId;
    deviceId = message.payload['deviceId'] as String;
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.pairJoined, {
      'householdId': result.householdId,
      'saltBase64': result.saltBase64,
    }));
    for (final owner in _household!.devices.values.where((d) => d.role == 'owner')) {
      app.hub.sendTo(householdId!, owner.deviceId,
          SyncMessage(SyncMessageTypes.pairPeerJoined, {
        'deviceId': deviceId,
        'deviceName': message.payload['deviceName'],
      }).encode());
    }
    unawaited(app.store.flush());
  }

  Household? get _household => app.store.household(householdId);

  void _handleSnapshotPush(SyncMessage message) {
    final household = _household;
    if (household == null) return;
    household
      ..snapshotVersion = message.payload['version'] as int
      ..snapshotCiphertext = message.payload['ciphertext'] as String;
    for (final device in household.devices.values.where((d) => d.role == 'pet')) {
      app.hub.sendTo(householdId!, device.deviceId,
          SyncMessage(SyncMessageTypes.snapshot, message.payload).encode());
    }
    unawaited(app.store.flush());
  }

  void _sendSnapshotIfAny() {
    final household = _household;
    if (household?.snapshotCiphertext == null) return;
    _send(SyncMessage(SyncMessageTypes.snapshot, {
      'version': household!.snapshotVersion,
      'ciphertext': household.snapshotCiphertext,
    }));
  }

  void _handleActionPush(SyncMessage message) {
    final household = _household;
    if (household == null) return;
    final entry = {
      'actionId': message.payload['actionId'],
      'ciphertext': message.payload['ciphertext'],
    };
    household.pendingActions.add(entry);
    for (final device in household.devices.values.where((d) => d.role == 'owner')) {
      if (app.hub.isOnline(householdId!, device.deviceId)) {
        app.hub.sendTo(householdId!, device.deviceId,
            SyncMessage(SyncMessageTypes.action, entry).encode());
      }
    }
    unawaited(app.store.flush());
  }

  void _handleActionAck(SyncMessage message) {
    _household?.pendingActions
        .removeWhere((a) => a['actionId'] == message.payload['actionId']);
    unawaited(app.store.flush());
  }

  void _sendDevices() {
    final household = _household;
    if (household == null) return;
    _send(SyncMessage(SyncMessageTypes.devices, {
      'devices': household.devices.values
          .map((d) => SyncedDeviceInfo(
                deviceId: d.deviceId,
                name: d.name,
                role: d.role,
                servedPetId: d.servedPetId,
                online: app.hub.isOnline(householdId!, d.deviceId),
                lastSeenMs: d.lastSeenMs,
              ).toJson())
          .toList(),
    }));
  }

  void _handleDeviceUpdate(SyncMessage message) {
    final device = _household?.devices[message.payload['deviceId']];
    if (device == null) return;
    if (message.payload['name'] is String) device.name = message.payload['name'] as String;
    if (message.payload.containsKey('servedPetId')) {
      device.servedPetId = message.payload['servedPetId'] as String?;
      app.hub.sendTo(householdId!, device.deviceId,
          SyncMessage(SyncMessageTypes.deviceConfig,
              {'servedPetId': device.servedPetId}).encode());
    }
    unawaited(app.store.flush());
    _sendDevices();
  }

  void _handleDeviceRemove(SyncMessage message) {
    final removedId = message.payload['deviceId'] as String;
    _household?.devices.remove(removedId);
    app.hub.sendTo(householdId!, removedId,
        SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}).encode());
    unawaited(app.store.flush());
    _sendDevices();
  }

  void _relayToTarget(SyncMessage message) {
    final target = message.payload['targetDeviceId'] as String?;
    if (householdId == null || target == null) return;
    app.hub.sendTo(householdId!, target, message.encode());
  }
```

并修改 `_handleHello`：注册成功后，若是 owner 且 `pendingActions` 非空，逐条补发 `action` 消息；同时更新 `device.lastSeenMs = DateTime.now().millisecondsSinceEpoch`。文件顶部补 `import 'dart:async';` 与 `import 'household_store.dart';`。

- [ ] **Step 4: `dart test` 全包通过**

- [ ] **Step 5: 提交**

```bash
git add server
git commit -m "feat(server): full session state machine for sync, actions and devices"
```

### Task 6: 部署物（Dockerfile / Compose / README）

**Files:**
- Create: `server/Dockerfile`
- Create: `server/docker-compose.yml`
- Create: `server/README.md`
- Test: `test/sync_server_deploy_structure_test.dart`（App 仓库根的结构测试，沿用项目 `*_structure_test.dart` 先例）

- [ ] **Step 1: 写结构测试**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('服务器部署物存在且包含关键配置', () {
    final dockerfile = File('server/Dockerfile').readAsStringSync();
    expect(dockerfile, contains('dart compile exe'));
    final compose = File('server/docker-compose.yml').readAsStringSync();
    expect(compose, contains('petnote-sync'));
    expect(compose, contains('coturn')); // 二期预留
    expect(File('server/README.md').existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: `flutter test test/sync_server_deploy_structure_test.dart` 确认失败**

- [ ] **Step 3: 编写部署物**

`server/Dockerfile`：

```dockerfile
FROM dart:3.6 AS build
WORKDIR /workspace
COPY packages/petnote_sync_protocol /workspace/packages/petnote_sync_protocol
COPY server /workspace/server
WORKDIR /workspace/server
RUN dart pub get && dart compile exe bin/petnote_sync_server.dart -o /petnote_sync_server

FROM debian:bookworm-slim
COPY --from=build /petnote_sync_server /usr/local/bin/petnote_sync_server
ENV PORT=8787 DATA_DIR=/data
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/petnote_sync_server"]
```

`server/docker-compose.yml`：

```yaml
services:
  petnote-sync:
    build:
      context: ..
      dockerfile: server/Dockerfile
    restart: unless-stopped
    ports:
      - "8787:8787"
    volumes:
      - petnote-data:/data

  # 二期启用：WebRTC TURN 兜底（先保留注释，凭证下发接口二期实现）
  # coturn:
  #   image: coturn/coturn:4.6
  #   restart: unless-stopped
  #   network_mode: host
  #   command: ["-n", "--use-auth-secret", "--static-auth-secret=${TURN_SECRET}", "--realm=petnote"]

volumes:
  petnote-data:
```

`server/README.md`：写部署步骤（构建注意 context 是仓库根 `..`，因为需要 `packages/`）、反代 TLS 示例（Caddy 两行配置：`your.domain { reverse_proxy localhost:8787 }`）、App 内服务器地址填 `wss://your.domain/ws`、数据目录备份说明。

- [ ] **Step 4: 测试通过；本机有 Docker 则 `docker compose -f server/docker-compose.yml build` 验证（无 Docker 跳过并在交付说明注明）**

- [ ] **Step 5: 提交**

```bash
git add server test/sync_server_deploy_structure_test.dart
git commit -m "feat(server): docker deployment with coturn placeholder"
```

---

## Part B：App 状态层

### Task 7: AppSettingsController 增加角色与同步配置

**Files:**
- Modify: `lib/state/app_settings_controller.dart`
- Test: `test/app_settings_device_role_test.dart`

- [ ] **Step 1: 写失败测试**（仿照现有 `test/app_settings_controller_test.dart` 的构造方式）

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('设备角色默认 undecided，可设置并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppSettingsController.load();
    expect(controller.deviceRole, DeviceRole.undecided);
    await controller.setDeviceRole(DeviceRole.pet);
    expect(controller.deviceRole, DeviceRole.pet);

    final reloaded = await AppSettingsController.load();
    expect(reloaded.deviceRole, DeviceRole.pet);
  });

  test('deviceId 首次访问自动生成且稳定', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppSettingsController.load();
    final id = await controller.ensureDeviceId();
    expect(id, isNotEmpty);
    expect(await controller.ensureDeviceId(), id);
  });

  test('同步配对配置可保存与清除', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppSettingsController.load();
    await controller.saveSyncPairing(
      serverUrl: 'wss://example.com/ws',
      householdId: 'h1',
      servedPetId: 'p1',
      deviceName: '客厅平板',
    );
    expect(controller.syncServerUrl, 'wss://example.com/ws');
    expect(controller.syncHouseholdId, 'h1');
    expect(controller.servedPetId, 'p1');
    await controller.clearSyncPairing();
    expect(controller.syncHouseholdId, isNull);
  });
}
```

- [ ] **Step 2: `flutter test test/app_settings_device_role_test.dart` 确认失败**

- [ ] **Step 3: 实现**——在 `app_settings_controller.dart` 中：

```dart
enum DeviceRole { undecided, owner, pet }
```

新增存储 key 常量与字段（沿用既有 `*_v1` 命名、私有字段 + getter + setter 持久化 + `notifyListeners()` 的模式）：

```dart
  static const String deviceRoleStorageKey = 'device_role_v1';
  static const String deviceIdStorageKey = 'device_id_v1';
  static const String deviceNameStorageKey = 'device_name_v1';
  static const String syncServerUrlStorageKey = 'sync_server_url_v1';
  static const String syncHouseholdIdStorageKey = 'sync_household_id_v1';
  static const String servedPetIdStorageKey = 'served_pet_id_v1';
```

API（实现都是「赋值 → `_preferences?.setString/remove` → `notifyListeners()`」，与 `setThemePreference` 同构）：

```dart
  DeviceRole get deviceRole;
  Future<void> setDeviceRole(DeviceRole value);

  String? get deviceName;
  Future<void> setDeviceName(String value);

  /// 首次调用生成并持久化随机 deviceId（时间戳36进制 + Random.secure 后缀）。
  Future<String> ensureDeviceId();

  String? get syncServerUrl;
  String? get syncHouseholdId;
  String? get servedPetId;
  Future<void> saveSyncPairing({
    required String serverUrl,
    required String householdId,
    String? servedPetId,
    String? deviceName,
  });
  Future<void> setServedPetId(String? value);
  Future<void> clearSyncPairing(); // 清 householdId/servedPetId（保留 serverUrl 方便重配）
```

`load()` 中读取以上 key 并传入构造（仿 `themePreference` 的处理；`DeviceRole` 解析用 `_deviceRoleFromName` switch，默认 `undecided`）。

- [ ] **Step 4: 测试通过；同时定向跑 `flutter test test/app_settings_controller_test.dart` 确认无回归**

- [ ] **Step 5: 提交**

```bash
git add lib/state/app_settings_controller.dart test/app_settings_device_role_test.dart
git commit -m "feat(app): device role and sync pairing settings"
```

### Task 8: 同步密钥存储 SyncSecretStore

**Files:**
- Create: `lib/sync/sync_secret_store.dart`
- Test: `test/sync_secret_store_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('安全存储可用时读写走 AiSecretStore 通道', () async {
    final secrets = InMemoryAiSecretStore();
    final store = SyncSecretStore(secretStore: secrets);
    await store.writeHouseholdKey('key-base64');
    expect(await store.readHouseholdKey(), 'key-base64');
    await store.deleteHouseholdKey();
    expect(await store.readHouseholdKey(), isNull);
  });

  test('安全存储不可用时回落 shared_preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncSecretStore(secretStore: _UnavailableSecretStore());
    await store.writeHouseholdKey('fallback-key');
    expect(await store.readHouseholdKey(), 'fallback-key');
  });
}

class _UnavailableSecretStore extends InMemoryAiSecretStore {
  @override
  Future<bool> isAvailable() async => false;
}
```

- [ ] **Step 2: 确认失败后实现**

```dart
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步共享密钥存储：优先复用 AI 密钥的原生安全存储通道
/// （configId 复用其 key-value 语义），不可用时回落 shared_preferences。
class SyncSecretStore {
  SyncSecretStore({AiSecretStore? secretStore})
      : _secretStore = secretStore ?? MethodChannelAiSecretStore();

  static const String _configId = 'sync.household_key_v1';
  static const String _fallbackPrefsKey = 'sync_household_key_fallback_v1';

  final AiSecretStore _secretStore;

  Future<String?> readHouseholdKey() async {
    if (await _secretStore.isAvailable()) {
      return _secretStore.readKey(_configId);
    }
    return (await SharedPreferences.getInstance()).getString(_fallbackPrefsKey);
  }

  Future<void> writeHouseholdKey(String keyBase64) async {
    if (await _secretStore.isAvailable()) {
      await _secretStore.writeKey(_configId, keyBase64);
      return;
    }
    await (await SharedPreferences.getInstance())
        .setString(_fallbackPrefsKey, keyBase64);
  }

  Future<void> deleteHouseholdKey() async {
    if (await _secretStore.isAvailable()) {
      await _secretStore.deleteKey(_configId);
    }
    await (await SharedPreferences.getInstance()).remove(_fallbackPrefsKey);
  }
}
```

- [ ] **Step 3: `flutter test test/sync_secret_store_test.dart` 通过后提交**

```bash
git add lib/sync/sync_secret_store.dart test/sync_secret_store_test.dart
git commit -m "feat(sync): household key storage reusing secure channel"
```

### Task 9: 协议包接入 App 与 SyncClient

**Files:**
- Modify: `pubspec.yaml`（App）
- Create: `lib/sync/sync_client.dart`
- Test: `test/sync_client_test.dart`

- [ ] **Step 1: App pubspec 添加依赖**

```yaml
dependencies:
  petnote_sync_protocol:
    path: packages/petnote_sync_protocol
```

运行 `PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get`。

- [ ] **Step 2: 写失败测试**（用 `dart:io` 起本地 WS 服务模拟服务器，flutter_test 可跑）

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('连接后可收发消息，断开后自动重连', () async {
    final connections = <WebSocket>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connections.add(socket);
      socket.listen((raw) {
        final message = SyncMessage.decode(raw as String);
        if (message.type == SyncMessageTypes.hello) {
          socket.add(SyncMessage(SyncMessageTypes.helloAck, {'snapshotVersion': 0}).encode());
        }
      });
    });

    final client = SyncClient(
      url: 'ws://127.0.0.1:${server.port}/ws',
      reconnectBaseDelay: const Duration(milliseconds: 50),
    );
    final received = <SyncMessage>[];
    client.messages.listen(received.add);
    await client.connect();
    client.send(SyncMessage(SyncMessageTypes.hello,
        {'householdId': 'h', 'deviceId': 'd', 'role': 'pet', 'deviceName': 'n'}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(received.map((m) => m.type), contains(SyncMessageTypes.helloAck));
    expect(client.state.value, SyncConnectionState.connected);

    await connections.first.close(); // 服务器踢断 → 客户端应自动重连
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(connections.length, greaterThan(1));

    await client.dispose();
    await server.close(force: true);
  });
}
```

- [ ] **Step 3: 确认失败后实现 `sync_client.dart`**

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum SyncConnectionState { disconnected, connecting, connected }

/// WebSocket 客户端：心跳 30s、指数退避自动重连（base*2^n，封顶 60s）。
class SyncClient {
  SyncClient({
    required this.url,
    this.reconnectBaseDelay = const Duration(seconds: 1),
  });

  final String url;
  final Duration reconnectBaseDelay;

  final ValueNotifier<SyncConnectionState> state =
      ValueNotifier(SyncConnectionState.disconnected);
  final StreamController<SyncMessage> _messages = StreamController.broadcast();
  Stream<SyncMessage> get messages => _messages.stream;

  WebSocket? _socket;
  bool _disposed = false;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  final List<String> _outbox = [];

  Future<void> connect() async {
    if (_disposed || state.value != SyncConnectionState.disconnected) return;
    state.value = SyncConnectionState.connecting;
    try {
      final socket = await WebSocket.connect(url);
      socket.pingInterval = const Duration(seconds: 30);
      _socket = socket;
      _retryCount = 0;
      state.value = SyncConnectionState.connected;
      for (final pending in _outbox) {
        socket.add(pending);
      }
      _outbox.clear();
      socket.listen(
        (raw) {
          try {
            _messages.add(SyncMessage.decode(raw as String));
          } on FormatException {
            // 忽略坏消息，保持连接。
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void send(SyncMessage message) {
    final encoded = message.encode();
    final socket = _socket;
    if (state.value == SyncConnectionState.connected && socket != null) {
      socket.add(encoded);
    } else {
      _outbox.add(encoded);
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _socket = null;
    state.value = SyncConnectionState.disconnected;
    final delay = reconnectBaseDelay * pow(2, min(_retryCount, 6)).toInt();
    _retryCount += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _socket?.close();
    await _messages.close();
    state.dispose();
  }
}
```

- [ ] **Step 4: `flutter test test/sync_client_test.dart` 通过后提交**

```bash
git add pubspec.yaml lib/sync/sync_client.dart test/sync_client_test.dart
git commit -m "feat(sync): reconnecting websocket sync client"
```

### Task 10: OwnerSyncEngine（主人端引擎）

**Files:**
- Create: `lib/sync/owner_sync_engine.dart`
- Test: `test/owner_sync_engine_test.dart`

- [ ] **Step 1: 写失败测试**（核心断言：store 变更触发加密快照推送；收到 action 调 `markChecklistDone`；devices 消息更新设备列表）

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class FakeSyncTransport implements SyncTransport {
  final List<SyncMessage> sent = [];
  final StreamController<SyncMessage> incoming = StreamController.broadcast();

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  void send(SyncMessage message) => sent.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('数据变更 → 节流后推送加密快照，版本递增', () async {
    final store = await PetNoteStore.loadWithSampleData(); // 与现有 store 测试同构的内存加载方式
    final transport = FakeSyncTransport();
    final crypto = SyncCrypto.fromKeyBase64(await (await SyncCrypto.deriveFromPairingCode(
            code: '123456', saltBase64: SyncCrypto.generateSaltBase64()))
        .exportKeyBase64());
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: crypto,
      throttle: const Duration(milliseconds: 50),
    )..start();

    await store.addTodo(
      petId: store.pets.first.id,
      title: '喂饭',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final pushes =
        transport.sent.where((m) => m.type == SyncMessageTypes.snapshotPush).toList();
    expect(pushes, isNotEmpty);
    final decrypted = await crypto.decryptString(pushes.last.payload['ciphertext'] as String);
    expect(decrypted, contains('喂饭'));

    engine.dispose();
  });

  test('收到 action 消息应用到 store 并 ack', () async {
    final store = await PetNoteStore.loadWithSampleData();
    final transport = FakeSyncTransport();
    final salt = SyncCrypto.generateSaltBase64();
    final crypto = await SyncCrypto.deriveFromPairingCode(code: '111111', saltBase64: salt);
    final engine = OwnerSyncEngine(
        store: store, transport: transport, crypto: crypto,
        throttle: const Duration(milliseconds: 50))
      ..start();

    final todo = store.todos.firstWhere((t) => t.status == TodoStatus.open);
    final action = PetAction(
        kind: PetActionKind.markDone, sourceType: 'todo', itemId: todo.id);
    transport.incoming.add(SyncMessage(SyncMessageTypes.action, {
      'actionId': 'a1',
      'ciphertext': await crypto.encryptString(
          const JsonEncoder().convert(action.toJson())),
    }));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(store.todos.firstWhere((t) => t.id == todo.id).status, TodoStatus.done);
    expect(transport.sent.any((m) => m.type == SyncMessageTypes.actionAck), isTrue);

    engine.dispose();
  });
}
```

注：`PetNoteStore.loadWithSampleData()` 若实际名称不同，以 `test/pet_care_store_test.dart` 中现成的 store 构造辅助为准（执行时先读该文件，复用同样的构造方法；`addTodo` 具名参数以 `lib/state/petnote_store.dart:1456` 实际签名为准）。测试文件顶部需 `import 'dart:convert';`。

- [ ] **Step 2: 确认失败后实现 `owner_sync_engine.dart`**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

/// 传输抽象：生产为 SyncClient，测试为 fake。SyncClient 已满足此接口，
/// 在 sync_client.dart 上声明 `class SyncClient implements SyncTransport`。
abstract class SyncTransport {
  Stream<SyncMessage> get messages;
  void send(SyncMessage message);
}

/// 主人端同步引擎：store 变更 → 节流 → 整体快照加密推送；
/// 处理宠物端 action 与设备目录消息。
class OwnerSyncEngine {
  OwnerSyncEngine({
    required this.store,
    required this.transport,
    required this.crypto,
    this.throttle = const Duration(seconds: 2),
  });

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;
  final Duration throttle;

  final ValueNotifier<List<SyncedDeviceInfo>> devices = ValueNotifier(const []);

  Timer? _pushTimer;
  String? _lastPushedJson;
  int _version = 0;
  StreamSubscription<SyncMessage>? _subscription;

  void start() {
    store.addListener(_onStoreChanged);
    _subscription = transport.messages.listen(_onMessage);
    _onStoreChanged(); // 启动即推一版，覆盖离线期间的变更
  }

  void _onStoreChanged() {
    _pushTimer?.cancel();
    _pushTimer = Timer(throttle, _pushSnapshot);
  }

  Future<void> _pushSnapshot() async {
    final state = PetNoteDataState(
      pets: store.pets,
      todos: store.todos,
      reminders: store.reminders,
      records: store.records,
    );
    final json = jsonEncode(state.toJson());
    if (json == _lastPushedJson) return;
    _lastPushedJson = json;
    _version += 1;
    transport.send(SyncMessage(SyncMessageTypes.snapshotPush, {
      'version': _version,
      'ciphertext': await crypto.encryptString(json),
    }));
  }

  Future<void> _onMessage(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageTypes.action:
        await _applyAction(message);
      case SyncMessageTypes.devices:
        devices.value = (message.payload['devices'] as List)
            .map((d) => SyncedDeviceInfo.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList(growable: false);
      default:
        break;
    }
  }

  Future<void> _applyAction(SyncMessage message) async {
    try {
      final json = jsonDecode(
          await crypto.decryptString(message.payload['ciphertext'] as String));
      final action = PetAction.fromJson(Map<String, dynamic>.from(json as Map));
      switch (action.kind) {
        case PetActionKind.markDone:
          await store.markChecklistDone(action.sourceType, action.itemId);
        case PetActionKind.postpone:
          await store.postponeChecklist(action.sourceType, action.itemId);
        case PetActionKind.skip:
          await store.skipChecklist(action.sourceType, action.itemId);
      }
      transport.send(SyncMessage(SyncMessageTypes.actionAck,
          {'actionId': message.payload['actionId']}));
    } catch (_) {
      // 解密/解析失败的 action 直接丢弃并 ack，避免服务器队列卡死。
      transport.send(SyncMessage(SyncMessageTypes.actionAck,
          {'actionId': message.payload['actionId']}));
    }
  }

  void requestDevices() =>
      transport.send(SyncMessage(SyncMessageTypes.devicesRequest, {}));

  void renameDevice(String deviceId, String name) => transport
      .send(SyncMessage(SyncMessageTypes.deviceUpdate, {'deviceId': deviceId, 'name': name}));

  void assignPet(String deviceId, String? petId) => transport.send(SyncMessage(
      SyncMessageTypes.deviceUpdate, {'deviceId': deviceId, 'servedPetId': petId}));

  void removeDevice(String deviceId) => transport
      .send(SyncMessage(SyncMessageTypes.deviceRemove, {'deviceId': deviceId}));

  void dispose() {
    _pushTimer?.cancel();
    _subscription?.cancel();
    store.removeListener(_onStoreChanged);
    devices.dispose();
  }
}
```

同时在 `sync_client.dart` 的类声明改为 `class SyncClient implements SyncTransport`（import 引擎文件或将 `SyncTransport` 移到独立文件 `lib/sync/sync_transport.dart` 避免循环依赖——采用后者）。

- [ ] **Step 3: `flutter test test/owner_sync_engine_test.dart` 通过后提交**

```bash
git add lib/sync test/owner_sync_engine_test.dart
git commit -m "feat(sync): owner sync engine with snapshot push and action apply"
```

### Task 11: PetReplicaController（宠物端副本）

**Files:**
- Create: `lib/sync/pet_replica_controller.dart`
- Test: `test/pet_replica_controller_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

// FakeSyncTransport 与 owner_sync_engine_test 相同（复制定义，测试间不共享 helper）。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('收到快照解密后写入本地 store', () async {
    final store = await PetNoteStore.loadWithSampleData();
    final replicaStore = await PetNoteStore.loadEmpty(); // 以 store 测试的内存空库构造为准
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
        code: '123456', saltBase64: SyncCrypto.generateSaltBase64());
    final controller = PetReplicaController(
        store: replicaStore, transport: transport, crypto: crypto)
      ..start();

    final state = PetNoteDataState(
        pets: store.pets, todos: store.todos,
        reminders: store.reminders, records: store.records);
    transport.incoming.add(SyncMessage(SyncMessageTypes.snapshot, {
      'version': 1,
      'ciphertext': await crypto.encryptString(jsonEncode(state.toJson())),
    }));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(replicaStore.pets.length, store.pets.length);
    expect(controller.lastSyncedVersion.value, 1);

    controller.dispose();
  });

  test('sendAction 加密上行并标记 pending', () async {
    final replicaStore = await PetNoteStore.loadEmpty();
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
        code: '123456', saltBase64: SyncCrypto.generateSaltBase64());
    final controller = PetReplicaController(
        store: replicaStore, transport: transport, crypto: crypto)
      ..start();

    await controller.sendAction(const PetAction(
        kind: PetActionKind.markDone, sourceType: 'todo', itemId: 't1'));
    expect(transport.sent.single.type, SyncMessageTypes.actionPush);
    expect(controller.pendingItemKeys.value, contains('todo:t1'));

    controller.dispose();
  });
}
```

- [ ] **Step 2: 确认失败后实现**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

/// 宠物端副本控制器：快照解密落库 + action 上行（乐观 pending 标记）。
class PetReplicaController {
  PetReplicaController({
    required this.store,
    required this.transport,
    required this.crypto,
  });

  final PetNoteStore store;
  final SyncTransport transport;
  final SyncCrypto crypto;

  final ValueNotifier<int> lastSyncedVersion = ValueNotifier(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier(null);
  final ValueNotifier<Set<String>> pendingItemKeys = ValueNotifier(const {});
  final ValueNotifier<String?> servedPetIdOverride = ValueNotifier(null);
  final ValueNotifier<bool> removedByOwner = ValueNotifier(false);

  StreamSubscription<SyncMessage>? _subscription;
  final Random _random = Random.secure();

  void start() {
    _subscription = transport.messages.listen(_onMessage);
    transport.send(SyncMessage(SyncMessageTypes.snapshotRequest, {}));
  }

  Future<void> _onMessage(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageTypes.snapshot:
        await _applySnapshot(message);
      case SyncMessageTypes.deviceConfig:
        if (message.payload['removed'] == true) {
          removedByOwner.value = true;
        } else if (message.payload.containsKey('servedPetId')) {
          servedPetIdOverride.value = message.payload['servedPetId'] as String?;
        }
      default:
        break;
    }
  }

  Future<void> _applySnapshot(SyncMessage message) async {
    try {
      final json = jsonDecode(
          await crypto.decryptString(message.payload['ciphertext'] as String));
      final state = PetNoteDataState.fromJson(Map<String, dynamic>.from(json as Map));
      await store.replaceAllData(state);
      lastSyncedVersion.value = message.payload['version'] as int? ?? 0;
      lastSyncedAt.value = DateTime.now();
      pendingItemKeys.value = const {}; // 新快照即权威结果，清掉乐观标记
    } catch (_) {
      // 密钥不匹配或数据损坏：保持旧副本，等待下一版快照。
    }
  }

  Future<void> sendAction(PetAction action) async {
    final actionId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';
    transport.send(SyncMessage(SyncMessageTypes.actionPush, {
      'actionId': actionId,
      'ciphertext': await crypto.encryptString(jsonEncode(action.toJson())),
    }));
    pendingItemKeys.value = {
      ...pendingItemKeys.value,
      '${action.sourceType}:${action.itemId}',
    };
  }

  void dispose() {
    _subscription?.cancel();
    lastSyncedVersion.dispose();
    lastSyncedAt.dispose();
    pendingItemKeys.dispose();
    servedPetIdOverride.dispose();
    removedByOwner.dispose();
  }
}
```

- [ ] **Step 3: `flutter test test/pet_replica_controller_test.dart` 通过后提交**

```bash
git add lib/sync/pet_replica_controller.dart test/pet_replica_controller_test.dart
git commit -m "feat(sync): pet-side replica controller with optimistic actions"
```

### Task 12: SyncService（生命周期 facade）

**Files:**
- Create: `lib/sync/sync_service.dart`
- Test: `test/sync_service_test.dart`

- [ ] **Step 1: 写失败测试**（断言：根据 settings 配置创建/复用/销毁 engine；未配对时不创建连接）

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未配对时 ensureStarted 不建立连接', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsController.load();
    final service = SyncService(settings: settings, secretStore: null);
    await service.ensureStartedForOwner(store: null);
    expect(service.isActive, isFalse);
  });
}
```

- [ ] **Step 2: 实现**——单例风格 facade（构造注入便于测试，生产经 `SyncService.instance` 配置）：

```dart
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

/// 同步生命周期管理：根据 settings 中的配对状态启停 client/engine。
/// 主人端在 PetNoteRoot 挂载时调用 ensureStartedForOwner；
/// 宠物端在 PetDeviceHome 挂载时调用 ensureStartedForPet。
class SyncService {
  SyncService({required this.settings, SyncSecretStore? secretStore})
      : _secretStore = secretStore ?? SyncSecretStore();

  static SyncService? instance;

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;

  SyncClient? _client;
  OwnerSyncEngine? ownerEngine;
  PetReplicaController? petController;

  bool get isActive => _client != null;

  Future<void> ensureStartedForOwner({required PetNoteStore? store}) async {
    if (store == null || isActive) return;
    final url = settings.syncServerUrl;
    final householdId = settings.syncHouseholdId;
    final keyBase64 = await _secretStore.readHouseholdKey();
    if (url == null || householdId == null || keyBase64 == null) return;
    final client = SyncClient(url: url);
    _client = client;
    ownerEngine = OwnerSyncEngine(
      store: store,
      transport: client,
      crypto: SyncCrypto.fromKeyBase64(keyBase64),
    )..start();
    await client.connect();
    client.send(SyncMessage(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': await settings.ensureDeviceId(),
      'role': 'owner',
      'deviceName': settings.deviceName ?? '主人设备',
    }));
  }

  Future<void> ensureStartedForPet({required PetNoteStore store}) async {
    if (isActive) return;
    final url = settings.syncServerUrl;
    final householdId = settings.syncHouseholdId;
    final keyBase64 = await _secretStore.readHouseholdKey();
    if (url == null || householdId == null || keyBase64 == null) return;
    final client = SyncClient(url: url);
    _client = client;
    petController = PetReplicaController(
      store: store,
      transport: client,
      crypto: SyncCrypto.fromKeyBase64(keyBase64),
    )..start();
    await client.connect();
    client.send(SyncMessage(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': await settings.ensureDeviceId(),
      'role': 'pet',
      'deviceName': settings.deviceName ?? '宠物端设备',
    }));
  }

  Future<void> stop() async {
    ownerEngine?.dispose();
    petController?.dispose();
    ownerEngine = null;
    petController = null;
    await _client?.dispose();
    _client = null;
  }
}
```

注意测试里 `secretStore: null` 参数按实现改为可空注入或传 `SyncSecretStore(secretStore: InMemoryAiSecretStore())`，以实现为准修正测试。

- [ ] **Step 3: 测试通过后提交**

```bash
git add lib/sync/sync_service.dart test/sync_service_test.dart
git commit -m "feat(sync): sync service lifecycle facade"
```

---

## Part C：UI——首启角色选择与路由

### Task 13: Intro 第 4 页「这台设备为谁服务？」

**Files:**
- Modify: `lib/app/pet_first_launch_intro.dart`
- Test: `test/first_launch_role_page_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_first_launch_intro.dart';

void main() {
  Widget host({
    required Future<void> Function() onStartOnboarding,
    required Future<void> Function() onExploreFirst,
    required Future<void> Function() onSelectPetRole,
  }) {
    return MaterialApp(
      home: Stack(children: [
        PetFirstLaunchIntro(
          shouldStartLaunchAnimation: false,
          onStartOnboarding: onStartOnboarding,
          onExploreFirst: onExploreFirst,
          onSelectPetRole: onSelectPetRole,
        ),
      ]),
    );
  }

  testWidgets('第4页展示角色双卡片，选主人走 onboarding，选爱宠走配对', (tester) async {
    var startedOnboarding = false;
    var selectedPet = false;
    await tester.pumpWidget(host(
      onStartOnboarding: () async => startedOnboarding = true,
      onExploreFirst: () async {},
      onSelectPetRole: () async => selectedPet = true,
    ));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 翻到第 4 页
    final pageView = find.byKey(const ValueKey('first_launch_intro_page_view'));
    for (var i = 0; i < 3; i++) {
      await tester.drag(pageView, const Offset(-400, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('这台设备为谁服务？'), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_role_owner_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_role_pet_card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intro_role_owner_card')));
    await tester.pumpAndSettle();
    expect(startedOnboarding, isTrue);

    await tester.tap(find.byKey(const ValueKey('intro_role_pet_card')));
    await tester.pumpAndSettle();
    expect(selectedPet, isTrue);
  });
}
```

- [ ] **Step 2: `flutter test test/first_launch_role_page_test.dart` 确认失败**

- [ ] **Step 3: 实现**。修改点：

1. `PetFirstLaunchIntro` 构造新增 `required Future<void> Function() onSelectPetRole`；
2. `_pages` 增加第 4 个 `_IntroPageData(title: '这台设备为谁服务？', subtitle: '主人设备用来记录与管理；爱宠设备放在家里展示提醒。', icon: Icons.devices_rounded, accentColor: Color(0xFFF2A65A), heroAccentColor: Color(0xFFF2A65A), listStyle: _IntroListStyle.roleCards)`，`_IntroListStyle` 增加 `roleCards` 值；
3. `_IntroPage` 的 build 中 `roleCards` 分支渲染两张大卡片（复用 `_IntroFeatureCard` 的容器样式，外面包 `InkWell`）：

```dart
  List<Widget> _buildRoleCards() {
    return [
      _buildReveal(
        interval: const Interval(0.34, 0.62, curve: Curves.easeOutCubic),
        child: _IntroRoleCard(
          key: const ValueKey('intro_role_owner_card'),
          emoji: '👤',
          title: '主人',
          subtitle: '我用这台设备记录和管理毛孩子的照护。',
          onTap: widget.onSelectOwnerRole,
        ),
      ),
      _buildReveal(
        interval: const Interval(0.48, 0.76, curve: Curves.easeOutCubic),
        child: _IntroRoleCard(
          key: const ValueKey('intro_role_pet_card'),
          emoji: '🐾',
          title: '爱宠',
          subtitle: '这台设备放在家里，给毛孩子当电子标签牌。',
          onTap: widget.onSelectPetRole,
        ),
      ),
    ];
  }
```

`_IntroRoleCard` 为新 StatelessWidget：`Container`（`tokens.panelStrongBackground` 背景、24 圆角、`tokens.panelBorder` 边框）内 `Row`：48 号 emoji `Text` + 标题（`titleMedium` w800）/副标题（`bodyMedium`）列，整体套 `Material`+`InkWell`。回调链：`_IntroPage` 需要把 onTap 从外层传入——给 `_IntroPage` 构造加 `this.onSelectOwnerRole, this.onSelectPetRole`（`VoidCallback?`），由 `PetFirstLaunchIntro.build` 的 `List.generate` 处传入：owner 卡片回调 = `_handleStartOnboarding`（落盘动作在 petnote_root 的回调里做），pet 卡片回调 = `() => unawaited(_handleSelectPetRole())`，`_handleSelectPetRole` 仿照 `_handleStartOnboarding` 加 `_isPrimaryNavigating` 防重入并 `await widget.onSelectPetRole()`；
4. 页脚：第 4 页（`isFinalPage` 现为 `index == 3`）不再显示主按钮，只显示指示器与「先看看宠记」次按钮——`_buildStaticFooterChrome` 的 final 分支去掉 `_buildPrimaryButton(true)`，保留 secondary；原第 3 页主按钮文案逻辑 `isFinalPage ? '那我们开始吧' : '继续'` 改为恒 `'继续'`（onPressed 恒 `_handlePrimaryContinue`）；
5. 受影响的既有测试：`flutter test test/first_launch_intro_structure_test.dart test/widget_test.dart test/intro_haptics_test.dart` 定向跑出失败列表，按新交互（主按钮恒为「继续」、第 4 页无主按钮）更新断言。`widget_test.dart` 中 `_advanceIntroToFinalPage`/`_enterOnboardingFromIntro` 辅助会受页数影响，同步更新翻页次数与按钮 key。

- [ ] **Step 4: 定向跑上述测试文件全部通过**

- [ ] **Step 5: 提交**

```bash
git add lib/app/pet_first_launch_intro.dart test/
git commit -m "feat(intro): role selection page (owner vs pet device)"
```

### Task 14: 角色路由（App home 分支）

**Files:**
- Modify: `lib/app/petnote_app.dart`
- Modify: `lib/app/petnote_root.dart`
- Create: `lib/app/pet_device/pet_device_home.dart`
- Test: `test/device_role_routing_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/app/pet_device/pet_device_home.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('role==pet 时 home 为 PetDeviceHome', (tester) async {
    SharedPreferences.setMockInitialValues({'device_role_v1': 'pet'});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(PetNoteApp(
      settingsController: settings,
      storeLoader: PetNoteStore.loadEmpty, // 与现有测试相同的内存加载方式
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PetDeviceHome), findsOneWidget);
  });

  testWidgets('role==owner 时走现有壳层', (tester) async {
    SharedPreferences.setMockInitialValues({'device_role_v1': 'owner'});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(PetNoteApp(
      settingsController: settings,
      storeLoader: PetNoteStore.loadEmpty,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PetDeviceHome), findsNothing);
  });
}
```

- [ ] **Step 2: 确认失败后实现**

1. `pet_device_home.dart` 本任务先做骨架（配对页/看板在 Task 16/17 填充）：

```dart
import 'package:flutter/material.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

/// 宠物端根：未配对显示配对流程，已配对显示看板。
class PetDeviceHome extends StatelessWidget {
  const PetDeviceHome({
    super.key,
    required this.settingsController,
    this.storeLoader,
  });

  final AppSettingsController settingsController;
  final Future<PetNoteStore> Function()? storeLoader;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final paired = settingsController.syncHouseholdId != null;
        return paired
            ? const ColoredBox(color: Color(0xFF17181C)) // Task 17 替换为看板
            : const Scaffold(body: Center(child: Text('配对'))); // Task 16 替换
      },
    );
  }
}
```

2. `petnote_app.dart`：两处 `home:`（无 controller 分支不变；有 controller 分支）改为：

```dart
          home: settingsController.deviceRole == DeviceRole.pet
              ? PetDeviceHome(
                  settingsController: settingsController,
                  storeLoader: widget.storeLoader,
                )
              : PetNoteRoot(...现有参数不变...),
```

3. `petnote_root.dart`：把角色回调接进 intro——`_PetNoteBody` 新增 `onSelectPetRoleFromIntro` 透传给 `PetFirstLaunchIntro.onSelectPetRole`；`_PetNoteRootState` 实现：

```dart
  Future<void> _selectPetRoleFromIntro() async {
    await widget.settingsController?.setDeviceRole(DeviceRole.pet);
    await _store?.dismissFirstLaunchIntro();
    // role 变化触发 petnote_app 的 AnimatedBuilder 重建，home 切换为 PetDeviceHome。
  }
```

主人路径：`_openOnboardingFromIntro` 开头追加 `await widget.settingsController?.setDeviceRole(DeviceRole.owner);`；`_dismissFirstLaunchIntro`（先看看宠记）同样落盘 owner。老用户升级：`_loadStore` 完成后若 `store.pets.isNotEmpty && settingsController?.deviceRole == DeviceRole.undecided`，调 `setDeviceRole(DeviceRole.owner)`。

4. 主人端同步启动：`_loadStore` 末尾追加：

```dart
    final settingsController = widget.settingsController;
    if (settingsController != null &&
        settingsController.deviceRole != DeviceRole.pet) {
      SyncService.instance ??= SyncService(settings: settingsController);
      unawaited(SyncService.instance!.ensureStartedForOwner(store: store));
    }
```

- [ ] **Step 3: 定向跑 `test/device_role_routing_test.dart` + `test/petnote_app_structure_test.dart` + `test/main_startup_test.dart` 通过**

- [ ] **Step 4: 提交**

```bash
git add lib/app test/device_role_routing_test.dart
git commit -m "feat(app): route pet-role devices to PetDeviceHome"
```

---

## Part D：UI——宠物端

### Task 15: 配对页与选宠物页

**Files:**
- Create: `lib/app/pet_device/pet_pairing_page.dart`
- Create: `lib/sync/pairing_flow.dart`
- Test: `test/pet_pairing_page_test.dart`

- [ ] **Step 1: 写失败测试**（fake transport 注入；输入服务器地址+6位码 → 调 PairingFlow → 成功后回调宠物列表选择 → 落盘）

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_device/pet_pairing_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('配对页含服务器地址与配对码输入及提交按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(MaterialApp(
      home: PetPairingPage(settingsController: settings),
    ));
    expect(find.byKey(const ValueKey('pairing_server_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('pairing_code_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('pairing_submit_button')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 实现 `pairing_flow.dart`**（业务逻辑独立于 UI，便于单测）：

```dart
import 'dart:async';

import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
}

/// 宠物端配对：连服务器 → pair_join → 派生密钥 → 持久化配置。
class PairingFlow {
  PairingFlow({
    required this.settings,
    SyncSecretStore? secretStore,
    SyncClient Function(String url)? clientFactory,
  })  : _secretStore = secretStore ?? SyncSecretStore(),
        _clientFactory = clientFactory ?? ((url) => SyncClient(url: url));

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;
  final SyncClient Function(String url) _clientFactory;

  Future<void> joinAsPet({
    required String serverUrl,
    required String code,
    required String deviceName,
  }) async {
    final client = _clientFactory(serverUrl);
    try {
      await client.connect();
      final reply = client.messages
          .firstWhere((m) =>
              m.type == SyncMessageTypes.pairJoined ||
              m.type == SyncMessageTypes.pairError)
          .timeout(const Duration(seconds: 10));
      client.send(SyncMessage(SyncMessageTypes.pairJoin, {
        'code': code,
        'deviceId': await settings.ensureDeviceId(),
        'deviceName': deviceName,
      }));
      final message = await reply;
      if (message.type == SyncMessageTypes.pairError) {
        throw PairingException(message.payload['message'] as String? ?? '配对失败');
      }
      final crypto = await SyncCrypto.deriveFromPairingCode(
        code: code,
        saltBase64: message.payload['saltBase64'] as String,
      );
      await _secretStore.writeHouseholdKey(await crypto.exportKeyBase64());
      await settings.saveSyncPairing(
        serverUrl: serverUrl,
        householdId: message.payload['householdId'] as String,
        deviceName: deviceName,
      );
    } on TimeoutException {
      throw const PairingException('服务器无响应，请检查地址与网络');
    } finally {
      await client.dispose();
    }
  }
}
```

- [ ] **Step 3: 实现 `pet_pairing_page.dart`**——Scaffold + `HyperPageBackground`（复用 common_widgets）+ 表单：服务器地址 `TextField`（key `pairing_server_field`，初值 `settings.syncServerUrl`）、6 位码 `TextField`（key `pairing_code_field`，`keyboardType: TextInputType.number`，大号字距样式）、设备名 `TextField`（默认「客厅的小屏幕」）、提交 `FilledButton`（key `pairing_submit_button`）。提交时 setState loading → `PairingFlow.joinAsPet` → 失败 `SnackBar` 展示 `PairingException.message`；成功后 `settingsController` 已落盘，`PetDeviceHome` 的 `AnimatedBuilder` 自动切到看板（选宠物在看板首次渲染时引导，见 Task 17）。页面底部 `TextButton`「切回主人模式」→ `settings.setDeviceRole(DeviceRole.owner)`。

- [ ] **Step 4: `flutter test test/pet_pairing_page_test.dart` 通过后提交**

```bash
git add lib/app/pet_device lib/sync/pairing_flow.dart test/pet_pairing_page_test.dart
git commit -m "feat(pet-device): pairing page and pairing flow"
```

### Task 16: 主人端配对码生成（OwnerPairingFlow）

**Files:**
- Modify: `lib/sync/pairing_flow.dart`
- Test: `test/owner_pairing_flow_test.dart`

- [ ] **Step 1: 写失败测试**（fake clientFactory 注入：发出 pair_create 后收 pair_created；密钥派生并落盘；等待 pair_peer_joined 完成回调）

```dart
// 断言要点：
// 1) createAsOwner 返回 ticket（code/expiresAt），settings.syncHouseholdId 落盘；
// 2) household key 已写入 SyncSecretStore；
// 3) onPeerJoined 回调在收到 pair_peer_joined 时触发。
```

完整测试与 Task 15 的 fake 模式相同：自建 `dart:io` 本地 WS 服务回放服务器消息（参考 `test/sync_client_test.dart` 的写法），不 mock SyncClient。

- [ ] **Step 2: 在 `pairing_flow.dart` 增加 OwnerPairingFlow**

```dart
class OwnerPairingTicket {
  const OwnerPairingTicket({required this.code, required this.expiresAtMs});
  final String code;
  final int expiresAtMs;
}

class OwnerPairingFlow {
  OwnerPairingFlow({
    required this.settings,
    SyncSecretStore? secretStore,
    SyncClient Function(String url)? clientFactory,
  })  : _secretStore = secretStore ?? SyncSecretStore(),
        _clientFactory = clientFactory ?? ((url) => SyncClient(url: url));

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;
  final SyncClient Function(String url) _clientFactory;

  SyncClient? _client;

  /// 生成配对码。连接保持到 [dispose]，期间收到 pair_peer_joined 触发回调。
  Future<OwnerPairingTicket> createAsOwner({
    required String serverUrl,
    required void Function(String deviceId, String deviceName) onPeerJoined,
  }) async {
    final client = _clientFactory(serverUrl);
    _client = client;
    await client.connect();
    final created = client.messages
        .firstWhere((m) => m.type == SyncMessageTypes.pairCreated)
        .timeout(const Duration(seconds: 10));
    client.send(SyncMessage(SyncMessageTypes.pairCreate, {
      'householdId': settings.syncHouseholdId,
      'deviceId': await settings.ensureDeviceId(),
      'deviceName': settings.deviceName ?? '主人设备',
    }));
    final message = await created;
    final code = message.payload['code'] as String;
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: code,
      saltBase64: message.payload['saltBase64'] as String,
    );
    await _secretStore.writeHouseholdKey(await crypto.exportKeyBase64());
    await settings.saveSyncPairing(
      serverUrl: serverUrl,
      householdId: message.payload['householdId'] as String,
      servedPetId: settings.servedPetId,
      deviceName: settings.deviceName,
    );
    client.messages
        .where((m) => m.type == SyncMessageTypes.pairPeerJoined)
        .listen((m) => onPeerJoined(
            m.payload['deviceId'] as String,
            m.payload['deviceName'] as String? ?? '宠物端设备'));
    return OwnerPairingTicket(
      code: code,
      expiresAtMs: message.payload['expiresAtMs'] as int,
    );
  }

  Future<void> dispose() async {
    await _client?.dispose();
    _client = null;
  }
}
```

注意：重复配对（household 已存在）时 salt 不变，新派生密钥与旧密钥一致（HKDF 输入相同 code 才一致——不同 code 派生不同 key！）。**约束：同一 household 第二台设备配对必须沿用首次配对码派生的密钥，因此服务器在 household 已有密钥盐时，createCode 复用既有 salt，且 OwnerPairingFlow 在 `settings.syncHouseholdId != null` 时跳过 writeHouseholdKey（保留原密钥），新宠物端用新 code+旧 salt 派生会得到不同密钥——为避免这个矛盾，规则定为：**新增设备时主人端把现有 household key 直接编进配对流程：服务器 `pair_created`/`pair_joined` 不变，但宠物端派生密钥仅在 household 首台宠物端成立；后续设备配对时主人端先 `deviceRemove` 旧设备或使用「重置配对」。一期接受此限制（单宠物端为主场景），在 DevicesPage 文案注明「每个家庭组当前支持一台宠物端设备，新增前请先解绑旧设备」。测试中对应断言：household 已有 key 时 `createAsOwner` 抛 `PairingException('请先解绑现有宠物端设备')`——以服务器 `household.devices` 中含 role==pet 的设备为判断（服务器在 `pair_created` payload 加 `hasPetDevice: bool` 字段，Task 5 的 `_handlePairCreate` 同步补充）。

- [ ] **Step 3: 测试通过后提交**

```bash
git add lib/sync/pairing_flow.dart server/lib/src/session_handler.dart test/owner_pairing_flow_test.dart server/test
git commit -m "feat(sync): owner pairing flow with single-pet-device constraint"
```

### Task 17: 宠物端看板 PetDeviceDashboard

**Files:**
- Create: `lib/app/pet_device/pet_device_dashboard.dart`
- Modify: `lib/app/pet_device/pet_device_home.dart`
- Test: `test/pet_device_dashboard_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_device/pet_device_dashboard.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('看板渲染名牌/时钟/今日待办/提醒贴纸与设置按钮', (tester) async {
    final store = await PetNoteStore.loadWithSampleData();
    await tester.pumpWidget(MaterialApp(
      home: PetDeviceDashboard(
        store: store,
        servedPetId: store.pets.first.id,
        syncStatusLabel: '已连接',
        onOpenSettings: () {},
        onMarkDone: (sourceType, itemId) async {},
        pendingItemKeys: const {},
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('dashboard_pet_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard_clock_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard_todos_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard_reminders_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard_settings_button')), findsOneWidget);
    expect(find.text(store.pets.first.name), findsWidgets);
  });

  testWidgets('未选择服务宠物时显示选择列表', (tester) async {
    final store = await PetNoteStore.loadWithSampleData();
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: PetDeviceDashboard(
        store: store,
        servedPetId: null,
        syncStatusLabel: '已连接',
        onOpenSettings: () {},
        onMarkDone: (sourceType, itemId) async {},
        onSelectServedPet: (petId) => selected = petId,
        pendingItemKeys: const {},
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('dashboard_select_pet')), findsOneWidget);
    await tester.tap(find.text(store.pets.first.name).first);
    expect(selected, store.pets.first.id);
  });
}
```

- [ ] **Step 2: 实现看板**。设计要点（贴纸风格）：

- 深色全屏 `Scaffold`（背景 `Color(0xFF101216)`），`SafeArea` 内自定义两列布局（`CustomScrollView` + `SliverPadding` + 手写 `Column`/`Row`，不引入新依赖）；
- 贴纸卡片统一组件 `_StickerCard`：圆角 28、纯亮色块背景（米黄 `0xFFF6E7C8` / 奶白 `0xFFF4F1EA` / 橘 `0xFFF2A65A`）、微小随机旋转（±1.2°，`Transform.rotate`，按卡片索引取固定角度，模拟贴纸）、深色文字；
- 卡片构成：
  - `dashboard_pet_card`：`PetPhotoAvatar`（复用 pet_photo_widgets）+ 宠物名特大字（48, w900）+ 年龄标签；
  - `dashboard_clock_card`：`StreamBuilder`（每分钟 `Stream.periodic`）显示 HH:mm 特大字与日期/星期；
  - `dashboard_todos_card`：标题「今天要做」+ 按 `servedPetId` 过滤的 `store.todos`（`status == TodoStatus.open` 且 `dueAt` 在今天或已过期），每行大号复选圈（点按调 `onMarkDone('todo', id)`；`pendingItemKeys` 含 `todo:<id>` 时显示「已上报 ✓」灰态）；空态文案「今天没有待办，摸摸 ${pet.name} 吧」；
  - `dashboard_reminders_card`：标题「最近提醒」+ 过滤 `store.reminders`（`status == ReminderStatus.pending || status == ReminderStatus.overdue`，按 `scheduledAt` 升序取前 5），行内显示 `kind` emoji（疫苗💉/驱虫💊/洗护🛁/复查🩺/用药💊/自定义🔔）+ 标题 + 相对时间；
  - 顶栏：左侧小字同步状态（`syncStatusLabel` + 圆点：已连接绿/重连中黄）、右侧 `IconButton(Icons.settings_rounded)`（key `dashboard_settings_button`）调 `onOpenSettings`；
- `servedPetId == null` 时整屏显示 `dashboard_select_pet`：标题「这台设备为谁服务？」+ 宠物列表卡片（头像+名字），点按回调 `onSelectServedPet`。

构造签名：

```dart
class PetDeviceDashboard extends StatelessWidget {
  const PetDeviceDashboard({
    super.key,
    required this.store,
    required this.servedPetId,
    required this.syncStatusLabel,
    required this.onOpenSettings,
    required this.onMarkDone,
    required this.pendingItemKeys,
    this.onSelectServedPet,
  });

  final PetNoteStore store;
  final String? servedPetId;
  final String syncStatusLabel;
  final VoidCallback onOpenSettings;
  final Future<void> Function(String sourceType, String itemId) onMarkDone;
  final Set<String> pendingItemKeys;
  final ValueChanged<String>? onSelectServedPet;
}
```

- [ ] **Step 3: 接线 `pet_device_home.dart`**——改为 StatefulWidget：`initState` 里 `storeLoader ?? PetNoteStore.load` 加载本地副本 store，创建 `SyncService.instance ??= SyncService(settings: ...)` 并 `ensureStartedForPet(store: store)`；`AnimatedBuilder(animation: Listenable.merge([settingsController, store, petController?.lastSyncedAt, petController?.pendingItemKeys]))` 渲染：未配对→`PetPairingPage`；已配对→`PetDeviceDashboard`（`servedPetId` 取 `petController.servedPetIdOverride.value ?? settings.servedPetId`；`onSelectServedPet` → `settings.setServedPetId`；`onMarkDone` → `petController.sendAction(...)`；`syncStatusLabel` 由 `SyncClient.state` 映射：connected→'已连接'、connecting→'连接中'、disconnected→'重连中'）；`removedByOwner == true` 时调 `settings.clearSyncPairing()` 回到配对页。

- [ ] **Step 4: `flutter test test/pet_device_dashboard_test.dart` 通过后提交**

```bash
git add lib/app/pet_device test/pet_device_dashboard_test.dart
git commit -m "feat(pet-device): sticker-style dashboard with todos and reminders"
```

### Task 18: 宠物端设置页

**Files:**
- Create: `lib/app/pet_device/pet_device_settings_page.dart`
- Test: `test/pet_device_settings_page_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_device/pet_device_settings_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设置页含模式切换/重新配对/屏幕常亮项，切主人端落盘', (tester) async {
    SharedPreferences.setMockInitialValues({'device_role_v1': 'pet'});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(MaterialApp(
      home: PetDeviceSettingsPage(
        settingsController: settings,
        keepScreenOn: true,
        onKeepScreenOnChanged: (_) {},
        onRepair: () {},
      ),
    ));
    expect(find.byKey(const ValueKey('settings_mode_owner')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_repair')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_keep_screen_on')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_mode_owner')));
    await tester.pumpAndSettle();
    // 二次确认对话框
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();
    expect(settings.deviceRole, DeviceRole.owner);
  });
}
```

- [ ] **Step 2: 实现**——普通亮色 `Scaffold` + `SectionCard`（复用 common_widgets）：

- 「App 模式」卡片：两个 `RadioListTile` 风格行（宠物端/主人端，key `settings_mode_pet` / `settings_mode_owner`）；切到主人端时 `showDialog` 二次确认（「切换后此设备将进入完整管理界面」，确认按钮文案「确认切换」）→ `settings.setDeviceRole(DeviceRole.owner)` + `SyncService.instance?.stop()`；
- 「配对」卡片：当前服务器地址/家庭组状态展示 + 「重新配对」按钮（key `settings_repair`，二次确认后 `settings.clearSyncPairing()` + `SyncSecretStore().deleteHouseholdKey()` + 回调 `onRepair`）；
- 「屏幕常亮」`SwitchListTile`（key `settings_keep_screen_on`）→ 回调 `onKeepScreenOnChanged`（Task 19 接 method channel）；
- 看板 `onOpenSettings` → `Navigator.push` 本页。

- [ ] **Step 3: 测试通过后提交**

```bash
git add lib/app/pet_device/pet_device_settings_page.dart test/pet_device_settings_page_test.dart
git commit -m "feat(pet-device): settings page with mode switch and repair"
```

### Task 19: 保活 method channel 与三端原生实现

**Files:**
- Create: `lib/platform/device_keep_alive.dart`
- Modify: `ohos/entry/src/main/ets/`（新增 `KeepAlivePlugin` ets 文件并在入口注册，路径与注册方式参照仓内现有 intro_haptics / notification 插件的接线先例）
- Modify: `ohos/entry/src/main/module.json5`（权限与 backgroundModes）
- Modify: `android/app/src/main/.../MainActivity`（同包新增 `KeepAliveChannel` 与前台服务，manifest 注册）
- Modify: `ios/Runner/AppDelegate.swift`
- Test: `test/device_keep_alive_test.dart`、`test/keep_alive_structure_test.dart`

- [ ] **Step 1: 写 Dart 侧失败测试**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/platform/device_keep_alive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setKeepScreenOn 调用通道并容忍 MissingPlugin', () async {
    final calls = <MethodCall>[];
    final keepAlive = DeviceKeepAlive();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceKeepAlive.channel, (call) async {
      calls.add(call);
      return null;
    });
    await keepAlive.setKeepScreenOn(true);
    expect(calls.single.method, 'setKeepScreenOn');
    expect(calls.single.arguments, {'enabled': true});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceKeepAlive.channel, null);
    await keepAlive.setKeepScreenOn(false); // 不应抛异常
  });
}
```

- [ ] **Step 2: 实现 Dart 侧**

```dart
import 'package:flutter/services.dart';

/// 宠物端保活：屏幕常亮 + 平台后台驻留（鸿蒙长时任务 / Android 前台服务）。
/// 所有调用容忍 MissingPluginException（如桌面/测试环境）。
class DeviceKeepAlive {
  static const MethodChannel channel = MethodChannel('petnote/keep_alive');

  Future<void> setKeepScreenOn(bool enabled) =>
      _invoke('setKeepScreenOn', {'enabled': enabled});

  Future<void> startBackgroundKeepAlive() => _invoke('startBackgroundKeepAlive', {});

  Future<void> stopBackgroundKeepAlive() => _invoke('stopBackgroundKeepAlive', {});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 平台未实现时静默降级。
    } on PlatformException {
      // 权限缺失等场景不阻塞看板运行。
    }
  }
}
```

- [ ] **Step 3: 写结构测试（原生三端，沿用 `*_structure_test.dart` 模式）**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ohos 保活插件与权限就位', () {
    final moduleJson = File('ohos/entry/src/main/module.json5').readAsStringSync();
    expect(moduleJson, contains('ohos.permission.KEEP_BACKGROUND_RUNNING'));
    expect(moduleJson, contains('dataTransfer'));
    final pluginFiles = Directory('ohos/entry/src/main/ets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ets'))
        .map((f) => f.readAsStringSync())
        .join();
    expect(pluginFiles, contains('petnote/keep_alive'));
    expect(pluginFiles, contains('startBackgroundRunning'));
    expect(pluginFiles, contains('setWindowKeepScreenOn'));
  });

  test('android 保活通道与前台服务就位', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('FOREGROUND_SERVICE'));
    expect(manifest, contains('KeepAliveService'));
    final sources = Directory('android/app/src/main')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt') || f.path.endsWith('.java'))
        .map((f) => f.readAsStringSync())
        .join();
    expect(sources, contains('petnote/keep_alive'));
    expect(sources, contains('FLAG_KEEP_SCREEN_ON'));
  });

  test('ios 保活通道就位', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('petnote/keep_alive'));
    expect(appDelegate, contains('isIdleTimerDisabled'));
  });
}
```

- [ ] **Step 4: 实现三端原生**（执行时先读各端现有插件接线文件，完全照搬其注册模式）：

- **ohos（ets）**：新建 `KeepAlivePlugin.ets`——`MethodChannel('petnote/keep_alive')`；`setKeepScreenOn` → `windowStage.getMainWindowSync().setWindowKeepScreenOn(enabled)`；`startBackgroundKeepAlive` → `backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgent)`（wantAgent 指回 EntryAbility）；`stopBackgroundKeepAlive` → `stopBackgroundRunning`。`module.json5`：`requestPermissions` 加 `ohos.permission.KEEP_BACKGROUND_RUNNING`，abilities 内 `backgroundModes: ["dataTransfer"]`。
- **Android（Kotlin）**：在 MainActivity `configureFlutterEngine` 注册通道；`setKeepScreenOn` → `window.addFlags/clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)`；`start/stopBackgroundKeepAlive` → `startForegroundService(Intent(this, KeepAliveService::class.java))`/`stopService`。`KeepAliveService`：`onStartCommand` 里 `startForeground(1, notification)`（低优先级常驻通知「宠物端守护运行中」，channel id `petnote_keep_alive`）。Manifest：`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC` 权限 + `<service android:name=".KeepAliveService" android:foregroundServiceType="dataSync"/>`。
- **iOS（Swift）**：AppDelegate 注册通道；`setKeepScreenOn` → `UIApplication.shared.isIdleTimerDisabled = enabled`；`start/stopBackgroundKeepAlive` → no-op 返回 success（iOS 不支持，文案在设置页注明）。

- [ ] **Step 5: 接线**——`pet_device_home.dart` 配对成功进入看板时：`DeviceKeepAlive().setKeepScreenOn(keepScreenOnSetting)` + `startBackgroundKeepAlive()`；离开宠物端模式 / dispose 时 `stopBackgroundKeepAlive()` + `setKeepScreenOn(false)`。屏幕常亮开关持久化进 `AppSettingsController`（key `pet_keep_screen_on_v1`，默认 true，getter/setter 与 Task 7 同构）。

- [ ] **Step 6: 定向测试 + 构建验证**

```bash
flutter test test/device_keep_alive_test.dart test/keep_alive_structure_test.dart
flutter build apk --debug   # Android 编译验证
# ohos 构建（参照 memory：hvigor；确保 codegraph watcher 已停）
```

- [ ] **Step 7: 提交**

```bash
git add lib/platform ohos android ios test/
git commit -m "feat(keep-alive): screen-on and background keep-alive on three platforms"
```

---

## Part E：UI——主人端设备管理

### Task 20: 我的页「设备」入口 + DevicesPage

**Files:**
- Create: `lib/app/devices_page.dart`
- Modify: `lib/app/me_page.dart`
- Test: `test/devices_page_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/devices_page.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未配置服务器时显示引导，配置后显示生成配对码入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(MaterialApp(home: DevicesPage(settingsController: settings)));
    expect(find.byKey(const ValueKey('devices_server_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('devices_generate_code')), findsOneWidget);
  });

  testWidgets('设备列表渲染与操作菜单', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'sync_server_url_v1': 'wss://x/ws', 'sync_household_id_v1': 'h1'});
    final settings = await AppSettingsController.load();
    await tester.pumpWidget(MaterialApp(
      home: DevicesPage(
        settingsController: settings,
        initialDevices: const [
          SyncedDeviceInfo(deviceId: 'p1', name: '客厅平板', role: 'pet', online: true),
        ],
      ),
    ));
    await tester.pump();
    expect(find.text('客厅平板'), findsOneWidget);
    expect(find.byKey(const ValueKey('device_item_p1')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 实现 DevicesPage**：

- `Scaffold` + `HyperPageBackground` + `ListView`：`PageHeader(title: '设备', subtitle: '配对的宠物端设备')`；
- 「同步服务器」`SectionCard`：服务器地址 `TextField`（key `devices_server_field`，失焦保存到 `settings`，注意 saveSyncPairing 需要 householdId——新增 `settings.setSyncServerUrl(String)` 独立 setter，Task 7 补充该 setter 与对应测试断言）；
- 「添加设备」`SectionCard`：说明文字（每个家庭组当前支持一台宠物端设备）+ `FilledButton`「生成配对码」（key `devices_generate_code`）→ `OwnerPairingFlow.createAsOwner` → `showDialog` 大字号展示 6 位码 + `expiresAtMs` 倒计时（`StatefulBuilder` + `Timer.periodic` 每秒），`onPeerJoined` 回调时关闭对话框并 `SnackBar`「客厅平板 已配对 ✓」；
- 「已配对设备」`SectionCard`：`initialDevices ?? SyncService.instance?.ownerEngine?.devices` 渲染列表（key `device_item_<id>`：名称、在线圆点、服务宠物名（由 `store.pets` 映射，store 经构造可选传入）、`PopupMenuButton`：重命名（`showDialog` 输入框→`ownerEngine.renameDevice`）、更换服务宠物（`showModalBottomSheet` 宠物列表→`assignPet`）、解绑（确认对话框→`removeDevice`）；页面 `initState` 调 `ownerEngine?.requestDevices()`；
- 底部「将本机切换为宠物端」`TextButton`（二次确认→`settings.setDeviceRole(DeviceRole.pet)`）。

构造：`DevicesPage({required this.settingsController, this.store, this.initialDevices})`——`initialDevices` 仅测试注入。

- [ ] **Step 3: me_page 加入口**——在「数据备份」`_SettingsNavigationEntry` 之后新增同构条目：

```dart
            _SettingsNavigationEntry(
              key: const ValueKey('me_devices_entry'),
              icon: Icons.devices_rounded,
              title: '设备',
              subtitle: '配对宠物端，自动同步数据',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => DevicesPage(
                    settingsController: settingsController!,
                  ),
                ),
              ),
            ),
```

（`_SettingsNavigationEntry` 实际构造参数以 me_page.dart:445 现有定义为准，照搬相邻条目的写法；`settingsController` 为 null 时该条目隐藏。）同步更新 `test/me_page_redesign_test.dart` 受影响断言（定向跑确认）。

- [ ] **Step 4: `flutter test test/devices_page_test.dart test/me_page_redesign_test.dart` 通过后提交**

```bash
git add lib/app/devices_page.dart lib/app/me_page.dart lib/state test/
git commit -m "feat(devices): owner-side device management page with pairing code"
```

---

## Part F：小需求

### Task 21: 爱宠页副标题三态

**Files:**
- Modify: `lib/app/petnote_pages_pets.dart:33`
- Test: `test/pets_page_subtitle_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(PetNoteStore store) => MaterialApp(
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      );

  testWidgets('无宠物显示添加引导副标题', (tester) async {
    final store = await PetNoteStore.loadEmpty();
    await tester.pumpWidget(host(store));
    expect(find.text('添加宠物就有照护档案啦'), findsOneWidget);
  });

  testWidgets('一只宠物显示「它的照护档案」', (tester) async {
    final store = await PetNoteStore.loadEmpty();
    await store.addPet(/* 最小必填参数，以 addPet 实际签名为准，参考 pet_care_store_test.dart */);
    await tester.pumpWidget(host(store));
    expect(find.text('它的照护档案'), findsOneWidget);
  });

  testWidgets('多只宠物显示「它们的照护档案」', (tester) async {
    final store = await PetNoteStore.loadEmpty();
    await store.addPet(/* 第一只 */);
    await store.addPet(/* 第二只 */);
    await tester.pumpWidget(host(store));
    expect(find.text('它们的照护档案'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 确认失败后修改 petnote_pages_pets.dart:33**

```dart
        PageHeader(
          title: '爱宠',
          subtitle: widget.store.pets.isEmpty
              ? '添加宠物就有照护档案啦'
              : widget.store.pets.length == 1
                  ? '它的照护档案'
                  : '它们的照护档案',
```

- [ ] **Step 3: `flutter test test/pets_page_subtitle_test.dart` 通过；定向跑 `test/widget_test.dart` 中涉及爱宠页副标题的既有断言（若有「管理你的宠物档案」「的照护档案」字样，更新为新文案）**

- [ ] **Step 4: 提交**

```bash
git add lib/app/petnote_pages_pets.dart test/
git commit -m "feat(pets): subtitle reflects pet count (它/它们/添加引导)"
```

### Task 22: 远程视频胶囊按钮与选项

**Files:**
- Create: `lib/app/remote_video_entry.dart`
- Modify: `lib/app/petnote_pages_pets.dart`
- Test: `test/remote_video_entry_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('爱宠页标题右侧有远程视频胶囊，点击弹两个选项', (tester) async {
    final store = await PetNoteStore.loadWithSampleData();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PetsPage(store: store, onAddFirstPet: () {}, onEditPet: (_) {}),
      ),
    ));
    await tester.pump();
    final pill = find.byKey(const ValueKey('remote_video_pill'));
    expect(pill, findsOneWidget);

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.text('视频通话'), findsOneWidget);
    expect(find.text('先看看它'), findsOneWidget);

    await tester.tap(find.text('先看看它'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteVideoPlaceholderPage), findsOneWidget);
    expect(find.textContaining('即将上线'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 实现 `remote_video_entry.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum RemoteVideoMode { call, watch }

/// 「远程视频」胶囊按钮：放在爱宠页 PageHeader.trailing。
class RemoteVideoPillButton extends StatelessWidget {
  const RemoteVideoPillButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('remote_video_pill'),
      color: const Color(0xFFF2A65A),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showOptions(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text('远程视频',
                  style: TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('remote_video_option_call'),
              leading: const Icon(Icons.video_call_rounded, color: Color(0xFF335FCA)),
              title: const Text('视频通话'),
              subtitle: const Text('双方开启摄像头与麦克风，和它说说话'),
              onTap: () => _openPlaceholder(sheetContext, RemoteVideoMode.call),
            ),
            ListTile(
              key: const ValueKey('remote_video_option_watch'),
              leading: const Icon(Icons.visibility_rounded, color: Color(0xFF6B51C9)),
              title: const Text('先看看它'),
              subtitle: const Text('只打开宠物端的摄像头和麦克风，悄悄看看'),
              onTap: () => _openPlaceholder(sheetContext, RemoteVideoMode.watch),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _openPlaceholder(BuildContext sheetContext, RemoteVideoMode mode) {
    Navigator.of(sheetContext).pop();
    Navigator.of(sheetContext, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => RemoteVideoPlaceholderPage(mode: mode),
      ),
    );
  }
}

/// 一期占位页：展示配对宠物端在线状态，实时画面二期接 WebRTC。
class RemoteVideoPlaceholderPage extends StatelessWidget {
  const RemoteVideoPlaceholderPage({super.key, required this.mode});

  final RemoteVideoMode mode;

  @override
  Widget build(BuildContext context) {
    final devices = SyncService.instance?.ownerEngine?.devices.value ?? const [];
    final petDevice = devices.where((d) => d.role == 'pet').toList();
    return Scaffold(
      appBar: AppBar(title: Text(mode == RemoteVideoMode.call ? '视频通话' : '先看看它')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.ondemand_video_rounded, size: 64, color: Color(0xFFB8BEC8)),
            const SizedBox(height: 16),
            Text(
              petDevice.isEmpty
                  ? '还没有配对的宠物端设备\n先去「我的 → 设备」配对吧'
                  : petDevice.any((d) => d.online)
                      ? '${petDevice.first.name} 在线'
                      : '${petDevice.first.name} 当前离线',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('实时画面功能即将上线', style: TextStyle(color: Color(0xFF6C7280))),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 接入爱宠页**——`petnote_pages_pets.dart` 的 `PageHeader` 加 `trailing: const RemoteVideoPillButton()`（`petnote_pages.dart` 顶部补 import；该文件为 part 库，import 加在 `lib/app/petnote_pages.dart`）。

- [ ] **Step 4: `flutter test test/remote_video_entry_test.dart test/pets_page_subtitle_test.dart` 通过后提交**

```bash
git add lib/app test/remote_video_entry_test.dart
git commit -m "feat(pets): remote video pill with call/watch options and placeholder"
```

### Task 23: 隐私文案更新

**Files:**
- Modify: `lib/app/pet_first_launch_intro.dart`（第 3 页 values 第二条）
- Test: 更新 `test/first_launch_intro_structure_test.dart` 受影响断言

- [ ] **Step 1: 修改文案**——第 3 页 `_IntroValueData(title: '所有数据均安全保存在本地')` 改为 `'数据保存在本地，同步走你自己的服务器'`；第三条 `'除了AI谁都看不到你的数据'` 保持不变。

- [ ] **Step 2: 定向跑 `flutter test test/first_launch_intro_structure_test.dart`，按需更新断言，通过后提交**

```bash
git add lib/app/pet_first_launch_intro.dart test/first_launch_intro_structure_test.dart
git commit -m "docs(intro): privacy copy reflects self-hosted sync"
```

---

## Part G：收尾验证

### Task 24: 三端构建验证与交付说明

- [ ] **Step 1: 服务器全量测试**

```bash
cd packages/petnote_sync_protocol && dart test
cd ../../server && dart test
```
预期：全部 PASS（这两个包是纯 Dart，可全量跑）。

- [ ] **Step 2: App 定向测试清单**（逐个文件跑，禁止全量）

```bash
flutter test test/app_settings_device_role_test.dart
flutter test test/sync_secret_store_test.dart
flutter test test/sync_client_test.dart
flutter test test/owner_sync_engine_test.dart
flutter test test/pet_replica_controller_test.dart
flutter test test/sync_service_test.dart
flutter test test/first_launch_role_page_test.dart
flutter test test/device_role_routing_test.dart
flutter test test/pet_pairing_page_test.dart
flutter test test/owner_pairing_flow_test.dart
flutter test test/pet_device_dashboard_test.dart
flutter test test/pet_device_settings_page_test.dart
flutter test test/device_keep_alive_test.dart
flutter test test/keep_alive_structure_test.dart
flutter test test/devices_page_test.dart
flutter test test/me_page_redesign_test.dart
flutter test test/pets_page_subtitle_test.dart
flutter test test/remote_video_entry_test.dart
flutter test test/first_launch_intro_structure_test.dart
flutter test test/widget_test.dart
flutter test test/sync_server_deploy_structure_test.dart
```

- [ ] **Step 3: 构建验证（验证止于构建成功，不部署真机）**

```bash
flutter build apk --debug
# 鸿蒙：按 memory 中 hvigor 流程构建（停 codegraph watcher 后 ohpm install / hvigor assembleHap）
# iOS：无 mac 环境则跳过并在交付说明注明
```

- [ ] **Step 4: 提交收尾 + 交付说明**——汇总：已完成清单、测试输出证据、用户待办（部署服务器 docker compose、填服务器地址、模拟器实测配对/看板/保活）。

```bash
git add -A
git commit -m "chore: phase1 wrap-up - build verification and delivery notes"
```

---

## 自查记录（writing-plans Self-Review）

- **Spec 覆盖**：需求1→Task 13/14；需求2→Task 1-12/16/20；需求3→Task 17/18/19；需求4→Task 21；需求5→Task 22 + 协议（Task 2）+ 服务器透传（Task 5）；隐私文案→Task 23；部署→Task 6。
- **占位符**：Task 21 测试中 `addPet(/* 最小必填参数 */)` 是有意引用——执行者必须先读 `test/pet_care_store_test.dart` 取实际签名（计划内已写明出处）；`PetNoteStore.loadWithSampleData/loadEmpty` 同理以现有测试辅助为准。这是「以仓内真实 API 为准」的指令而非空占位。
- **类型一致性**：`SyncTransport` 在 Task 10 定义于 `lib/sync/sync_transport.dart`，Task 9 的 `SyncClient` 声明 implements（Task 10 步骤已注明回改）；`PetAction`/`SyncedDeviceInfo`/`SyncMessageTypes` 全部来自 Task 2 协议包。
