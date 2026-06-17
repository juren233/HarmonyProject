import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

class TestClient {
  TestClient(int port)
      : channel = IOWebSocketChannel.connect('ws://127.0.0.1:$port/ws') {
    _subscription = channel.stream.listen(
      (raw) {
        final message = SyncMessage.decode(raw as String);
        _messages.add(message);
        _controller.add(message);
      },
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  final IOWebSocketChannel channel;
  final StreamController<SyncMessage> _controller =
      StreamController<SyncMessage>.broadcast();
  final List<SyncMessage> _messages = <SyncMessage>[];
  late final StreamSubscription<dynamic> _subscription;

  void send(String type, Map<String, dynamic> payload) {
    channel.sink.add(SyncMessage(type, payload).encode());
  }

  Future<SyncMessage> expectType(String type) {
    final existingIndex =
        _messages.indexWhere((message) => message.type == type);
    if (existingIndex >= 0) {
      return Future.value(_messages.removeAt(existingIndex));
    }
    return _controller.stream
        .firstWhere((message) => message.type == type)
        .then((message) {
      _messages.remove(message);
      return message;
    }).timeout(const Duration(seconds: 5));
  }

  Future<void> expectNoType(String type) async {
    expect(_messages.where((message) => message.type == type), isEmpty);
    final received = Completer<SyncMessage>();
    late final StreamSubscription<SyncMessage> subscription;
    subscription = _controller.stream
        .where((message) => message.type == type)
        .listen((message) {
      if (!received.isCompleted) {
        received.complete(message);
      }
    });
    final result = await Future.any<Object?>([
      received.future,
      Future<void>.delayed(const Duration(milliseconds: 250)),
    ]);
    await subscription.cancel();
    if (result is SyncMessage) {
      fail('不应收到 $type 消息：${result.payload}');
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await channel.sink.close();
  }
}

void main() {
  late SyncServerApp app;
  late HttpServer server;
  late List<TestClient> clients;

  setUp(() async {
    clients = <TestClient>[];
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_sync_flow_'),
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    await app.close();
    await server.close(force: true);
  });

  TestClient connect() {
    final client = TestClient(server.port);
    clients.add(client);
    return client;
  }

  test('配对后完成快照、Action、设备管理与信令透传闭环', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    expect(created.payload['code'],
        isA<String>().having((code) => code.length, 'length', 4));
    expect(created.payload['householdId'], isA<String>());
    expect(created.payload['saltBase64'], isA<String>());
    expect(created.payload['authToken'], isA<String>());
    expect(created.payload['hasPetDevice'], isFalse);

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    final joined = await petPair.expectType(SyncMessageTypes.pairJoined);
    expect(joined.payload['householdId'], created.payload['householdId']);
    expect(joined.payload['saltBase64'], created.payload['saltBase64']);
    expect(joined.payload['authToken'], created.payload['authToken']);
    final peerJoined =
        await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);
    expect(peerJoined.payload['deviceId'], 'pet-1');

    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;
    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    expect(
        (await owner.expectType(SyncMessageTypes.helloAck))
            .payload['snapshotVersion'],
        0);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    expect(
        (await pet.expectType(SyncMessageTypes.helloAck))
            .payload['snapshotVersion'],
        0);

    owner.send(SyncMessageTypes.snapshotPush, {
      'version': 1,
      'ciphertext': 'encrypted-snapshot-v1',
    });
    final snapshotRegistered =
        await owner.expectType(SyncMessageTypes.syncReceived);
    expect(snapshotRegistered.payload['version'], 1);
    final pushedSnapshot = await pet.expectType(SyncMessageTypes.snapshot);
    expect(pushedSnapshot.payload['version'], 1);
    expect(pushedSnapshot.payload['ciphertext'], 'encrypted-snapshot-v1');
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': pushedSnapshot.payload['syncId'],
      'originDeviceId': pushedSnapshot.payload['originDeviceId'],
    });
    final ownerReceipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(ownerReceipt.payload['syncId'], pushedSnapshot.payload['syncId']);
    expect(ownerReceipt.payload['receivedDeviceId'], 'pet-1');

    pet.send(SyncMessageTypes.snapshotRequest, {});
    await pet.expectNoType(SyncMessageTypes.snapshot);

    owner.send(SyncMessageTypes.callInvite, {
      'callId': 'call-1',
      'mode': 'watch',
      'sdp': 'offer',
      'targetDeviceId': 'pet-1',
    });
    final invite = await pet.expectType(SyncMessageTypes.callInvite);
    expect(invite.payload['mode'], 'watch');
    pet.send(SyncMessageTypes.iceCandidate, {
      'callId': 'call-1',
      'candidate': 'candidate-1',
      'targetDeviceId': 'owner-1',
    });
    expect(
        (await owner.expectType(SyncMessageTypes.iceCandidate))
            .payload['candidate'],
        'candidate-1');

    await owner.close();
    clients.remove(owner);
    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'action-1',
      'ciphertext': 'encrypted-action',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final actionRegistered =
        await pet.expectType(SyncMessageTypes.syncReceived);
    expect(actionRegistered.payload['actionId'], 'action-1');

    final replayOwner = connect();
    replayOwner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await replayOwner.expectType(SyncMessageTypes.helloAck);
    replayOwner.send(SyncMessageTypes.snapshotRequest, {});
    final replayedAction =
        await replayOwner.expectType(SyncMessageTypes.action);
    expect(replayedAction.payload['actionId'], 'action-1');
    expect(replayedAction.payload['ciphertext'], 'encrypted-action');
    replayOwner.send(SyncMessageTypes.syncReceived, {
      'syncId': replayedAction.payload['syncId'],
      'originDeviceId': replayedAction.payload['originDeviceId'],
    });
    final petReceipt = await pet.expectType(SyncMessageTypes.syncReceived);
    expect(petReceipt.payload['syncId'], replayedAction.payload['syncId']);
    expect(petReceipt.payload['receivedDeviceId'], 'owner-1');
    expect(petReceipt.payload['actionId'], 'action-1');
    expect(petReceipt.payload['kind'], PetActionKind.markDone.name);
    expect(petReceipt.payload['sourceType'], 'todo');
    expect(petReceipt.payload['itemId'], 'todo-1');
    replayOwner.send(SyncMessageTypes.snapshotRequest, {});
    await replayOwner.expectNoType(SyncMessageTypes.action);

    replayOwner.send(SyncMessageTypes.devicesRequest, {});
    final devices = await replayOwner.expectType(SyncMessageTypes.devices);
    expect(devices.payload['devices'], isA<List<dynamic>>());
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      contains('pet-1'),
    );
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('owner-1')),
    );

    replayOwner.send(SyncMessageTypes.deviceUpdate, {
      'deviceId': 'pet-1',
      'name': '客厅值守平板',
      'servedPetId': 'pet-a',
    });
    final config = await pet.expectType(SyncMessageTypes.deviceConfig);
    expect(config.payload['servedPetId'], 'pet-a');
    final updatedDevices =
        await replayOwner.expectType(SyncMessageTypes.devices);
    final updatedPet = (updatedDevices.payload['devices'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((device) => device['deviceId'] == 'pet-1');
    expect(updatedPet['name'], '客厅值守平板');
    expect(updatedPet['servedPetId'], 'pet-a');

    replayOwner.send(SyncMessageTypes.deviceRemove, {'deviceId': 'pet-1'});
    final removedConfig = await pet.expectType(SyncMessageTypes.deviceConfig);
    expect(removedConfig.payload['removed'], isTrue);
    final afterRemove = await replayOwner.expectType(SyncMessageTypes.devices);
    expect(
      (afterRemove.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('pet-1')),
    );

    final persisted = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persisted, isNot(contains('encrypted-snapshot-v1')));
    expect(persisted, contains('encrypted-action'));
    expect(persisted, contains('completedActions'));
    expect(persisted, isNot(contains('"syncEvents":{"')));
  });

  test('移除设备后其他在线设备会收到更新后的设备列表', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.pairCreate, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    final backupInvite = await owner.expectType(SyncMessageTypes.pairCreated);
    final backupPair = connect();
    backupPair.send(SyncMessageTypes.pairJoin, {
      'code': backupInvite.payload['code'],
      'deviceId': 'owner-2',
      'deviceName': '备用主人',
      'role': 'owner',
    });
    await backupPair.expectType(SyncMessageTypes.pairJoined);
    await owner.expectType(SyncMessageTypes.pairPeerJoined);

    owner.send(SyncMessageTypes.deviceRemove, {'deviceId': 'pet-1'});
    final removedConfig = await pet.expectType(SyncMessageTypes.deviceConfig);
    expect(removedConfig.payload['removed'], isTrue);

    final ownerDevices = await owner.expectType(SyncMessageTypes.devices);
    final backupDevices = await backupPair.expectType(SyncMessageTypes.devices);

    expect(
      (ownerDevices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('pet-1')),
    );
    expect(
      (backupDevices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('pet-1')),
    );
    expect(
      (backupDevices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('owner-2')),
    );
  });

  test('主人端不能在设备管理里移除当前设备', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.deviceRemove, {'deviceId': 'owner-1'});
    expect(
      (await owner.expectType(SyncMessageTypes.pairError)).payload['message'],
      'forbidden',
    );

    owner.send(SyncMessageTypes.devicesRequest, {});
    final devices = await owner.expectType(SyncMessageTypes.devices);
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('owner-1')),
    );
  });

  test('宠物端能中转快照和查看设备列表但不能移除设备', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    pet.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'pet-snapshot',
    });
    await pet.expectNoType(SyncMessageTypes.pairError);

    pet.send(SyncMessageTypes.devicesRequest, {});
    final devices = await pet.expectType(SyncMessageTypes.devices);
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      contains('owner-1'),
    );
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      isNot(contains('pet-1')),
    );

    pet.send(SyncMessageTypes.deviceRemove, {'deviceId': 'owner-1'});
    expect(
        (await pet.expectType(SyncMessageTypes.pairError)).payload['message'],
        'forbidden');
  });

  test('同一设备可按当前会话角色切换主人端和宠物端能力', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);

    final petAsOwner = connect();
    petAsOwner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await petAsOwner.expectType(SyncMessageTypes.helloAck);
    petAsOwner.send(SyncMessageTypes.deviceUpdate, {
      'deviceId': 'owner-1',
      'name': '主人手机已更新',
    });
    final ownerDevices = await petAsOwner.expectType(SyncMessageTypes.devices);
    final updatedOwner = (ownerDevices.payload['devices'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((device) => device['deviceId'] == 'owner-1');
    expect(updatedOwner['name'], '主人手机已更新');

    final petAsPet = connect();
    petAsPet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await petAsPet.expectType(SyncMessageTypes.helloAck);
    petAsPet.send(SyncMessageTypes.deviceRemove, {'deviceId': 'owner-1'});
    expect(
        (await petAsPet.expectType(SyncMessageTypes.pairError))
            .payload['message'],
        'forbidden');
    petAsPet.send(SyncMessageTypes.devicesRequest, {});
    final petDevices = await petAsPet.expectType(SyncMessageTypes.devices);
    expect(
      (petDevices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      contains('owner-1'),
    );
  });

  test('离线设备没有固定端身份不会被设备列表标成宠物端', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await petPair.close();
    clients.remove(petPair);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);
    owner.send(SyncMessageTypes.devicesRequest, {});

    final devices = await owner.expectType(SyncMessageTypes.devices);
    final offlinePet = (devices.payload['devices'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((device) => device['deviceId'] == 'pet-1');
    expect(offlinePet['online'], isFalse);
    expect(offlinePet['role'], 'unknown');
  });

  test('hello 必须携带正确家庭认证 token', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;

    final attacker = connect();
    attacker.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': 'wrong-token',
      'deviceName': '伪装主人',
    });

    expect(
      (await attacker.expectType(SyncMessageTypes.pairError))
          .payload['message'],
      'auth failed',
    );
  });

  test('匿名连接不能为已有家庭组生成配对码', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);

    final attacker = connect();
    attacker.send(SyncMessageTypes.pairCreate, {
      'householdId': created.payload['householdId'],
      'deviceId': 'attacker-owner',
      'deviceName': '伪装主人',
    });

    expect(
      (await attacker.expectType(SyncMessageTypes.pairError))
          .payload['message'],
      'forbidden',
    );
  });

  test('已配对设备继续生成配对码后新设备加入三端设备列表互通', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final firstPet = connect();
    firstPet.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await firstPet.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final firstPetSession = connect();
    firstPetSession.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await firstPetSession.expectType(SyncMessageTypes.helloAck);
    firstPetSession.send(SyncMessageTypes.pairCreate, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    final secondCode =
        await firstPetSession.expectType(SyncMessageTypes.pairCreated);

    final secondPet = connect();
    secondPet.send(SyncMessageTypes.pairJoin, {
      'code': secondCode.payload['code'],
      'deviceId': 'pet-2',
      'deviceName': '卧室平板',
    });

    await secondPet.expectType(SyncMessageTypes.pairJoined);
    final peerJoined =
        await firstPetSession.expectType(SyncMessageTypes.pairPeerJoined);
    expect(peerJoined.payload['deviceId'], 'pet-2');

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    for (final client in <TestClient>[owner, firstPetSession]) {
      client.send(SyncMessageTypes.devicesRequest, {});
      final devices = await client.expectType(SyncMessageTypes.devices);
      final deviceIds = (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId'])
          .toList();
      if (client == owner) {
        expect(deviceIds, isNot(contains('owner-1')));
        expect(deviceIds, containsAll(<String>['pet-1', 'pet-2']));
      } else {
        expect(deviceIds, isNot(contains('pet-1')));
        expect(deviceIds, containsAll(<String>['owner-1', 'pet-2']));
      }
    }
  });

  test('业务同步消息只中转给其他在线设备且不限制设备角色', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    pet.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'pet-snapshot',
    });
    final snapshot = await owner.expectType(SyncMessageTypes.snapshot);
    expect(snapshot.payload['ciphertext'], 'pet-snapshot');

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'owner-action-1',
      'ciphertext': 'owner-action',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final action = await pet.expectType(SyncMessageTypes.action);
    expect(action.payload['ciphertext'], 'owner-action');

    await owner.expectNoType(SyncMessageTypes.snapshot);
    await pet.expectNoType(SyncMessageTypes.action);
  });

  test('正常数据变更操作会透传给其他设备并回执', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.mutationPush, {
      'mutationId': 'mutation-1',
      'ciphertext': 'encrypted-mutation',
      'entityType': PetNoteEntityType.todo.name,
      'entityId': 'todo-remote',
      'kind': PetNoteMutationKind.upsert.name,
    });

    final registrationReceipt =
        await owner.expectType(SyncMessageTypes.syncReceived);
    expect(registrationReceipt.payload['mutationId'], 'mutation-1');
    expect(registrationReceipt.payload['receivedDeviceId'], 'owner-1');
    final persistedAfterReceipt = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persistedAfterReceipt, contains('mutation-1'));
    expect(persistedAfterReceipt, contains('encrypted-mutation'));

    final mutation = await pet.expectType(SyncMessageTypes.mutation);
    expect(mutation.payload['mutationId'], 'mutation-1');
    expect(mutation.payload['ciphertext'], 'encrypted-mutation');
    expect(mutation.payload['entityType'], PetNoteEntityType.todo.name);
    expect(mutation.payload['entityId'], 'todo-remote');
    expect(mutation.payload['kind'], PetNoteMutationKind.upsert.name);

    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': mutation.payload['syncId'],
      'originDeviceId': mutation.payload['originDeviceId'],
    });
    final receipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(receipt.payload['mutationId'], 'mutation-1');
    expect(receipt.payload['receivedDeviceId'], 'pet-1');
  });

  test('重复 mutationId 不会重复广播给其他设备', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    final payload = {
      'mutationId': 'mutation-repeat',
      'ciphertext': 'encrypted-mutation',
      'entityType': PetNoteEntityType.todo.name,
      'entityId': 'todo-repeat',
      'kind': PetNoteMutationKind.upsert.name,
    };
    owner.send(SyncMessageTypes.mutationPush, payload);
    final mutation = await pet.expectType(SyncMessageTypes.mutation);
    expect(mutation.payload['mutationId'], 'mutation-repeat');

    owner.send(SyncMessageTypes.mutationPush, payload);
    await pet.expectNoType(SyncMessageTypes.mutation);
  });

  test('mutation 事件清理后重复 mutationId 仍不会重复广播', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    final payload = {
      'mutationId': 'mutation-pruned-repeat',
      'ciphertext': 'encrypted-mutation',
      'entityType': PetNoteEntityType.todo.name,
      'entityId': 'todo-repeat',
      'kind': PetNoteMutationKind.upsert.name,
    };
    owner.send(SyncMessageTypes.mutationPush, payload);
    final mutation = await pet.expectType(SyncMessageTypes.mutation);
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': mutation.payload['syncId'],
      'originDeviceId': mutation.payload['originDeviceId'],
    });
    final firstReceipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(firstReceipt.payload['mutationId'], 'mutation-pruned-repeat');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await app.store.flush();
    final persistedAfterPrune = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persistedAfterPrune, isNot(contains('"syncEvents":{"')));

    owner.send(SyncMessageTypes.mutationPush, payload);
    await pet.expectNoType(SyncMessageTypes.mutation);
    final duplicateReceipt =
        await owner.expectType(SyncMessageTypes.syncReceived);
    expect(duplicateReceipt.payload['mutationId'], 'mutation-pruned-repeat');
  });

  test('主动拉取快照会把 dataPolicy 透传给其他设备', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.snapshotRequest, {
      'dataPolicy': SyncDataPolicy.remoteWins.name,
    });
    final request = await pet.expectType(SyncMessageTypes.snapshotRequest);
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    pet.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'remote-snapshot',
      'dataPolicy': request.payload['dataPolicy'],
    });
    final snapshot = await owner.expectType(SyncMessageTypes.snapshot);
    expect(snapshot.payload['ciphertext'], 'remote-snapshot');
    expect(snapshot.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
  });

  test('主人端生成配对码后宠物端 localWins 快照仍同步给主人同步连接', () async {
    final owner = connect();
    owner.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
      'role': 'owner',
    });
    final created = await owner.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final ownerSync = connect();
    ownerSync.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await ownerSync.expectType(SyncMessageTypes.helloAck);

    final ownerPairing = connect();
    ownerPairing.send(SyncMessageTypes.pairCreate, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    final nextCode =
        await ownerPairing.expectType(SyncMessageTypes.pairCreated);

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': nextCode.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
      'role': 'pet',
      'dataPolicy': SyncDataPolicy.localWins.name,
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPairing.expectType(SyncMessageTypes.pairPeerJoined);

    final petSync = connect();
    petSync.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await petSync.expectType(SyncMessageTypes.helloAck);
    petSync.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'pet-local-snapshot',
      'dataPolicy': SyncDataPolicy.remoteWins.name,
      'completedItemKeys': <String>[],
    });

    final snapshot = await ownerSync.expectType(SyncMessageTypes.snapshot);
    expect(snapshot.payload['ciphertext'], 'pet-local-snapshot');
    expect(snapshot.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
  });

  test('完成状态到达服务器后会否决同一事项后续延后或跳过', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'done-action',
      'ciphertext': 'done-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final doneAction = await pet.expectType(SyncMessageTypes.action);
    expect(doneAction.payload['ciphertext'], 'done-ciphertext');

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-action',
      'ciphertext': 'postpone-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final rejectedAction = await pet.expectType(SyncMessageTypes.action);
    expect(rejectedAction.payload['actionId'], 'done-action');
    expect(rejectedAction.payload['ciphertext'], 'done-ciphertext');
    final completedReceipt =
        await pet.expectType(SyncMessageTypes.syncReceived);
    expect(completedReceipt.payload['actionId'], 'done-action');
    expect(completedReceipt.payload['kind'], PetActionKind.markDone.name);
    expect(completedReceipt.payload['sourceType'], 'todo');
    expect(completedReceipt.payload['itemId'], 'todo-1');
    await owner.expectNoType(SyncMessageTypes.action);
  });

  test('完成事件已清理后仍会用完成动作回执被否决操作', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'done-pruned',
      'ciphertext': 'done-pruned-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-pruned',
    });
    final doneAction = await pet.expectType(SyncMessageTypes.action);
    expect(doneAction.payload['actionId'], 'done-pruned');

    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': doneAction.payload['syncId'],
      'originDeviceId': doneAction.payload['originDeviceId'],
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await app.store.flush();
    final persistedAfterPrune = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persistedAfterPrune, isNot(contains('"syncEvents":{"')));

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-after-prune',
      'ciphertext': 'postpone-after-prune-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-pruned',
    });

    final rejectedAction = await pet.expectType(SyncMessageTypes.action);
    expect(rejectedAction.payload['actionId'], 'done-pruned');
    final receipt = await pet.expectType(SyncMessageTypes.syncReceived);
    expect(receipt.payload['actionId'], 'done-pruned');
    expect(receipt.payload['kind'], PetActionKind.markDone.name);
    expect(receipt.payload['sourceType'], 'todo');
    expect(receipt.payload['itemId'], 'todo-pruned');
  });

  test('重复 actionId 不会重复广播且发送端会收到登记回执', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    final payload = {
      'actionId': 'action-repeat',
      'ciphertext': 'encrypted-action',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    };
    owner.send(SyncMessageTypes.actionPush, payload);
    final action = await pet.expectType(SyncMessageTypes.action);
    expect(action.payload['actionId'], 'action-repeat');
    final receipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(receipt.payload['actionId'], 'action-repeat');
    expect(receipt.payload['sourceType'], 'todo');
    expect(receipt.payload['itemId'], 'todo-1');

    owner.send(SyncMessageTypes.actionPush, payload);
    await pet.expectNoType(SyncMessageTypes.action);
    final duplicateReceipt =
        await owner.expectType(SyncMessageTypes.syncReceived);
    expect(duplicateReceipt.payload['actionId'], 'action-repeat');
  });

  test('已确认的延后 action 被剪枝后重复上报不会再次广播', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    final payload = {
      'actionId': 'postpone-repeat',
      'ciphertext': 'postpone-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 100,
    };
    owner.send(SyncMessageTypes.actionPush, payload);
    final action = await pet.expectType(SyncMessageTypes.action);
    expect(action.payload['actionId'], 'postpone-repeat');
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': action.payload['syncId'],
      'originDeviceId': action.payload['originDeviceId'],
    });
    final receipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(receipt.payload['actionId'], 'postpone-repeat');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await app.store.flush();
    final persistedAfterPrune = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persistedAfterPrune, isNot(contains('"syncEvents":{"')));

    owner.send(SyncMessageTypes.actionPush, {
      ...payload,
      'actionId': 'postpone-repeat-after-resume',
    });
    await pet.expectNoType(SyncMessageTypes.action);
    final duplicateReceipt =
        await owner.expectType(SyncMessageTypes.syncReceived);
    expect(duplicateReceipt.payload['actionId'], 'postpone-repeat');
    expect(duplicateReceipt.payload['kind'], PetActionKind.postpone.name);
  });

  test('同一事项新操作确认后旧操作重放不会覆盖最新状态', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-before-skip',
      'ciphertext': 'postpone-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 100,
    });
    final postponeAction = await pet.expectType(SyncMessageTypes.action);
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': postponeAction.payload['syncId'],
      'originDeviceId': postponeAction.payload['originDeviceId'],
    });
    await owner.expectType(SyncMessageTypes.syncReceived);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'skip-after-postpone',
      'ciphertext': 'skip-ciphertext',
      'kind': PetActionKind.skip.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 200,
    });
    final skipAction = await pet.expectType(SyncMessageTypes.action);
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': skipAction.payload['syncId'],
      'originDeviceId': skipAction.payload['originDeviceId'],
    });
    await owner.expectType(SyncMessageTypes.syncReceived);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-replayed-after-skip',
      'ciphertext': 'postpone-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 100,
    });
    await pet.expectNoType(SyncMessageTypes.action);
    final replayReceipt = await owner.expectType(SyncMessageTypes.syncReceived);
    expect(replayReceipt.payload['actionId'], 'skip-after-postpone');
    expect(replayReceipt.payload['kind'], PetActionKind.skip.name);
  });

  test('远端权威快照会清理旧 checklist 索引并允许后续新操作', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-old',
      'ciphertext': 'postpone-old-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 100,
    });
    final oldAction = await pet.expectType(SyncMessageTypes.action);
    pet.send(SyncMessageTypes.syncReceived, {
      'syncId': oldAction.payload['syncId'],
      'originDeviceId': oldAction.payload['originDeviceId'],
    });
    await owner.expectType(SyncMessageTypes.syncReceived);

    owner.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'remote-wins-snapshot',
      'completedItemKeys': <String>[],
      'dataPolicy': SyncDataPolicy.remoteWins.name,
    });
    await owner.expectType(SyncMessageTypes.syncReceived);
    await pet.expectType(SyncMessageTypes.snapshot);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'postpone-new',
      'ciphertext': 'postpone-new-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
      'occurredAtMs': 200,
    });
    final newAction = await pet.expectType(SyncMessageTypes.action);
    expect(newAction.payload['actionId'], 'postpone-new');
    expect(newAction.payload['kind'], PetActionKind.postpone.name);
  });

  test('完成状态到达服务器后会否决缺失完成状态的后续快照', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'done-action',
      'ciphertext': 'done-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final doneAction = await pet.expectType(SyncMessageTypes.action);
    expect(doneAction.payload['ciphertext'], 'done-ciphertext');

    pet.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'pet-snapshot-without-done',
      'completedItemKeys': <String>[],
    });

    final rejectedSnapshotAction =
        await pet.expectType(SyncMessageTypes.action);
    expect(rejectedSnapshotAction.payload['actionId'], 'done-action');
    expect(rejectedSnapshotAction.payload['ciphertext'], 'done-ciphertext');
    await owner.expectNoType(SyncMessageTypes.snapshot);
  });

  test('远端权威覆盖快照不会被本机旧完成状态拦截', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    owner.send(SyncMessageTypes.actionPush, {
      'actionId': 'owner-done-action',
      'ciphertext': 'owner-done-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-from-owner',
    });
    await pet.expectType(SyncMessageTypes.action);

    owner.send(SyncMessageTypes.snapshotRequest, {
      'dataPolicy': SyncDataPolicy.remoteWins.name,
    });
    final request = await pet.expectType(SyncMessageTypes.snapshotRequest);
    expect(request.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);

    pet.send(SyncMessageTypes.snapshotPush, {
      'version': 2,
      'ciphertext': 'pet-authoritative-snapshot',
      'dataPolicy': SyncDataPolicy.remoteWins.name,
      'completedItemKeys': <String>[],
    });

    final snapshot = await owner.expectType(SyncMessageTypes.snapshot);
    expect(snapshot.payload['ciphertext'], 'pet-authoritative-snapshot');
    expect(snapshot.payload['dataPolicy'], SyncDataPolicy.remoteWins.name);
    await pet.expectNoType(SyncMessageTypes.action);
  });

  test('历史同步事件重放不会绕过完成状态优先级', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'old-postpone-action',
      'ciphertext': 'old-postpone-ciphertext',
      'kind': PetActionKind.postpone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    final oldPostpone = await owner.expectType(SyncMessageTypes.action);
    expect(oldPostpone.payload['ciphertext'], 'old-postpone-ciphertext');
    await owner.close();
    clients.remove(owner);

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'done-action',
      'ciphertext': 'done-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final replayOwner = connect();
    replayOwner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await replayOwner.expectType(SyncMessageTypes.helloAck);
    replayOwner.send(SyncMessageTypes.snapshotRequest, {});

    final replayedAction =
        await replayOwner.expectType(SyncMessageTypes.action);
    expect(replayedAction.payload['actionId'], 'done-action');
    expect(replayedAction.payload['ciphertext'], 'done-ciphertext');
    await replayOwner.expectNoType(SyncMessageTypes.snapshot);
  });

  test('服务器重启后仍保留未回执事件并在回执后清理', () async {
    final dataDirectory = app.store.dataDirectory;
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'offline-action',
      'ciphertext': 'offline-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await app.store.flush();

    final persistedBeforeRestart =
        await File('${dataDirectory.path}/households.json').readAsString();
    expect(persistedBeforeRestart, contains('offline-ciphertext'));
    expect(persistedBeforeRestart, contains('syncEvents'));
    expect(persistedBeforeRestart, contains('"receivedByDeviceIds":[]'));

    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    await app.close();
    await server.close(force: true);

    app = SyncServerApp(dataDirectory: dataDirectory);
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);
    owner.send(SyncMessageTypes.snapshotRequest, {});
    final replayedAction = await owner.expectType(SyncMessageTypes.action);
    expect(replayedAction.payload['actionId'], 'offline-action');
    expect(replayedAction.payload['ciphertext'], 'offline-ciphertext');

    owner.send(SyncMessageTypes.syncReceived, {
      'syncId': replayedAction.payload['syncId'],
      'originDeviceId': replayedAction.payload['originDeviceId'],
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final persistedAfterReceipt =
        await File('${dataDirectory.path}/households.json').readAsString();
    expect(persistedAfterReceipt, contains('offline-ciphertext'));
    expect(persistedAfterReceipt, contains('completedActions'));
    expect(persistedAfterReceipt, isNot(contains('"syncEvents":{"')));
    final decodedAfterReceipt =
        jsonDecode(persistedAfterReceipt) as Map<String, dynamic>;
    final persistedHousehold = (decodedAfterReceipt['households']
        as Map<String, dynamic>)[householdId] as Map<String, dynamic>;
    expect(
      persistedHousehold['actionSyncEventIds'],
      containsPair('offline-action', replayedAction.payload['syncId']),
    );
    expect(persistedHousehold['mutationSyncEventIds'], isEmpty);

    final replayPet = connect();
    replayPet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await replayPet.expectType(SyncMessageTypes.helloAck);
    replayPet.send(SyncMessageTypes.actionPush, {
      'actionId': 'offline-action',
      'ciphertext': 'offline-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    await owner.expectNoType(SyncMessageTypes.action);
    final duplicateReceipt =
        await replayPet.expectType(SyncMessageTypes.syncReceived);
    expect(duplicateReceipt.payload['actionId'], 'offline-action');
  });

  test('首次发送设备不需要回执自己产生的同步事件', () async {
    final ownerPair = connect();
    ownerPair.send(SyncMessageTypes.pairCreate, {
      'deviceId': 'owner-1',
      'deviceName': '主人手机',
    });
    final created = await ownerPair.expectType(SyncMessageTypes.pairCreated);
    final householdId = created.payload['householdId'] as String;
    final authToken = created.payload['authToken'] as String;

    final petPair = connect();
    petPair.send(SyncMessageTypes.pairJoin, {
      'code': created.payload['code'],
      'deviceId': 'pet-1',
      'deviceName': '客厅平板',
    });
    await petPair.expectType(SyncMessageTypes.pairJoined);
    await ownerPair.expectType(SyncMessageTypes.pairPeerJoined);

    final pet = connect();
    pet.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'pet',
      'authToken': authToken,
      'deviceName': '客厅平板',
    });
    await pet.expectType(SyncMessageTypes.helloAck);

    pet.send(SyncMessageTypes.actionPush, {
      'actionId': 'pet-action',
      'ciphertext': 'pet-action-ciphertext',
      'kind': PetActionKind.markDone.name,
      'sourceType': 'todo',
      'itemId': 'todo-1',
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    pet.send(SyncMessageTypes.snapshotRequest, {});
    await pet.expectNoType(SyncMessageTypes.action);

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);
    owner.send(SyncMessageTypes.snapshotRequest, {});
    final replayedAction = await owner.expectType(SyncMessageTypes.action);
    expect(replayedAction.payload['actionId'], 'pet-action');

    owner.send(SyncMessageTypes.syncReceived, {
      'syncId': replayedAction.payload['syncId'],
      'originDeviceId': replayedAction.payload['originDeviceId'],
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final persisted = await File(
      '${app.store.dataDirectory.path}/households.json',
    ).readAsString();
    expect(persisted, isNot(contains('"syncEvents":{"')));
  });
}
