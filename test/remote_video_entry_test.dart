import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/pet_device_home.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/remote_video_call_page.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/platform/device_keep_alive.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_media_permission_coordinator.dart';
import 'package:petnote/rtc/rtc_media_permissions.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/rtc/rtc_token_client.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SyncService.instance = null;
    debugHasPetPhotoOverride = null;
    debugPetPhotoImageBuilder = null;
  });

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
  "gslb": ["https://gslb.dingrtc.com"],
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

    final firstInvite = firstTransport.sent.singleWhere(
      (message) => message.type == SyncMessageTypes.callInvite,
    );
    final firstCallId = firstInvite.payload['callId'] as String;
    expect(tokenRequests.single['channelId'], firstCallId);
    expect(firstCallId.length, lessThanOrEqualTo(64));
    expect(firstCallId, matches(RegExp(r'^[A-Za-z0-9_-]+$')));

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

    final secondInvite = secondTransport.sent.singleWhere(
      (message) => message.type == SyncMessageTypes.callInvite,
    );
    final secondCallId = secondInvite.payload['callId'] as String;
    expect(tokenRequests.last['channelId'], secondCallId);
    expect(secondCallId.length, lessThanOrEqualTo(64));
    expect(secondCallId, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
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
    final permissionCoordinator = _FakeRtcMediaPermissionCoordinator(
      state: RtcMediaPermissionState.authorized,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
            remoteVideoPermissionCoordinator: permissionCoordinator,
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
    // 连接对象固定为爱宠页当前展示的宠物。
    expect(find.text('连接对象：${store.selectedPet!.name}'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_hangup_button')),
        findsOneWidget);
  });

  testWidgets('远程视频未授权摄像头和麦克风时先弹权限提示且不直接进通话页', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final permissionCoordinator = _FakeRtcMediaPermissionCoordinator(
      state: RtcMediaPermissionState.denied,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
            remoteVideoPermissionCoordinator: permissionCoordinator,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remote_video_pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote_video_option_call')));
    await tester.pumpAndSettle();

    expect(find.text('需要开启摄像头和麦克风权限'), findsOneWidget);
    expect(find.byType(RemoteVideoCallPage), findsNothing);
    expect(permissionCoordinator.requestCount, 0);

    await tester.tap(find.text('去授权'));
    await tester.pumpAndSettle();

    expect(permissionCoordinator.requestCount, 1);
    expect(find.byType(RemoteVideoCallPage), findsNothing);
  });

  testWidgets('宠物端收到远程视频来电但未授权媒体权限时先弹权限提示且不直接进通话页', (tester) async {
    final store = PetNoteStore.seeded();
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.saveSyncPairing(
      serverUrl: 'wss://sync.example.com/ws',
      householdId: 'household-1',
      sharedKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      householdAuthToken: 'auth-token',
      servedPetId: store.selectedPet!.id,
    );
    final localDeviceId = await settings.ensureDeviceId();
    final transport = _FakeSyncTransport();
    final syncService = SyncService(
      settings: settings,
      secretStore: InMemorySyncSecretStore()
        ..saveSharedKey('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
      transportFactory: (_) => transport,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await syncService.stop();
      syncService.dispose();
      settings.dispose();
    });
    final permissionCoordinator = _FakeRtcMediaPermissionCoordinator(
      state: RtcMediaPermissionState.denied,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetDeviceHome(
          settingsController: settings,
          storeLoader: () async => store,
          syncService: syncService,
          keepAlive: _NoopDeviceKeepAlive(),
          remoteVideoPermissionCoordinator: permissionCoordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    transport.incoming.add(RtcCallInvite(
      callId: 'call-1',
      callerDeviceId: 'owner-device',
      targetDeviceId: localDeviceId,
      mode: RtcCallMode.call,
      sdp: 'offer-sdp',
    ).toSyncMessage());
    await tester.pumpAndSettle();

    expect(find.text('需要开启摄像头和麦克风权限'), findsOneWidget);
    expect(find.byType(RemoteVideoCallPage), findsNothing);
    expect(permissionCoordinator.requestCount, 0);
  });

  testWidgets('宠物端更新后安全密钥不可读仍能接收远程视频来电', (tester) async {
    final store = PetNoteStore.seeded();
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    await settings.saveSyncPairing(
      serverUrl: 'wss://sync.example.com/ws',
      householdId: 'household-1',
      sharedKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      householdAuthToken: 'auth-token',
      servedPetId: store.selectedPet!.id,
    );
    final localDeviceId = await settings.ensureDeviceId();
    final transport = _FakeSyncTransport();
    final syncService = SyncService(
      settings: settings,
      secretStore: const _UnavailableSyncSecretStore(),
      transportFactory: (_) => transport,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await syncService.stop();
      syncService.dispose();
      settings.dispose();
    });
    final permissionCoordinator = _FakeRtcMediaPermissionCoordinator(
      state: RtcMediaPermissionState.denied,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetDeviceHome(
          settingsController: settings,
          storeLoader: () async => store,
          syncService: syncService,
          keepAlive: _NoopDeviceKeepAlive(),
          remoteVideoPermissionCoordinator: permissionCoordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    transport.incoming.add(RtcCallInvite(
      callId: 'call-after-update',
      callerDeviceId: 'owner-device',
      targetDeviceId: localDeviceId,
      mode: RtcCallMode.call,
      sdp: 'offer-sdp',
    ).toSyncMessage());
    await tester.pumpAndSettle();

    expect(syncService.isActive, isTrue);
    expect(find.text('需要开启摄像头和麦克风权限'), findsOneWidget);
    expect(find.byType(RemoteVideoCallPage), findsNothing);
    expect(permissionCoordinator.requestCount, 0);
  });

  testWidgets('宠物端入口切换 settingsController 时重建同步服务避免复用旧配对',
      (tester) async {
    final oldSettings = await AppSettingsController.load();
    await oldSettings.setDeviceRole(DeviceRole.pet);
    await oldSettings.setHouseholdId('old-house');
    final oldService = SyncService(
      settings: oldSettings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => _FakeSyncTransport(),
    );
    SyncService.instance = oldService;

    final newSettings = await AppSettingsController.load();
    await newSettings.setDeviceRole(DeviceRole.pet);
    final store = PetNoteStore.seeded();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final service = SyncService.instance;
      if (service != null) {
        await service.stop();
        service.dispose();
      }
      SyncService.instance = null;
      oldSettings.dispose();
      newSettings.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetDeviceHome(
          settingsController: newSettings,
          storeLoader: () async => store,
          keepAlive: _NoopDeviceKeepAlive(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(SyncService.instance, isNot(same(oldService)));
    expect(SyncService.instance?.settings, same(newSettings));
  });

  testWidgets('远程视频只连当前宠物对应的宠物端设备', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = _fakeRtcTokenClient();

    Future<void> pumpCallPage(List<SyncedDeviceInfo> devices) async {
      adapter.calls.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPetNoteTheme(Brightness.light),
          home: RemoteVideoCallPage(
            mode: RemoteVideoMode.watch,
            pet: pet,
            devicesOverride: devices,
            userId: 'owner-device',
            signalingController: signaling,
            tokenClient: tokenClient,
            rtcAdapter: adapter,
          ),
        ),
      );
      await tester.pumpAndSettle();
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
    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
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
    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
        findsNothing);
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
    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
        findsOneWidget);
  });

  testWidgets('通话页沉浸显示并支持拖拽与交换主副画面', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
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
  "channelId": "${body['channelId']}",
  "userId": "${body['userId']}",
  "role": "${body['role']}",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://gslb.dingrtc.com"],
  "expiresAtMs": 1710003600000
}
''';
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: RemoteVideoCallPage(
          mode: RemoteVideoMode.watch,
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

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBody, isTrue);
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final annotated = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(annotated.value.statusBarColor, const Color(0x00000000));
    expect(annotated.value.systemNavigationBarColor, const Color(0x00000000));
    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having((call) => call.method, 'method',
                'SystemChrome.setEnabledSystemUIMode')
            .having((call) => call.arguments, 'arguments',
                'SystemUiMode.immersiveSticky'),
      ),
    );

    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_preview_local_view')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote_video_local_preview')));
    await tester.pump();

    expect(find.byKey(const ValueKey('remote_video_main_local_view')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_preview_remote_view')),
        findsOneWidget);

    final preview = find.byKey(const ValueKey('remote_video_local_preview'));
    final beforeDrag = tester.getTopLeft(preview);
    final gesture = await tester.startGesture(tester.getCenter(preview));
    await gesture.moveBy(const Offset(-24, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(-900, -900));
    await tester.pump();
    expect(tester.getTopLeft(preview).dx, lessThan(beforeDrag.dx));
    final draggedPastSafeEdge = tester.getTopLeft(preview);
    final mediaPadding = tester.view.padding;
    final safeLeft = mediaPadding.left / tester.view.devicePixelRatio + 18;
    final safeTop = mediaPadding.top / tester.view.devicePixelRatio + 18;
    expect(
      draggedPastSafeEdge.dx,
      lessThan(safeLeft),
    );
    expect(
      draggedPastSafeEdge.dy,
      lessThan(safeTop),
    );
    expect(draggedPastSafeEdge.dx, greaterThan(-72));
    expect(draggedPastSafeEdge.dy, greaterThan(-72));

    await gesture.up();
    await tester.pump();
    final positioned = tester.widget<AnimatedPositioned>(
      find.byKey(const ValueKey('remote_video_preview_positioned')),
    );
    expect(positioned.duration, const Duration(milliseconds: 520));
    expect(positioned.curve, Curves.elasticOut);
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(preview);
    expect(settled.dx, greaterThanOrEqualTo(safeLeft));
    expect(settled.dy, greaterThanOrEqualTo(safeTop));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having((call) => call.method, 'method',
                'SystemChrome.setEnabledSystemUIMode')
            .having((call) => call.arguments, 'arguments',
                'SystemUiMode.edgeToEdge'),
      ),
    );
  });

  testWidgets('通话页顶部优先显示宠物真实头像', (tester) async {
    final photoFile = File(
      '${Directory.systemTemp.path}/petnote-remote-video-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (photoFile.existsSync()) {
        photoFile.deleteSync();
      }
    });
    debugHasPetPhotoOverride = (path) => path == photoFile.path;
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required BoxFit fit,
      required Widget fallback,
    }) {
      return SizedBox(
        key: ValueKey('remote-video-real-photo-$photoPath'),
      );
    };
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final seedPet = store.pets.first;
    final pet = Pet(
      id: seedPet.id,
      name: seedPet.name,
      avatarText: seedPet.avatarText,
      photoPath: photoFile.path,
      type: seedPet.type,
      breed: seedPet.breed,
      sex: seedPet.sex,
      birthday: seedPet.birthday,
      ageLabel: seedPet.ageLabel,
      weightKg: seedPet.weightKg,
      neuterStatus: seedPet.neuterStatus,
      feedingPreferences: seedPet.feedingPreferences,
      allergies: seedPet.allergies,
      note: seedPet.note,
    );
    final adapter = _FakeRtcAdapter();
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
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: _fakeRtcTokenClient(),
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_pet_avatar')),
        matching:
            find.byKey(ValueKey('remote-video-real-photo-${photoFile.path}')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_pet_avatar')),
        matching: find.byIcon(Icons.pets_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('通话页无头像时保留默认爪子图标', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
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
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: _fakeRtcTokenClient(),
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_pet_avatar')),
        matching: find.byIcon(Icons.pets_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('通话成功后不显示阿里云连接成功文案', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
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
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: _fakeRtcTokenClient(),
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阿里云视频通话已连接'), findsNothing);
    expect(
      find.byKey(const ValueKey('remote_video_call_state_label')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('remote_video_elapsed_label')),
        findsOneWidget);
  });

  testWidgets('本地关闭摄像头遮罩会跟随本地画面切换', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = _fakeRtcTokenClient();

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

    expect(find.text('摄像头已关闭'), findsNothing);
    expect(find.byKey(const ValueKey('remote_video_preview_local_view')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote_video_camera_button')));
    await tester.pump();

    expect(find.text('摄像头已关闭'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_preview_local_view')),
        findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_local_preview')),
        matching: find.byKey(
          const ValueKey('remote_video_camera_off_overlay'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote_video_local_preview')));
    await tester.pump();

    expect(find.byKey(const ValueKey('remote_video_main_local_view')),
        findsNothing);
    expect(find.byKey(const ValueKey('remote_video_preview_remote_view')),
        findsOneWidget);
    expect(find.text('摄像头已关闭'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_local_preview')),
        matching: find.byKey(
          const ValueKey('remote_video_camera_off_overlay'),
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_main_surface')),
        matching: find.byKey(
          const ValueKey('remote_video_camera_off_overlay'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('remote_video_camera_button')));
    await tester.pump();

    expect(find.text('摄像头已关闭'), findsNothing);
    expect(transport.sent.last.type, SyncMessageTypes.callMediaState);
    expect(transport.sent.last.payload['cameraEnabled'], isTrue);
    expect(adapter.calls.where((call) => call == 'toggleCamera:false'),
        hasLength(1));
    expect(adapter.calls.where((call) => call == 'toggleCamera:true'),
        hasLength(2));
  });

  testWidgets('远端关闭摄像头时遮罩跟随远端画面而不是显示黑屏', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = _fakeRtcTokenClient();

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

    transport.incoming.add(const RtcCallMediaState(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
      cameraEnabled: false,
    ).toSyncMessage());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('remote_video_main_remote_view')),
        findsNothing);
    expect(find.text('摄像头已关闭'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_main_surface')),
        matching: find.byKey(const ValueKey('remote_video_camera_off_overlay')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('remote_video_local_preview')));
    await tester.pump();

    expect(find.byKey(const ValueKey('remote_video_main_local_view')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('remote_video_preview_remote_view')),
        findsNothing);
    expect(find.text('摄像头已关闭'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('remote_video_local_preview')),
        matching: find.byKey(const ValueKey('remote_video_camera_off_overlay')),
      ),
      findsOneWidget,
    );

    transport.incoming.add(const RtcCallMediaState(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
      cameraEnabled: true,
    ).toSyncMessage());
    await tester.pump();
    await tester.pump();

    expect(find.text('摄像头已关闭'), findsNothing);
    expect(find.byKey(const ValueKey('remote_video_preview_remote_view')),
        findsOneWidget);
  });

  testWidgets('应用恢复前台后会重新同步本端摄像头状态', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = _fakeRtcTokenClient();

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
    transport.sent.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.type, SyncMessageTypes.callMediaState);
    expect(transport.sent.single.payload['cameraEnabled'], isTrue);
    expect(transport.sent.single.payload['targetDeviceId'], 'pet-device');
  });

  testWidgets('远程视频挂断会发送 call_end 信令', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final adapter = _FakeRtcAdapter();
    final tokenClient = _fakeRtcTokenClient();
    final pet = store.pets.first;

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
    expect(transport.sent.map((message) => message.type), [
      SyncMessageTypes.callInvite,
      SyncMessageTypes.callMediaState,
    ]);
    transport.sent.clear();

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
  "gslb": ["https://gslb.dingrtc.com"],
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
    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
    ]);
    expect(adapter.joinedConfig?.appId, 'nml2ycrp');
    expect(adapter.joinedConfig?.channelId, 'call-1');
    expect(adapter.joinedConfig?.userId, 'owner-device');
    expect(adapter.joinedConfig?.remoteUserId, 'pet-device');
    expect(adapter.joinedConfig?.token, 'signed-token');
    expect(adapter.joinedConfig?.singleToken, 'single-token');
    expect(transport.sent, hasLength(2));
    expect(transport.sent.first.type, SyncMessageTypes.callInvite);
    expect(transport.sent.first.payload['callId'], 'call-1');
    expect(transport.sent.first.payload['callerDeviceId'], 'owner-device');
    expect(transport.sent.first.payload['targetDeviceId'], 'pet-device');
    expect(transport.sent.last.type, SyncMessageTypes.callMediaState);
    expect(transport.sent.last.payload['cameraEnabled'], isTrue);

    await tester.tap(find.byKey(const ValueKey('remote_video_hangup_button')));
    await tester.pumpAndSettle();

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
      'leave',
      'dispose',
    ]);
    expect(transport.sent, hasLength(3));
    expect(transport.sent.last.type, SyncMessageTypes.callEnd);
  });

  testWidgets('远程视频设备目录为空时会先请求设备列表再入会', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('auth-token');
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    await settings.setSharedKeyBase64(await crypto.exportKeyBase64());
    final serviceTransport = _FakeSyncTransport();
    final service = SyncService(
      settings: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => serviceTransport,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await service.stop();
      service.dispose();
      SyncService.instance = null;
      settings.dispose();
    });
    SyncService.instance = service;
    await service.ensureStartedForOwner(
      store: store,
      pushStartupSnapshot: false,
    );
    serviceTransport.sent.clear();

    final pet = store.pets.first;
    final tokenRequests = <Map<String, dynamic>>[];
    final adapter = _FakeRtcAdapter();
    final signaling = RtcSignalingController(transport: serviceTransport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        tokenRequests.add(body);
        return '''
{
  "appId": "nml2ycrp",
  "channelId": "call-1",
  "userId": "${body['userId']}",
  "role": "${body['role']}",
  "token": "signed-token",
  "singleToken": "single-token",
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://gslb.dingrtc.com"],
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
          userId: 'owner-device',
          signalingController: signaling,
          tokenClient: tokenClient,
          rtcAdapter: adapter,
        ),
      ),
    );
    await tester.pump();

    expect(serviceTransport.sent.map((message) => message.type),
        contains(SyncMessageTypes.devicesRequest));
    expect(tokenRequests, isEmpty);

    serviceTransport.incoming.add(
      SyncMessage(SyncMessageTypes.devices, {
        'devices': [
          SyncedDeviceInfo(
            deviceId: 'pet-device',
            name: '客厅平板',
            role: 'pet',
            servedPetId: pet.id,
            online: true,
          ).toJson(),
        ],
      }),
    );
    await tester.pumpAndSettle();

    expect(tokenRequests, hasLength(1));
    expect(adapter.joinedConfig?.remoteUserId, 'pet-device');
    final invite = serviceTransport.sent.singleWhere(
      (message) => message.type == SyncMessageTypes.callInvite,
    );
    expect(invite.payload['targetDeviceId'], 'pet-device');
  });

  testWidgets('远程视频请求 Token 时携带恢复后的家庭认证', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final tokenRequests = <Map<String, dynamic>>[];
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.owner);
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('ws://127.0.0.1/ws');
    await settings.setHouseholdId('house-1');
    await settings.setHouseholdAuthToken('restored-auth-token');
    final service = SyncService(
      settings: settings,
      secretStore: InMemorySyncSecretStore(),
      transportFactory: (_) => _FakeSyncTransport(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await service.stop();
      service.dispose();
      SyncService.instance = null;
      settings.dispose();
    });
    SyncService.instance = service;
    final pet = store.pets.first;
    final adapter = _FakeRtcAdapter();
    final transport = _FakeSyncTransport();
    final signaling = RtcSignalingController(transport: transport);
    addTearDown(signaling.dispose);
    final tokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
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
  "gslb": ["https://gslb.dingrtc.com"],
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

    expect(tokenRequests.single['householdId'], 'house-1');
    expect(tokenRequests.single['authToken'], 'restored-auth-token');
    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
    ]);
  });

  testWidgets('通话控制按钮会真实调用 RTC 适配器', (tester) async {
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
  "gslb": ["https://gslb.dingrtc.com"],
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

    await tester.tap(find.byKey(const ValueKey('remote_video_mic_button')));
    await tester.tap(find.byKey(const ValueKey('remote_video_speaker_button')));
    await tester.tap(find.byKey(const ValueKey('remote_video_camera_button')));
    await tester
        .tap(find.byKey(const ValueKey('remote_video_switch_camera_button')));
    await tester.pump();

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
      'toggleMicrophone:false',
      'toggleSpeaker:false',
      'toggleCamera:false',
      'switchCamera',
    ]);
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
  "gslb": ["https://gslb.dingrtc.com"],
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

    expect(adapter.calls, [
      'initialize',
      'join',
      'dispose',
      'initialize',
      'join',
      'dispose',
    ]);
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
  "gslb": ["https://gslb.dingrtc.com"],
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

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
    ]);
    expect(transport.sent.map((message) => message.type), [
      SyncMessageTypes.callMediaState,
    ]);
    expect(transport.sent.single.payload['cameraEnabled'], isTrue);
    transport.sent.clear();

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
  "gslb": ["https://gslb.dingrtc.com"],
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
    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
    ]);

    transport.incoming.add(const RtcCallEnd(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
    ).toSyncMessage());
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
      'leave',
      'dispose',
    ]);
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
  "gslb": ["https://gslb.dingrtc.com"],
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

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
    ]);

    final endMessage = const RtcCallEnd(
      callId: 'call-1',
      targetDeviceId: 'owner-device',
    ).toSyncMessage();
    transport.incoming.add(endMessage);
    transport.incoming.add(endMessage);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(adapter.calls, [
      'initialize',
      'join',
      'toggleMicrophone:true',
      'toggleSpeaker:true',
      'toggleCamera:true',
      'leave',
      'dispose',
    ]);
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

