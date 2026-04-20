import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/ios_native_overview_range_button.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/native_option_picker.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/app/overview_bottom_cta.dart';
import 'package:petnote/app/add_sheet/form_controls/adaptive_date_time_field.dart';
import 'package:petnote/app/add_sheet/form_controls/choice_wrap.dart';
import 'package:petnote/app/add_sheet/form_controls/pet_selector.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

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
                label: '即将到期',
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
            SegmentItem(key: 'upcoming', label: '即将到期 ${upcoming.summary}'),
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
