import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncService.instance = null;
  });

  tearDown(() async {
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
    await SyncService.instance?.stop();
    SyncService.instance = null;
  });

  testWidgets('未选择服务宠物时展示宠物选择列表', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    String? selectedPetId;
    var openedSettings = false;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (value) => selectedPetId = value,
          onMarkDone: (_) {},
          onOpenSettings: () => openedSettings = true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pet_selector_hero')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pet_selector_list_panel')), findsOneWidget);
    expect(find.text('这台设备照顾谁？'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('选择后会进入常亮中枢屏，只展示它的状态和待办。'), findsNothing);
    expect(find.text('稍后可在设置中重新选择'), findsNothing);

    final cardInk = tester.widget<Ink>(
      find.descendant(
        of: find.byKey(ValueKey('dashboard_select_pet_${store.pets.first.id}')),
        matching: find.byType(Ink),
      ),
    );
    final cardDecoration = cardInk.decoration as BoxDecoration;
    expect(cardDecoration.boxShadow, anyOf(isNull, isEmpty));

    final pet = store.pets.first;
    await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
    await tester.pump();
    expect(selectedPetId, pet.id);

    await tester.tap(find.byIcon(Icons.settings_rounded).first);
    await tester.pump();
    expect(openedSettings, isTrue);
  });

  testWidgets('宠物端选择列表页时钟保持分钟刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var now = DateTime(2026, 6, 22, 9, 58);
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
          nowProvider: () => now,
        ),
      ),
    );

    expect(find.text('09:58'), findsOneWidget);

    now = DateTime(2026, 6, 22, 9, 59, 1);
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('09:59'), findsOneWidget);
    expect(find.text('09:58'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('宠物端选择列表页恢复前台时立即刷新时钟', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var now = DateTime(2026, 6, 22, 9, 58);
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
          nowProvider: () => now,
        ),
      ),
    );

    expect(find.text('09:58'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = DateTime(2026, 6, 22, 10, 2, 15);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('10:02'), findsOneWidget);
    expect(find.text('09:58'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('横屏下服务宠物选择页使用中枢式分栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    String? selectedPetId;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (value) => selectedPetId = value,
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('pet_selector_side_panel')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pet_selector_list_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('pet_selector_app_logo_box')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pet_selector_brand_header')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pet_selector_status_card')),
        matching: find.text('宠记'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pet_selector_status_card')),
        matching: find.text('PetNote'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pet_selector_status_card')),
        matching: find.text('宠物日常关怀记录App'),
      ),
      findsOneWidget,
    );
    expect(find.text('选择服务宠物'), findsNothing);
    expect(find.text('这台设备照顾谁？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pet_selector_list_panel')),
        matching: find.text('这台设备照顾谁？'),
      ),
      findsNothing,
    );
    expect(find.text('2 只可服务'), findsNothing);
    expect(find.text('横放设备时，左侧保留状态和设置，右侧留给宠物选择。'), findsNothing);
    expect(find.text('选择后进入常亮中枢屏'), findsNothing);
    expect(find.text('点击一张宠物卡片即可接管对应待办和观察状态。'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    final sidePanelSize = tester.getSize(
      find.byKey(const ValueKey('pet_selector_side_panel')),
    );
    final listPanelSize = tester.getSize(
      find.byKey(const ValueKey('pet_selector_list_panel')),
    );
    expect(sidePanelSize.width / listPanelSize.width, closeTo(3 / 7, 0.02));

    final pet = store.pets.first;
    await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
    await tester.pump();
    expect(selectedPetId, pet.id);
  });

  testWidgets('横屏选择页在多尺寸下保持布局完整', (tester) async {
    final sizes = <Size>[
      const Size(720, 390),
      const Size(900, 520),
      const Size(1180, 620),
    ];

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      final store = PetNoteStore.seeded();
      String? selectedPetId;

      await tester.pumpWidget(
        _wrapDashboard(
          PetDeviceDashboard(
            store: store,
            servedPetId: null,
            syncStatusLabel: '同步中...',
            pendingItemKeys: const <String>{},
            onSelectServedPet: (value) => selectedPetId = value,
            onMarkDone: (_) {},
            onOpenSettings: () {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pet_selector_side_panel')),
          findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      final sidePanelRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_side_panel')),
      );
      final listPanelRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_list_panel')),
      );
      final statusCardRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_status_card')),
      );
      final logoRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_app_logo_box')),
      );
      final brandHeaderRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_brand_header')),
      );
      final brandTaglineRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pet_selector_brand_header')),
          matching: find.text('宠物日常关怀记录App'),
        ),
      );
      expect(sidePanelRect.left, greaterThanOrEqualTo(0));
      expect(listPanelRect.right, lessThanOrEqualTo(size.width));
      expect(sidePanelRect.right, lessThan(listPanelRect.left));
      expect(
          brandHeaderRect.left, greaterThanOrEqualTo(statusCardRect.left + 8));
      expect(brandHeaderRect.top, greaterThanOrEqualTo(statusCardRect.top + 8));
      expect(
        brandHeaderRect.right,
        lessThanOrEqualTo(statusCardRect.right - 8),
      );
      expect(
        brandHeaderRect.bottom,
        lessThanOrEqualTo(statusCardRect.bottom - 8),
      );
      expect(logoRect.left, greaterThanOrEqualTo(statusCardRect.left + 8));
      expect(logoRect.top, greaterThanOrEqualTo(statusCardRect.top + 8));
      expect(logoRect.right, lessThanOrEqualTo(statusCardRect.right - 8));
      expect(logoRect.bottom, lessThanOrEqualTo(statusCardRect.bottom - 8));
      final syncPillRect = tester.getRect(find.text('同步中...'));
      expect(syncPillRect.left, greaterThanOrEqualTo(statusCardRect.left + 8));
      expect(syncPillRect.right, lessThanOrEqualTo(statusCardRect.right - 8));
      expect(syncPillRect.bottom, lessThanOrEqualTo(statusCardRect.bottom - 8));
      final titleRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pet_selector_status_card')),
          matching: find.text('这台设备照顾谁？'),
        ),
      );
      expect(titleRect.left, greaterThanOrEqualTo(statusCardRect.left + 8));
      expect(titleRect.right, lessThanOrEqualTo(statusCardRect.right - 8));
      expect(logoRect.top, greaterThanOrEqualTo(brandHeaderRect.top));
      expect(logoRect.bottom, lessThan(brandHeaderRect.bottom));
      expect(
          brandTaglineRect.right, lessThanOrEqualTo(statusCardRect.right - 8));
      expect(
          brandTaglineRect.bottom, lessThanOrEqualTo(brandHeaderRect.bottom));
      expect(brandHeaderRect.bottom, lessThan(titleRect.top));
      expect(titleRect.bottom, lessThan(syncPillRect.top));
      expect(find.text('选择服务宠物'), findsNothing);
      expect(find.text('${store.pets.length} 只可服务'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pet_selector_list_panel')),
          matching: find.text('这台设备照顾谁？'),
        ),
        findsNothing,
      );

      final pet = store.pets.first;
      await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
      await tester.pump();
      expect(selectedPetId, pet.id);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('横屏选择页左侧 App 图标跟随深浅色模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpDashboard(Brightness brightness) async {
      final store = PetNoteStore.seeded();
      await tester.pumpWidget(
        _wrapDashboard(
          PetDeviceDashboard(
            store: store,
            servedPetId: null,
            syncStatusLabel: '已连接',
            pendingItemKeys: const <String>{},
            onSelectServedPet: (_) {},
            onMarkDone: (_) {},
            onOpenSettings: () {},
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpDashboard(Brightness.light);
    final lightLogo = tester.widget<Container>(
      find.byKey(const ValueKey('pet_selector_app_logo_box')),
    );
    final lightDecoration = lightLogo.decoration as BoxDecoration;
    expect(lightDecoration.color, Colors.white);
    expect(lightDecoration.boxShadow?.single.blurRadius, 16);
    expect(lightDecoration.boxShadow?.single.offset, const Offset(0, 5));
    expect(
      tester
          .widget<SvgPicture>(
            find.descendant(
              of: find.byKey(const ValueKey('pet_selector_app_logo_box')),
              matching: find.byType(SvgPicture),
            ),
          )
          .colorFilter,
      isNull,
    );

    await pumpDashboard(Brightness.dark);
    final darkLogo = tester.widget<Container>(
      find.byKey(const ValueKey('pet_selector_app_logo_box')),
    );
    final darkDecoration = darkLogo.decoration as BoxDecoration;
    expect(darkDecoration.color, const Color(0xFF111111));
    expect(darkDecoration.boxShadow?.single.blurRadius, 16);
    expect(darkDecoration.boxShadow?.single.offset, const Offset(0, 5));
    expect(
      tester
          .widget<SvgPicture>(
            find.descendant(
              of: find.byKey(const ValueKey('pet_selector_app_logo_box')),
              matching: find.byType(SvgPicture),
            ),
          )
          .colorFilter,
      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
  });

  testWidgets('横屏选择页长文案不破坏布局', (tester) async {
    final sizes = <Size>[
      const Size(720, 390),
      const Size(900, 520),
      const Size(1180, 620),
    ];

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      final store = await PetNoteStore.load(
        storage: PetNoteLocalStorage.memory(),
      );
      await store.addPet(
        name: '名字特别特别长的强强同学',
        type: PetType.dog,
        breed: '非常长的法国斗牛犬混合品种名称',
        sex: '弟弟',
        birthday: '2025-01-01',
        weightKg: 8,
        neuterStatus: PetNeuterStatus.unknown,
        feedingPreferences: '少食多餐',
        allergies: '无',
        note: '横屏长文案压测',
      );
      String? selectedPetId;

      await tester.pumpWidget(
        _wrapDashboard(
          PetDeviceDashboard(
            store: store,
            servedPetId: null,
            syncStatusLabel: '同步中，请保持设备在线',
            pendingItemKeys: const <String>{},
            onSelectServedPet: (value) => selectedPetId = value,
            onMarkDone: (_) {},
            onOpenSettings: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final sidePanelRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_side_panel')),
      );
      final listPanelRect = tester.getRect(
        find.byKey(const ValueKey('pet_selector_list_panel')),
      );
      expect(sidePanelRect.left, greaterThanOrEqualTo(0));
      expect(listPanelRect.right, lessThanOrEqualTo(size.width));
      expect(sidePanelRect.right, lessThan(listPanelRect.left));
      final syncPillRect = tester.getRect(find.text('同步中，请保持设备在线'));
      expect(syncPillRect.left, greaterThanOrEqualTo(sidePanelRect.left + 8));
      expect(syncPillRect.right, lessThanOrEqualTo(sidePanelRect.right - 8));
      final titleRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pet_selector_status_card')),
          matching: find.text('这台设备照顾谁？'),
        ),
      );
      expect(titleRect.left, greaterThanOrEqualTo(sidePanelRect.left + 8));
      expect(titleRect.right, lessThanOrEqualTo(sidePanelRect.right - 8));
      final petCardRect = tester.getRect(
        find.byKey(ValueKey('dashboard_select_pet_${store.pets.first.id}')),
      );
      expect(petCardRect.left, greaterThanOrEqualTo(listPanelRect.left + 8));
      expect(petCardRect.right, lessThanOrEqualTo(listPanelRect.right - 8));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

      final pet = store.pets.first;
      await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
      await tester.pump();
      expect(selectedPetId, pet.id);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('服务宠物选择页显示同步后的真实头像', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final photoFile = File(
      '${Directory.systemTemp.path}/petnote-selector-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
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
        key: ValueKey('selector-real-photo-$photoPath'),
      );
    };
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await store.addPet(
      name: '强',
      type: PetType.dog,
      photoPath: photoFile.path,
      breed: '法斗',
      sex: '弟弟',
      birthday: '2025-01-01',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '同步头像',
    );

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.byKey(ValueKey('selector-real-photo-${photoFile.path}')),
        findsOneWidget);
  });

  testWidgets('看板展示同步状态并把待办完成动作回调给上层', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '测试喂饭',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;
    PetAction? action;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (value) => action = value,
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text(pet.name), findsWidgets);
    expect(find.text('已连接'), findsOneWidget);
    final petCard = find.byKey(const ValueKey('pet_dashboard_pet_card'));
    expect(
      find.descendant(of: petCard, matching: find.text('已连接')),
      findsNothing,
    );
    expect(find.text(firstItem.title), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
    await tester.pump();

    expect(action?.kind, PetActionKind.markDone);
    expect(action?.sourceType, firstItem.sourceType);
  });

  testWidgets('点击宠物待办页头像返回宠物选择列表', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;
    String? selectedPetId = pet.id;

    Widget dashboard() => _wrapDashboard(
          PetDeviceDashboard(
            store: store,
            servedPetId: selectedPetId,
            syncStatusLabel: '已连接',
            pendingItemKeys: const <String>{},
            onSelectServedPet: (value) => selectedPetId = value,
            onMarkDone: (_) {},
            onOpenSettings: () {},
          ),
        );

    await tester.pumpWidget(dashboard());
    expect(
        find.byKey(const ValueKey('pet_dashboard_pet_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('pet_selector_list_panel')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('pet_dashboard_avatar_return_selection')),
    );
    await tester.pumpWidget(dashboard());

    expect(selectedPetId, isNull);
    expect(
        find.byKey(const ValueKey('pet_selector_list_panel')), findsOneWidget);
  });

  testWidgets('宠物端看板详情页时钟保持分钟刷新', (tester) async {
    var now = DateTime(2026, 6, 22, 21, 5);
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
          nowProvider: () => now,
        ),
      ),
    );

    expect(find.text('21:05'), findsOneWidget);

    now = DateTime(2026, 6, 22, 21, 6, 1);
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('21:06'), findsOneWidget);
    expect(find.text('21:05'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('宠物端看板详情页恢复前台时立即刷新时钟', (tester) async {
    var now = DateTime(2026, 6, 22, 21, 5);
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
          nowProvider: () => now,
        ),
      ),
    );

    expect(find.text('21:05'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = DateTime(2026, 6, 22, 21, 9, 30);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('21:09'), findsOneWidget);
    expect(find.text('21:05'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('深色模式下宠物端看板使用主题文字和监控面板', (tester) async {
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
        brightness: Brightness.dark,
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, darkPetNoteTokens.pageGradientTop);

    final title = tester.widget<Text>(find.text(pet.name));
    expect(title.style?.color, darkPetNoteTokens.primaryText);
    expect(
      find.byKey(const ValueKey('pet_dashboard_pet_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pet_dashboard_todo_panel')),
      findsOneWidget,
    );
    expect(find.text('下一件事'), findsWidgets);
  });

  testWidgets('横屏下宠物端看板保留头像状态区和待办主区域', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '横屏喂食',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pet_dashboard_pet_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pet_dashboard_todo_panel')),
      findsOneWidget,
    );
    expect(find.text('已连接'), findsOneWidget);
    final petCard = find.byKey(const ValueKey('pet_dashboard_pet_card'));
    expect(
      find.descendant(of: petCard, matching: find.text('已连接')),
      findsOneWidget,
    );
    expect(find.text(firstItem.title), findsOneWidget);
    expect(find.text('下一件事'), findsOneWidget);
  });

  testWidgets('横屏看板多尺寸下控件保持在卡片边界内', (tester) async {
    final sizes = <Size>[
      const Size(720, 390),
      const Size(900, 520),
      const Size(2048, 945),
    ];

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);

      final store = PetNoteStore.seeded();
      final pet = store.pets.first;
      await store.addTodo(
        petId: pet.id,
        title: '横屏特别长的待办标题用于压测完成按钮是否仍然留在卡片里面',
        dueAt: DateTime(2026, 6, 22, 20, 15),
        notificationLeadTime: NotificationLeadTime.none,
        note: '备注也需要在横屏空间里保持省略，不应该把完成按钮向卡片外挤出。',
      );

      await tester.pumpWidget(
        _wrapDashboard(
          PetDeviceDashboard(
            store: store,
            servedPetId: pet.id,
            syncStatusLabel: '已连接',
            pendingItemKeys: const <String>{},
            onSelectServedPet: (_) {},
            onMarkDone: (_) {},
            onOpenSettings: () {},
            nowProvider: () => DateTime(2026, 6, 22, 19, 15),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final petCardRect = tester.getRect(
        find.byKey(const ValueKey('pet_dashboard_pet_card')),
      );
      final todoPanelRect = tester.getRect(
        find.byKey(const ValueKey('pet_dashboard_todo_panel')),
      );
      final settingsRect = tester.getRect(
        find.byKey(const ValueKey('pet_dashboard_settings')),
      );
      final connectionRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('pet_dashboard_pet_card')),
          matching: find.text('已连接'),
        ),
      );
      final completeButtonRect = tester.getRect(
        find.byKey(ValueKey(
            'dashboard_item_${store.checklistSections.expand((section) => section.items).where((item) => item.petId == pet.id).first.sourceType}_${store.checklistSections.expand((section) => section.items).where((item) => item.petId == pet.id).first.id}')),
      );

      expect(settingsRect.right, closeTo(petCardRect.right, 1.0));
      expect(connectionRect.left, greaterThanOrEqualTo(petCardRect.left + 8));
      expect(connectionRect.right, lessThanOrEqualTo(petCardRect.right - 8));
      expect(connectionRect.bottom, lessThanOrEqualTo(petCardRect.bottom - 8));

      expect(todoPanelRect.left, greaterThan(petCardRect.right));
      expect(todoPanelRect.right, lessThanOrEqualTo(size.width));
      expect(todoPanelRect.bottom, lessThanOrEqualTo(size.height));
      expect(completeButtonRect.left,
          greaterThanOrEqualTo(todoPanelRect.left + 8));
      expect(
          completeButtonRect.right, lessThanOrEqualTo(todoPanelRect.right - 8));
      expect(completeButtonRect.bottom,
          lessThanOrEqualTo(todoPanelRect.bottom - 8));
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('横屏看板设置和完成交互保持可用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '横屏完成交互',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;
    var openedSettings = false;
    PetAction? action;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (value) => action = value,
          onOpenSettings: () => openedSettings = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pet_dashboard_settings')));
    await tester.pump();
    expect(openedSettings, isTrue);

    await tester.tap(
      find.byKey(
          ValueKey('dashboard_item_${firstItem.sourceType}_${firstItem.id}')),
    );
    await tester.pump();
    expect(action?.kind, PetActionKind.markDone);
    expect(action?.sourceType, firstItem.sourceType);
  });

  testWidgets('横屏看板待确认事项仍显示同步中并禁用完成按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '横屏待确认事项',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;
    PetAction? action;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: {'${firstItem.sourceType}:${firstItem.id}'},
          onSelectServedPet: (_) {},
          onMarkDone: (value) => action = value,
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text('同步中'), findsOneWidget);
    await tester.tap(
      find.byKey(
          ValueKey('dashboard_item_${firstItem.sourceType}_${firstItem.id}')),
    );
    await tester.pump();
    expect(action, isNull);
  });

  testWidgets('宠物端看板优先显示同步后的真实头像', (tester) async {
    final photoFile = File(
      '${Directory.systemTemp.path}/petnote-dashboard-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
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
        key: ValueKey('dashboard-real-photo-$photoPath'),
      );
    };
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await store.addPet(
      name: '强',
      type: PetType.dog,
      photoPath: photoFile.path,
      breed: '法斗',
      sex: '弟弟',
      birthday: '2025-01-01',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '同步头像',
    );
    final pet = store.pets.single;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.byKey(ValueKey('dashboard-real-photo-${photoFile.path}')),
        findsOneWidget);
  });

  testWidgets('等待同步确认时宠物端在设置旁显示胶囊', (tester) async {
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    final transport = _FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: store,
      transport: transport,
      crypto: crypto,
    );
    final settings = await AppSettingsController.load();
    await settings.setHouseholdId('house-1');
    final service = SyncService(settings: settings);
    service.petController = controller;
    SyncService.instance = service;
    await settings.setPendingResetSnapshotSyncId('failed-sync');

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pet_dashboard_settings')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sync_failure_chip')), findsNothing);
    expect(find.text('同步确认中'), findsOneWidget);

    await tester.tap(find.text('同步确认中'));
    await tester.pumpAndSettle();

    expect(find.text('同步确认中'), findsWidgets);
    expect(find.text('数据已发出，正在等待另一台设备确认收到。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync_failure_retry_button')),
      findsOneWidget,
    );

    await service.stop();
    SyncService.instance = null;
  });

  testWidgets('合并冲突弹窗返回保留对方', (tester) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            dialogContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showSyncMergeConflictDialog(
      dialogContext,
      const SyncMergeConflict(
        collectionLabel: '待办',
        id: 'todo-1',
        localLabel: '本机待办',
        remoteLabel: '对方待办',
        differences: [
          SyncMergeDifference(
            fieldPath: 'title',
            localValue: '本机待办',
            remoteValue: '对方待办',
          ),
          SyncMergeDifference(
            fieldPath: 'note',
            localValue: '本机备注',
            remoteValue: '对方备注',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待办冲突'), findsOneWidget);
    expect(find.textContaining('本机待办'), findsWidgets);
    expect(find.text('title'), findsOneWidget);
    expect(find.text('note'), findsOneWidget);
    expect(find.textContaining('对方备注'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync_merge_keep_remote')));
    await tester.pumpAndSettle();

    expect(await future, SyncMergeSide.remote);
  });
}

Widget _wrapDashboard(Widget child,
    {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildPetNoteTheme(brightness),
    home: child,
  );
}

class _FakeSyncTransport implements SyncTransport {
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  ValueListenable<SyncConnectionState> get state => _state;
  final ValueNotifier<SyncConnectionState> _state =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connected);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void send(SyncMessage message) {}
}
