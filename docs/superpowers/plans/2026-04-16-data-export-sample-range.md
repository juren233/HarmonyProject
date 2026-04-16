# 数据导出短样本替换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 1 个月和 3 个月两份伪真实备份样本替换当前年度高密度导出样本，并同步更新样本校验测试。

**Architecture:** 保持 `PetNoteDataPackage` 和真实导出逻辑不变，只替换 `docs/examples/` 下的样本文件以及引用它们的测试。实现时先把测试改成“短样本双文件”预期，再用一次性脚本从现有年度样本裁剪出 1 个月和 3 个月版本，最后删除旧年度样本并做回归验证。

**Tech Stack:** Flutter, Dart test, JSON fixtures, Python 3 one-off transformation script, iOS unsigned IPA build, Android arm64-v8a APK build

---

## File Structure

- Modify: `test/data_storage_sample_fixture_test.dart`
  - 从单个年度样本断言改为两个短样本断言
  - 增加复用 helper，统一校验解析、时间窗口和未来计划约束
- Create: `docs/examples/petnote-ai-history-backup-1m.json`
  - 最近 30 天历史 + 少量未来 todo/reminder 的单宠备份样本
- Create: `docs/examples/petnote-ai-history-backup-3m.json`
  - 最近 90 天历史 + 少量未来 todo/reminder 的单宠备份样本
- Delete: `docs/examples/petnote-ai-history-backup.json`
  - 移除不再作为默认联调样本的年度高密度文件

### Task 1: 先把样本测试改成短样本双文件约束

**Files:**
- Modify: `test/data_storage_sample_fixture_test.dart`

- [ ] **Step 1: 写失败测试，改成 1m / 3m 双样本校验**

将 `test/data_storage_sample_fixture_test.dart` 改成下面这个版本：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final baseline = DateTime.parse('2026-04-09T23:59:59+08:00');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('1 month sample backup fixture parses and passes coordinator validation',
      () async {
    await _expectFixtureIsValid(
      fixturePath: 'docs/examples/petnote-ai-history-backup-1m.json',
      baseline: baseline,
      expectedWindowDays: 30,
      nameKeyword: '1个月',
    );
  });

  test('3 month sample backup fixture parses and passes coordinator validation',
      () async {
    await _expectFixtureIsValid(
      fixturePath: 'docs/examples/petnote-ai-history-backup-3m.json',
      baseline: baseline,
      expectedWindowDays: 90,
      nameKeyword: '3个月',
    );
  });
}

