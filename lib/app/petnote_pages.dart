import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/interaction_feedback.dart';
import 'package:petnote/app/interaction_haptics.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/app/overview_bottom_cta.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/app/add_sheet/form_controls/adaptive_date_time_field.dart';
import 'package:petnote/app/add_sheet/form_controls/choice_wrap.dart';
import 'package:petnote/app/add_sheet/form_controls/pet_selector.dart';
import 'package:petnote/rtc/rtc_media_permission_coordinator.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_service.dart';

part 'petnote_pages_overview.dart';
part 'petnote_pages_pets.dart';
part 'petnote_pages_pets_details.dart';
part 'petnote_pages_checklist_details.dart';
part 'petnote_pages_me.dart';
part 'petnote_pages_ai.dart';

class ChecklistPage extends StatelessWidget {
  const ChecklistPage({
    super.key,
    required this.store,
    required this.activeSectionKey,
    required this.highlightedChecklistItemKey,
    required this.onSectionChanged,
    required this.onAddFirstPet,
  });

  final PetNoteStore store;
  final String activeSectionKey;
  final String? highlightedChecklistItemKey;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onAddFirstPet;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    if (store.pets.isEmpty) {
      return ListView(
        padding: pagePadding,
        children: [
          const PageHeader(
            title: '清单',
            subtitle: '先建好第一只爱宠，再开始安排照护节奏',
          ),
          PageEmptyStateBlock(
            heroTitle: '欢迎来到日常照护清单',
            heroSubtitle: '添加第一只爱宠后，这里会开始承接待办、提醒和记录，让每天的事情更顺手。',
            emptyTitle: '先添加第一只爱宠',
            emptySubtitle: '建好第一份档案后，清单、提醒和总览都会围绕它展开。',
            actionLabel: '开始添加宠物',
            onAction: onAddFirstPet,
          ),
        ],
      );
    }

    final sections = store.checklistSections;
    final section = sections.firstWhere(
      (item) => item.key == activeSectionKey,
      orElse: () => sections.first,
    );
    final today = _sectionByKey(sections, 'today');
    final upcoming = _sectionByKey(sections, 'upcoming');
    final overdue = _sectionByKey(sections, 'overdue');
    final postponed = _sectionByKey(sections, 'postponed');
    final skipped = _sectionByKey(sections, 'skipped');

    return ListView(
      padding: pagePadding,
      children: [
        PageHeader(
          title: '清单',
          subtitle: '今天 ${today.items.length} 项待处理',
          trailing: const SyncFailureChip(),
        ),
        HeroPanel(
          title: '今日照护概况',
          subtitle: '关键节点和日常待办都被整理在这里，先把最重要的事情完成掉。',
          child: MetricOverview(
            metrics: [
              MetricItem(
                label: '今日待办',
                value: '${today.items.length}',
                background: const Color(0xFFEAF0FF),
                foreground: const Color(0xFF335FCA),
              ),
              MetricItem(
                label: '未来待办',
                value: '${upcoming.items.length}',
                background: const Color(0xFFFFF3D8),
                foreground: const Color(0xFF976A00),
              ),
              MetricItem(
                label: '已逾期',
                value: '${overdue.items.length}',
                background: const Color(0xFFFDEBE8),
                foreground: const Color(0xFFC7533E),
              ),
            ],
          ),
        ),
        HyperSegmentedControl(
          items: [
            SegmentItem(key: 'today', label: '今日 ${today.summary}'),
            SegmentItem(key: 'upcoming', label: '未来待办 ${upcoming.summary}'),
            SegmentItem(key: 'overdue', label: '已逾期 ${overdue.summary}'),
            SegmentItem(key: 'postponed', label: '已延后 ${postponed.summary}'),
            SegmentItem(key: 'skipped', label: '已跳过 ${skipped.summary}'),
          ],
          selectedKey: activeSectionKey,
          onChanged: onSectionChanged,
        ),
        const SizedBox(height: 18),
        if (section.items.isEmpty)
          const EmptyCard(
            title: '这一栏已经清空了',
            subtitle: '可以点击底部中间的 + 新增待办、提醒或记录，让照护节奏继续保持顺手。',
          )
        else
          ...section.items.map(
            (item) => ChecklistCard(
              key: ValueKey('checklist_card_${item.sourceType}-${item.id}'),
              item: item,
              highlighted: highlightedChecklistItemKey ==
                  '${item.sourceType}:${item.id}',
              onTap: () {
                final route = switch (item.sourceType) {
                  'reminder' => MaterialPageRoute<void>(
                      builder: (context) => ReminderDetailPage(
                        store: store,
                        reminderId: item.id,
                      ),
                    ),
                  _ => MaterialPageRoute<void>(
                      builder: (context) => TodoDetailPage(
                        store: store,
                        todoId: item.id,
                      ),
                    ),
                };
                Navigator.of(context).push(route);
              },
              onComplete: () =>
                  store.markChecklistDone(item.sourceType, item.id),
              onPostpone: () =>
                  store.postponeChecklist(item.sourceType, item.id),
              onSkip: () => store.skipChecklist(item.sourceType, item.id),
            ),
          ),
      ],
    );
  }
}

