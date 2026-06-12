import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('官方配置支持域名并补全 WebSocket 地址', () async {
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => '{"server_domain":"petnote.juren233.top"}',
    );

    expect(await resolver.resolve(), 'wss://petnote.juren233.top/ws');
  });

  test('官方配置支持 http 地址转换为 wss', () async {
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => '{"server_url":"https://petnote.juren233.top"}',
    );

    expect(await resolver.resolve(), 'wss://petnote.juren233.top/ws');
  });

  test('官方配置支持纯文本域名', () async {
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => 'petnote.juren233.top',
    );

    expect(await resolver.resolve(), 'wss://petnote.juren233.top/ws');
  });

  test('官方配置缺少域名时给出可观察错误', () async {
    final resolver = OfficialSyncServerResolver(
      fetcher: (_) async => '{"version":"1.0.0"}',
    );

    expect(
      resolver.resolve,
      throwsA(isA<OfficialSyncServerException>()),
    );
  });

  test('自定义服务器配置在同步服务读取时补全 WebSocket 地址', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsController.load();
    await settings.setSyncServerMode(SyncServerMode.custom);
    await settings.setSyncServerUrl('petnote.juren233.top');

    final resolved = await resolveConfiguredSyncServerUrl(
      settings: settings,
      officialResolver: OfficialSyncServerResolver(
        fetcher: (_) async => 'unused.example',
      ),
    );

    expect(resolved, 'wss://petnote.juren233.top/ws');
    expect(settings.syncServerUrl, 'wss://petnote.juren233.top/ws');
  });
}