Future<void> _expectFixtureIsValid({
  required String fixturePath,
  required DateTime baseline,
  required int expectedWindowDays,
  required String nameKeyword,
}) async {
  final rawJson = File(fixturePath).readAsStringSync();
  final coordinator = DataStorageCoordinator(
    store: await PetNoteStore.load(),
    settingsController: await AppSettingsController.load(),
  );

  final package = coordinator.parsePackageJson(rawJson);
  final createdAt = package.createdAt;
  final historyStart = createdAt.subtract(Duration(days: expectedWindowDays));
  final futureTodos = package.data.todos
      .where((item) => item.dueAt.isAfter(baseline))
      .toList();
  final futureReminders = package.data.reminders
      .where((item) => item.scheduledAt.isAfter(baseline))
      .toList();
  final futureRecords = package.data.records
      .where((item) => item.recordDate.isAfter(baseline))
      .toList();

  expect(package.packageType, PetNoteDataPackageType.backup);
  expect(package.packageName, contains(nameKeyword));
  expect(package.data.pets, hasLength(1));
  expect(package.data.todos, isNotEmpty);
  expect(package.data.reminders, isNotEmpty);
  expect(package.data.records, isNotEmpty);
  expect(package.settings?.aiProviderConfigs, isEmpty);
  expect(package.settings?.activeAiProviderConfigId, isNull);
  expect(coordinator.validatePackage(package), isNull);
  expect(
    package.data.todos.every((item) => item.petId == 'pet-mochi-01'),
    isTrue,
  );
  expect(
    package.data.reminders.every((item) => item.petId == 'pet-mochi-01'),
    isTrue,
  );
  expect(
    package.data.records.every((item) => item.petId == 'pet-mochi-01'),
    isTrue,
  );
  expect(
    package.data.todos
        .where((item) => !item.dueAt.isAfter(createdAt))
        .every((item) => !item.dueAt.isBefore(historyStart)),
    isTrue,
  );
  expect(
    package.data.reminders
        .where((item) => !item.scheduledAt.isAfter(createdAt))
        .every((item) => !item.scheduledAt.isBefore(historyStart)),
    isTrue,
  );
  expect(
    package.data.records.every((item) => !item.recordDate.isBefore(historyStart)),
    isTrue,
  );
  expect(
    package.data.records.every((item) => !item.recordDate.isAfter(createdAt)),
    isTrue,
  );
  expect(futureTodos, isNotEmpty);
  expect(futureReminders, isNotEmpty);
  expect(futureRecords, isEmpty);
}
```

- [ ] **Step 2: 运行测试，确认它因为新样本文件不存在而失败**

Run:

```bash
flutter test test/data_storage_sample_fixture_test.dart
```

Expected: FAIL，并提示 `docs/examples/petnote-ai-history-backup-1m.json` 或 `docs/examples/petnote-ai-history-backup-3m.json` 不存在。

- [ ] **Step 3: 提交测试红灯**

```bash
git add test/data_storage_sample_fixture_test.dart
git commit -m "test: 改为校验导出短样本备份"
```

### Task 2: 生成 1 个月和 3 个月样本并移除年度样本

**Files:**
- Create: `docs/examples/petnote-ai-history-backup-1m.json`
- Create: `docs/examples/petnote-ai-history-backup-3m.json`
- Delete: `docs/examples/petnote-ai-history-backup.json`

- [ ] **Step 1: 用一次性脚本从年度样本裁剪 1m / 3m 两份文件**

在仓库根目录执行下面这个脚本：

```bash
python3 - <<'PY'
import json
from datetime import datetime, timedelta
from pathlib import Path

root = Path('.')
source_path = root / 'docs/examples/petnote-ai-history-backup.json'
source = json.loads(source_path.read_text())

created_at = datetime.fromisoformat(source['createdAt'])
baseline = datetime.fromisoformat('2026-04-09T23:59:59+08:00')

def within_window(value: str, history_days: int, future_days: int, *, allow_future: bool):
    dt = datetime.fromisoformat(value)
    history_start = created_at - timedelta(days=history_days)
    future_end = created_at + timedelta(days=future_days)
    if dt <= created_at:
      return dt >= history_start
    return allow_future and dt <= future_end