Future<SyncMergeSide> showSyncMergeConflictDialog(
  BuildContext context,
  SyncMergeConflict conflict,
) async {
  final side = await showDialog<SyncMergeSide>(
    context: context,
    builder: (context) {
      final differences = conflict.differences.take(8).toList();
      return AlertDialog(
        title: Text('${conflict.collectionLabel}冲突'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本机：${conflict.localLabel}'),
              Text('对方：${conflict.remoteLabel}'),
              if (differences.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final item in differences)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.fieldPath),
                        Text('本机：${_syncConflictValueLabel(item.localValue)}'),
                        Text('对方：${_syncConflictValueLabel(item.remoteValue)}'),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('sync_merge_keep_local'),
            onPressed: () => Navigator.of(context).pop(SyncMergeSide.local),
            child: const Text('保留本机'),
          ),
          FilledButton(
            key: const ValueKey('sync_merge_keep_remote'),
            onPressed: () => Navigator.of(context).pop(SyncMergeSide.remote),
            child: const Text('保留对方'),
          ),
        ],
      );
    },
  );
  return side ?? SyncMergeSide.local;
}

String _syncConflictValueLabel(Object? value) {
  if (value == null) {
    return '空';
  }
  if (value is List || value is Map) {
    return jsonEncode(value);
  }
  return value.toString();
}

class SyncFailureChip extends StatelessWidget {
  const SyncFailureChip({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SyncService.instance;
    if (service == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => _SyncFailureCountChip(
        listenable: service.failedSyncCount,
      ),
    );
  }
}

class _SyncFailureCountChip extends StatelessWidget {
  const _SyncFailureCountChip({required this.listenable});

