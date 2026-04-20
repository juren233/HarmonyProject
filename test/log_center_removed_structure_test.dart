import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('日志中心页面功能已从应用代码和测试中移除', () {
    expect(File('lib/app/log_center_page.dart').existsSync(), isFalse);
    expect(File('test/log_center_page_test.dart').existsSync(), isFalse);

    final scannedFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .followedBy(
            Directory('test').listSync(recursive: true).whereType<File>())
        .where((file) => file.path.endsWith('.dart'))
        .where((file) =>
            !file.path.endsWith('log_center_removed_structure_test.dart'));

    for (final file in scannedFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('LogCenterPage')), reason: file.path);
      expect(source, isNot(contains('log_center_page')), reason: file.path);
      expect(source, isNot(contains('日志中心')), reason: file.path);
      expect(source, isNot(contains('me_open_log_center')), reason: file.path);
    }
  });
}