def build_variant(history_days: int, future_days: int, package_name: str, description: str, out_name: str):
    package = dict(source)
    data = dict(source['data'])
    data['todos'] = [
        item for item in source['data']['todos']
        if within_window(item['dueAt'], history_days, future_days, allow_future=True)
    ]
    data['reminders'] = [
        item for item in source['data']['reminders']
        if within_window(item['scheduledAt'], history_days, future_days, allow_future=True)
    ]
    data['records'] = [
        item for item in source['data']['records']
        if within_window(item['recordDate'], history_days, future_days, allow_future=False)
    ]
    package['packageName'] = package_name
    package['description'] = description
    package['data'] = data
    out_path = root / 'docs/examples' / out_name
    out_path.write_text(
        json.dumps(package, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )
    print(out_name, len(data['todos']), len(data['reminders']), len(data['records']))

build_variant(
    history_days=30,
    future_days=14,
    package_name='PetNote AI 联调短样本备份（单宠 1个月）',
    description='用于 AI 功能联调的单宠 1 个月伪真实备份样本，覆盖最近 30 天历史与少量未来计划。',
    out_name='petnote-ai-history-backup-1m.json',
)
build_variant(
    history_days=90,
    future_days=21,
    package_name='PetNote AI 联调短样本备份（单宠 3个月）',
    description='用于 AI 功能联调的单宠 3 个月伪真实备份样本，覆盖最近 90 天历史与少量未来计划。',
    out_name='petnote-ai-history-backup-3m.json',
)
PY
```

Expected output 类似：

```text
petnote-ai-history-backup-1m.json <todo-count> <reminder-count> <record-count>
petnote-ai-history-backup-3m.json <todo-count> <reminder-count> <record-count>
```

- [ ] **Step 2: 删除旧的年度高密度样本**

Run:

```bash
rm docs/examples/petnote-ai-history-backup.json
```

Expected: 年度样本文件被移除，仓库仅保留 `1m` 和 `3m` 两份联调样本。

- [ ] **Step 3: 打开新样本做一次人工抽查**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
for name in [
    'docs/examples/petnote-ai-history-backup-1m.json',
    'docs/examples/petnote-ai-history-backup-3m.json',
]:
    obj = json.loads(Path(name).read_text())
    print(name)
    print(obj['packageName'])
    print(obj['description'])
    print(len(obj['data']['pets']), len(obj['data']['todos']), len(obj['data']['reminders']), len(obj['data']['records']))
PY
```

Expected:

```text
docs/examples/petnote-ai-history-backup-1m.json
PetNote AI 联调短样本备份（单宠 1个月）
...
docs/examples/petnote-ai-history-backup-3m.json
PetNote AI 联调短样本备份（单宠 3个月）
...
```

- [ ] **Step 4: 提交样本替换**

```bash
git add docs/examples/petnote-ai-history-backup-1m.json docs/examples/petnote-ai-history-backup-3m.json docs/examples/petnote-ai-history-backup.json
git commit -m "feat: 将导出联调样本收敛到1个月和3个月"
```

### Task 3: 跑验证并构建交付产物

**Files:**
- Test: `test/data_storage_sample_fixture_test.dart`
- Test: `test/data_storage_coordinator_test.dart`
- Test: `test/data_storage_widget_test.dart`
- Output: `release/PetNote-ios-unsigned.ipa`
- Output: `release/PetNote-android-arm64-v8a-release.apk`

- [ ] **Step 1: 运行样本专项测试，确认绿灯**

Run:

```bash
flutter test test/data_storage_sample_fixture_test.dart
```

Expected: PASS，两个短样本都可解析、可校验。

- [ ] **Step 2: 运行导出链路回归测试**

Run:

```bash
flutter test test/data_storage_coordinator_test.dart
flutter test test/data_storage_widget_test.dart
```

Expected: PASS，不出现“年度样本名称”或“12 个月 bucket”相关失败。

- [ ] **Step 3: 构建未签名 IPA**

Run:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release --no-codesign
tmpdir="$(mktemp -d /tmp/petnote-unsigned-ipa.XXXXXX)"
mkdir -p "$tmpdir/Payload"
cp -R build/ios/iphoneos/Runner.app "$tmpdir/Payload/Runner.app"
ditto -c -k --sequesterRsrc --keepParent "$tmpdir/Payload" release/PetNote-ios-unsigned.ipa
rm -rf "$tmpdir"
cp -f release/PetNote-ios-unsigned.ipa build/ios/Runner-unsigned.ipa
```

Expected: `release/PetNote-ios-unsigned.ipa` 和 `build/ios/Runner-unsigned.ipa` 都存在。

- [ ] **Step 4: 构建 Android arm64-v8a APK**

Run:

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk release/PetNote-android-arm64-v8a-release.apk
```

Expected: `release/PetNote-android-arm64-v8a-release.apk` 存在。

- [ ] **Step 5: 提交最终收口**

```bash
git add test/data_storage_sample_fixture_test.dart docs/examples/petnote-ai-history-backup-1m.json docs/examples/petnote-ai-history-backup-3m.json docs/examples/petnote-ai-history-backup.json release/PetNote-ios-unsigned.ipa release/PetNote-android-arm64-v8a-release.apk
git commit -m "feat: 缩减导出联调样本时间范围"
```