RtcTokenClient _fakeRtcTokenClient() {
  return RtcTokenClient(
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
  "nonce": "AK-test-nonce",
  "timestamp": 1710003600,
  "gslb": ["https://gslb.dingrtc.com"],
  "expiresAtMs": 1710003600000
}
''';
    },
  );
}

class _UnavailableSyncSecretStore implements SyncSecretStore {
  const _UnavailableSyncSecretStore();

  @override
  Future<void> deleteSharedKey() async {}

  @override
  Future<String?> loadSharedKey() async {
    throw const SyncSecretStoreException('secure storage unavailable');
  }

  @override
  Future<void> saveSharedKey(String keyBase64) async {}
}

class _NoopDeviceKeepAlive extends DeviceKeepAlive {
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> startBackgroundKeepAlive() async {}

  @override
  Future<void> stopBackgroundKeepAlive() async {}
}

class _FakeRtcAdapter implements RtcAdapter {
  final List<String> calls = <String>[];
  RtcJoinConfig? joinedConfig;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  Future<RtcMediaPermissionState> getMediaPermissionState() async {
    return RtcMediaPermissionState.authorized;
  }

  @override
  Future<PermissionRequestOutcome<RtcMediaPermissionState>>
      requestMediaPermission() async {
    return const PermissionRequestOutcome<RtcMediaPermissionState>(
      state: RtcMediaPermissionState.authorized,
    );
  }

  @override
  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings() async {
    return RtcMediaSettingsOpenResult.opened;
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
  Future<RtcMediaPermissionState> getMediaPermissionState() async {
    return RtcMediaPermissionState.authorized;
  }

  @override
  Future<PermissionRequestOutcome<RtcMediaPermissionState>>
      requestMediaPermission() async {
    return const PermissionRequestOutcome<RtcMediaPermissionState>(
      state: RtcMediaPermissionState.authorized,
    );
  }

  @override
  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings() async {
    return RtcMediaSettingsOpenResult.opened;
  }

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

class _FakeRtcMediaPermissionCoordinator
    implements RtcMediaPermissionCoordinator {
  _FakeRtcMediaPermissionCoordinator({
    required this.state,
  });

  @override
  RtcMediaPermissionState state;

  @override
  bool hasHandledPermissionPrompt = false;

  int requestCount = 0;

  @override
  bool get hasGrantedPermission => state == RtcMediaPermissionState.authorized;

  @override
  bool get isInitialized => true;

  @override
  bool get shouldOpenSettingsForPermissionRequest =>
      !hasGrantedPermission && hasHandledPermissionPrompt;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshPlatformState() async {}

  @override
  Future<RtcMediaPermissionState> requestPermission() async {
    requestCount += 1;
    return state;
  }

  @override
  Future<RtcMediaSettingsOpenResult> openMediaPermissionSettings() async {
    return RtcMediaSettingsOpenResult.opened;
  }
}
