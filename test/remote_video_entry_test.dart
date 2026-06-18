import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/remote_video_call_page.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/rtc/rtc_token_client.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RTC Token 地址从同步服务器地址推导', () {
    expect(
      rtcTokenBaseUriFromSyncServerUrl('wss://petnote.example.com/ws')
          .toString(),
      'https://petnote.example.com/',
    );
    expect(
      rtcTokenBaseUriFromSyncServerUrl('ws://127.0.0.1:8787/ws').toString(),
      'http://127.0.0.1:8787/',
    );
    expect(rtcTokenBaseUriFromSyncServerUrl(null), isNull);
  });

  testWidgets('默认 callId 每次新通话唯一且单通话内一致', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final tokenRequests = <Map<String, dynamic>>[];
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        tokenRequests.add(body);
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "${body['channelId']}",
  "userId": "${body['userId']}",
  "role": "${body['role']}",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    final firstAdapter = _FakeRtcAdapter();
    final firstTransport = _FakeSyncTransport();
    final firstSignaling = RtcSignalingController(transport: firstTransport);
    addTearDown(firstSignaling.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          key: UniqueKey(),
          mode: RemoteVideoMode.call,
          pet: pet,
          targetDeviceId: 'pet-device',
          userId: 'owner-device',
          signalingController: firstSignaling,
          tokenClient: tokenClient,
          rtcAdapter: firstAdapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstCallId = firstTransport.sent.single.payload['callId'] as String;
    expect(tokenRequests.single['channelId'], firstCallId);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final secondAdapter = _FakeRtcAdapter();
    final secondTransport = _FakeSyncTransport();
    final secondSignaling = RtcSignalingController(transport: secondTransport);
    addTearDown(secondSignaling.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          key: UniqueKey(),
          mode: RemoteVideoMode.call,
          pet: pet,
          targetDeviceId: 'pet-device',
          userId: 'owner-device',
          signalingController: secondSignaling,
          tokenClient: tokenClient,
          rtcAdapter: secondAdapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final secondCallId =
        secondTransport.sent.single.payload['callId'] as String;
    expect(tokenRequests.last['channelId'], secondCallId);
    expect(secondCallId, isNot(firstCallId));
  });

  testWidgets('无宠物时爱宠页不显示远程视频入口', (tester) async {
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('remote_video_pill')), findsNothing);
  });

  testWidgets('爱宠页远程视频入口弹出两个选项并进入通话页', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );

    final pill = find.byKey(const ValueKey('remote_video_pill'));
    expect(pill, findsOneWidget);

    await tester.tap(pill);
    await tester.pumpAndSettle();

    expect(find.text('视频通话'), findsOneWidget);
    expect(find.text('先看看它'), findsOneWidget);

    await tester.tap(find.text('先看看它'));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteVideoCallPage), findsOneWidget);
    expect(find.text('先看看它'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_status_label')),
        findsOneWidget);
    // 连接对象固定为爱宠页当前展示的宠物。
    expect(find.text('连接对象：${store.selectedPet!.name}'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_hangup_button')),
        findsOneWidget);
  });

  testWidgets('远程视频只连当前宠物对应的宠物端设备', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;

    Future<void> pumpCallPage(List<SyncedDeviceInfo> devices) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPetNoteTheme(Brightness.light),
          home: RemoteVideoCallPage(
            mode: RemoteVideoMode.watch,
            pet: pet,
            devicesOverride: devices,
          ),
        ),
      );
    }

    // 指派给当前宠物的设备：可连。
    await pumpCallPage([
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        servedPetId: pet.id,
        online: true,
      ),
    ]);
    expect(find.byKey(const ValueKey('remote_video_status_label')),
        findsOneWidget);

    // 指派给其他宠物的设备：不可连。
    await pumpCallPage(const [
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        servedPetId: 'other-pet',
        online: true,
      ),
    ]);
    expect(find.byKey(const ValueKey('remote_video_status_label')),
        findsOneWidget);

    // 未指派宠物的设备：视为可服务当前宠物。
    await pumpCallPage(const [
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        online: false,
      ),
    ]);
    expect(find.byKey(const ValueKey('remote_video_status_label')),
        findsOneWidget);
  });

  testWidgets('远程视频挂断会发送 call_end 信令', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final pet = store.pets.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.call,
          pet: pet,
          callId: 'call-1',
          targetDeviceId: 'pet-device',
          signalingController: signaling,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remote_video_hangup_button')));
    await tester.pumpAndSettle();

    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.type, SyncMessageTypes.callEnd);
    expect(transport.sent.single.payload['callId'], 'call-1');
    expect(transport.sent.single.payload['targetDeviceId'], 'pet-device');
  });

  testWidgets('远程视频进页会请求 Token 并加入 RTC 房间，挂断释放原生资源', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final tokenRequests = <Map<String, dynamic>>[];
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        expect(uri.toString(), 'https://sync.example.com/rtc/token');
        tokenRequests.add(body);
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "call-1",
  "userId": "owner-device",
  "role": "publisher",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.call,
          pet: pet,
          callId: 'call-1',
          targetDeviceId: 'pet-device',
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: tokenClient,
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tokenRequests, [
      {
        'channelId': 'call-1',
        'userId': 'owner-device',
        'role': 'publisher',
      }
    ]);
    expect(adapter.calls, ['initialize', 'join']);
    expect(adapter.joinedConfig?.appId, 'nml2ycrp');
    expect(adapter.joinedConfig?.channelId, 'call-1');
    expect(adapter.joinedConfig?.userId, 'owner-device');
    expect(adapter.joinedConfig?.token, 'signed-token');
    expect(adapter.joinedConfig?.singleToken, 'single-token');
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.type, SyncMessageTypes.callInvite);
    expect(transport.sent.single.payload['callId'], 'call-1');
    expect(transport.sent.single.payload['callerDeviceId'], 'owner-device');
    expect(transport.sent.single.payload['targetDeviceId'], 'pet-device');

    await tester.tap(find.byKey(const ValueKey('remote_video_hangup_button')));
    await tester.pumpAndSettle();

    expect(adapter.calls, ['initialize', 'join', 'leave', 'dispose']);
    expect(transport.sent, hasLength(2));
    expect(transport.sent.last.type, SyncMessageTypes.callEnd);
  });

  testWidgets('缺少通话依赖时会明确显示不可用状态', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.call,
          pet: pet,
          callId: 'call-1',
          targetDeviceId: 'pet-device',
          tokenClient: null,
          signalingController: signaling,
          rtcAdapter: const _NoopRtcAdapter(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusText = tester.widget<Text>(
      find.byKey(const ValueKey('remote_video_status_label')),
    );
    expect(statusText.data, '通话不可用');

    await tester.tap(find.byKey(const ValueKey('remote_video_hangup_button')));
    await tester.pumpAndSettle();

    expect(transport.sent, isEmpty);
  });

  testWidgets('连接失败后控制按钮不会调用已释放 RTC 资源', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FailingJoinRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "${body['channelId']}",
  "userId": "${body['userId']}",
  "role": "${body['role']}",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.call,
          pet: pet,
          callId: 'call-1',
          targetDeviceId: 'pet-device',
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: tokenClient,
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.calls, ['initialize', 'join', 'dispose']);
    final statusText = tester.widget<Text>(
      find.byKey(const ValueKey('remote_video_status_label')),
    );
    expect(statusText.data, '连接失败');

    await tester.tap(find.byKey(const ValueKey('remote_video_mic_button')));
    await tester.tap(find.byKey(const ValueKey('remote_video_speaker_button')));
    await tester.tap(find.byKey(const ValueKey('remote_video_camera_button')));
    await tester.pump();

    expect(adapter.calls, ['initialize', 'join', 'dispose']);
  });

  testWidgets('宠物端被叫进页自动入房但不反向发送 call_invite', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "call-1",
  "userId": "pet-device",
  "role": "publisher",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.call,
          pet: pet,
          callId: 'call-1',
          targetDeviceId: 'owner-device',
          userId: 'pet-device',
          signalingController: signaling,
          tokenClient: tokenClient,
          rtcAdapter: adapter,
          sendInviteOnJoin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.calls, ['initialize', 'join']);
    expect(transport.sent, isEmpty);

    await tester.tap(find.byKey(const ValueKey('remote_video_hangup_button')));
    await tester.pumpAndSettle();

    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.type, SyncMessageTypes.callEnd);
    expect(transport.sent.single.payload['targetDeviceId'], 'owner-device');
  });

  testWidgets('收到远端 call_end 会离会释放并返回上一页', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "call-1",
  "userId": "owner-device",
  "role": "publisher",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RemoteVideoCallPage(
                  mode: RemoteVideoMode.call,
                  pet: pet,
                  callId: 'call-1',
                  targetDeviceId: 'pet-device',
                  userId: 'owner-device',
                  signalingController: signaling,
                  tokenClient: tokenClient,
                  rtcAdapter: adapter,
                ),
              ));
            },
            child: const Text('打开通话'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开通话'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(RemoteVideoCallPage), findsOneWidget);
    expect(adapter.calls, ['initialize', 'join']);

    transport.incoming.add(const RtcCallEnd(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
    ).toSyncMessage());
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(adapter.calls, ['initialize', 'join', 'leave', 'dispose']);
    expect(find.byType(RemoteVideoCallPage), findsNothing);
  });

  testWidgets('重复收到远端 call_end 只释放一次 RTC 资源', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "call-1",
  "userId": "owner-device",
  "role": "publisher",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://rgslb.rtc.aliyuncs.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RemoteVideoCallPage(
                  mode: RemoteVideoMode.call,
                  pet: pet,
                  callId: 'call-1',
                  targetDeviceId: 'pet-device',
                  userId: 'owner-device',
                  signalingController: signaling,
                  tokenClient: tokenClient,
                  rtcAdapter: adapter,
                ),
              ));
            },
            child: const Text('打开通话'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开通话'));
    await tester.pump();
    await tester.pump();

    expect(adapter.calls, ['initialize', 'join']);

    final endMessage = const RtcCallEnd(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
    ).toSyncMessage();
    transport.incoming.add(endMessage);
    transport.incoming.add(endMessage);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(adapter.calls, ['initialize', 'join', 'leave', 'dispose']);
  });
}

