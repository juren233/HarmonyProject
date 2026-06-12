import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('服务器部署物存在且包含关键配置', () {
    final dockerfile = File('server/Dockerfile').readAsStringSync();
    expect(dockerfile, contains('dart compile exe'));
    expect(dockerfile, contains('petnote_sync_server.dart'));

    final compose = File('server/docker-compose.yml').readAsStringSync();
    expect(compose, contains('petnote-sync'));
    expect(compose, contains('DATA_DIR'));
    expect(compose, contains('coturn'));
    expect(compose, contains('3478'));

    final readme = File('server/README.md').readAsStringSync();
    expect(readme, contains('docker compose up -d'));
    expect(readme, contains('wss://'));
  });
}