  final ValueListenable<int>? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, count, _) {
        if (count <= 0) {
          return const SizedBox.shrink();
        }
        final service = SyncService.instance;
        final issueKind =
            service?.currentIssueKind ?? SyncIssueKind.failedQueue;
        final label = syncIssueChipLabel(issueKind);
        return Padding(
          padding: const EdgeInsets.only(left: 12),
          child: ActionChip(
            key: const ValueKey('sync_failure_chip'),
            avatar: const Icon(Icons.sync_problem_rounded, size: 18),
            label: Text(label),
            onPressed: () => showSyncIssueDialog(
              context,
              count: count,
              issueKind: issueKind,
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSyncIssueDialog(
  BuildContext context, {
  required int count,
  required SyncIssueKind issueKind,
}) {
  final parentContext = context;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_syncIssueDialogTitle(issueKind)),
      content: Text(_syncIssueDialogMessage(issueKind, count)),
      actions: [
        TextButton(
          key: const ValueKey('sync_failure_diagnostics_button'),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(showSyncDiagnosticsDialog(parentContext));
          },
          child: const Text('诊断信息'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          key: const ValueKey('sync_failure_retry_button'),
          onPressed: () {
            final service = SyncService.instance;
            service?.retrySyncIssues();
            Navigator.of(context).pop();
          },
          child: const Text('重新同步'),
        ),
      ],
    ),
  );
}

Future<void> showSyncDiagnosticsDialog(BuildContext context) async {
  final service = SyncService.instance;
  final diagnostics = service == null
      ? <String, Object?>{'available': false}
      : await service.buildDiagnosticsSnapshotWithPayloadStats();
  if (!context.mounted) {
    return;
  }
  final encoded = const JsonEncoder.withIndent('  ').convert(diagnostics);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('同步诊断信息'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: SelectableText(
            encoded,
            key: const ValueKey('sync_diagnostics_payload'),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('sync_diagnostics_copy_button'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: encoded));
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('诊断信息已复制')),
            );
          },
          child: const Text('复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String syncIssueChipLabel(SyncIssueKind issueKind) {
  return switch (issueKind) {
    SyncIssueKind.pendingResetConfirmation => '同步确认中',
    SyncIssueKind.handshakeFailed || SyncIssueKind.failedQueue => '同步失败',
    SyncIssueKind.none => '同步',
  };
}

String _syncIssueDialogTitle(SyncIssueKind issueKind) {
  return switch (issueKind) {
    SyncIssueKind.pendingResetConfirmation => '同步确认中',
    SyncIssueKind.handshakeFailed || SyncIssueKind.failedQueue => '同步失败',
    SyncIssueKind.none => '同步状态',
  };
}

String _syncIssueDialogMessage(SyncIssueKind issueKind, int count) {
  return switch (issueKind) {
    SyncIssueKind.pendingResetConfirmation => '数据已发出，正在等待另一台设备确认收到。',
    SyncIssueKind.handshakeFailed => '同步服务器握手失败，请检查配对状态或重新同步。',
    SyncIssueKind.failedQueue => '$count 条数据同步失败',
    SyncIssueKind.none => '当前没有待处理的同步问题。',
  };
}

ChecklistSection _sectionByKey(
  List<ChecklistSection> sections,
  String key,
) {
  return sections.firstWhere(
    (section) => section.key == key,
    orElse: () => ChecklistSection(
      key: key,
      title: '',
      summary: '0 项',
      items: const [],
    ),
  );
}

String petAgeLabel(Pet pet, DateTime now) {
  final birthday = DateTime.tryParse(pet.birthday);
  if (birthday == null) {
    return _visibleAgeLabel(pet.ageLabel);
  }
  final today = DateTime(now.year, now.month, now.day);
  final birthDate = DateTime(birthday.year, birthday.month, birthday.day);
  if (birthDate.isAfter(today)) {
    return _visibleAgeLabel(pet.ageLabel);
  }
  var years = today.year - birthDate.year;
  final birthdayThisYear = DateTime(today.year, birthDate.month, birthDate.day);
  if (today.isBefore(birthdayThisYear)) {
    years -= 1;
  }
  if (years > 0) {
    return '$years岁';
  }
  var months =
      (today.year - birthDate.year) * 12 + today.month - birthDate.month;
  if (today.day < birthDate.day) {
    months -= 1;
  }
  if (months > 0) {
    return '$months个月';
  }
  final days = today.difference(birthDate).inDays;
  if (days > 0) {
    return '$days天';
  }
  return '';
}

String petProfileSummary(
  Pet pet,
  DateTime now, {
  bool includeWeight = false,
}) {
  return [
    petTypeLabel(pet.type),
    pet.breed,
    petAgeLabel(pet, now),
    if (includeWeight) '当前体重 ${pet.weightKg} kg',
  ].where((item) => item.trim().isNotEmpty).join(' · ');
}

String _visibleAgeLabel(String value) {
  final trimmed = value.trim();
  return trimmed == '新加入' ? '' : trimmed;
}

String formatDate(DateTime value, {bool withTime = true}) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  if (!withTime) {
    return '${value.year}-$month-$day';
  }
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
