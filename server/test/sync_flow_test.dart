import 'dart:async';
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
        isA<String>().having((code) => code.length, 'length', 6));
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
    final pushedSnapshot = await pet.expectType(SyncMessageTypes.snapshot);
    expect(pushedSnapshot.payload['version'], 1);
    expect(pushedSnapshot.payload['ciphertext'], 'encrypted-snapshot-v1');

    pet.send(SyncMessageTypes.snapshotRequest, {});
    final requestedSnapshot = await pet.expectType(SyncMessageTypes.snapshot);
    expect(requestedSnapshot.payload['version'], 1);

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
    });

    final replayOwner = connect();
    replayOwner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await replayOwner.expectType(SyncMessageTypes.helloAck);
    final replayedAction =
        await replayOwner.expectType(SyncMessageTypes.action);
    expect(replayedAction.payload['actionId'], 'action-1');
    expect(replayedAction.payload['ciphertext'], 'encrypted-action');
    replayOwner.send(SyncMessageTypes.actionAck, {'actionId': 'action-1'});
    await replayOwner.expectNoType(SyncMessageTypes.action);

    replayOwner.send(SyncMessageTypes.devicesRequest, {});
    final devices = await replayOwner.expectType(SyncMessageTypes.devices);
    expect(devices.payload['devices'], isA<List<dynamic>>());
    expect(
      (devices.payload['devices'] as List<dynamic>)
          .map((device) => (device as Map<String, dynamic>)['deviceId']),
      containsAll(<String>['owner-1', 'pet-1']),
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
  });

  test('宠物端不能写权威快照或管理设备', () async {
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
    expect(
        (await pet.expectType(SyncMessageTypes.pairError)).payload['message'],
        'forbidden');

    pet.send(SyncMessageTypes.devicesRequest, {});
    expect(
        (await pet.expectType(SyncMessageTypes.pairError)).payload['message'],
        'forbidden');

    pet.send(SyncMessageTypes.deviceRemove, {'deviceId': 'owner-1'});
    expect(
        (await pet.expectType(SyncMessageTypes.pairError)).payload['message'],
        'forbidden');
  });

  test('hello 不能冒充其他角色', () async {
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

    final attacker = connect();
    attacker.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'pet-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '伪装设备',
    });

    expect(
      (await attacker.expectType(SyncMessageTypes.pairError))
          .payload['message'],
      'role mismatch',
    );
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

  test('已有宠物端时拒绝第二台宠物端加入', () async {
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

    final owner = connect();
    owner.send(SyncMessageTypes.hello, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    await owner.expectType(SyncMessageTypes.helloAck);
    owner.send(SyncMessageTypes.pairCreate, {
      'householdId': householdId,
      'deviceId': 'owner-1',
      'authToken': authToken,
      'deviceName': '主人手机',
    });
    final secondCode = await owner.expectType(SyncMessageTypes.pairCreated);

    final secondPet = connect();
    secondPet.send(SyncMessageTypes.pairJoin, {
      'code': secondCode.payload['code'],
      'deviceId': 'pet-2',
      'deviceName': '卧室平板',
    });

    expect(
      (await secondPet.expectType(SyncMessageTypes.pairError))
          .payload['message'],
      '配对码无效或已过期',
    );
  });
}