class _FakeSyncTransport implements SyncTransport {
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();
  final ValueNotifier<SyncConnectionState> stateNotifier =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connected);
  final List<SyncMessage> sent = <SyncMessage>[];

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  ValueListenable<SyncConnectionState> get state => stateNotifier;

  @override
  Future<void> connect() async {}

  @override
  void send(SyncMessage message) => sent.add(message);

  @override
  Future<void> disconnect() async {}
}

class _FakeRtcAdapter implements RtcAdapter {
  final List<String> calls = <String>[];
  RtcJoinConfig? joinedConfig;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  Future<void> join(RtcJoinConfig config) async {
    calls.add('join');
    joinedConfig = config;
  }

  @override
  Future<void> leave() async {
    calls.add('leave');
  }

  @override
  Future<void> toggleCamera({required bool enabled}) async {
    calls.add('toggleCamera:$enabled');
  }

  @override
  Future<void> toggleMicrophone({required bool enabled}) async {
    calls.add('toggleMicrophone:$enabled');
  }

  @override
  Future<void> toggleSpeaker({required bool enabled}) async {
    calls.add('toggleSpeaker:$enabled');
  }

  @override
  Future<void> switchCamera() async {
    calls.add('switchCamera');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

class _FailingJoinRtcAdapter extends _FakeRtcAdapter {
  @override
  Future<void> join(RtcJoinConfig config) async {
    calls.add('join');
    throw StateError('join failed');
  }
}

class _NoopRtcAdapter implements RtcAdapter {
  const _NoopRtcAdapter();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> join(RtcJoinConfig config) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> toggleCamera({required bool enabled}) async {}

  @override
  Future<void> toggleMicrophone({required bool enabled}) async {}

  @override
  Future<void> toggleSpeaker({required bool enabled}) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {}
}
