import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

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
          const HeroPanel(
            title: '欢迎来到日常照护清单',
            subtitle: '添加第一只爱宠后，这里会开始承接待办、提醒和记录，让每天的事情更顺手。',
            child: SizedBox.shrink(),
          ),
          EmptyCard(
            title: '先添加第一只爱宠',
            subtitle: '建好第一份档案后，清单、提醒和总览都会围绕它展开。',
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

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
  });

  final PetNoteStore store;
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
            title: '总览',
            subtitle: '先添加宠物，AI 照护总结才会开始积累',
          ),
          const HeroPanel(
            title: '等第一份档案建立后再开始总结',
            subtitle: '当前还没有宠物资料、提醒或记录。先完成第一只爱宠建档，后续的照护观察会自动收拢到这里。',
            child: SizedBox.shrink(),
          ),
          EmptyCard(
            title: '先添加第一只爱宠',
            subtitle: '有了基础档案后，这里才会生成更贴近日常的总结内容。',
            actionLabel: '开始添加宠物',
            onAction: onAddFirstPet,
          ),
        ],
      );
    }

    final snapshot = store.overviewSnapshot;
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '总览',
          subtitle: 'AI 照护总结',
        ),
        HeroPanel(
          title: _overviewTitle(snapshot.range),
          subtitle: '根据最近的待办、提醒和资料记录，用更接近系统报告页的方式整理你的照护观察。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HyperSegmentedControl(
                items: const [
                  SegmentItem(key: 'sevenDays', label: '7天'),
                  SegmentItem(key: 'oneMonth', label: '1个月'),
                  SegmentItem(key: 'threeMonths', label: '3个月'),
                  SegmentItem(key: 'sixMonths', label: '6个月'),
                  SegmentItem(key: 'oneYear', label: '1年'),
                ],
                selectedKey: snapshot.range.name,
                onChanged: (value) =>
                    store.setOverviewRange(_rangeFromKey(value)),
              ),
            ],
          ),
        ),
        ...snapshot.sections.map(
          (section) => SectionCard(
            title: section.title,
            children:
                section.items.map((item) => BulletText(text: item)).toList(),
          ),
        ),
        SectionCard(
          title: '说明',
          children: [
            Text(
              snapshot.disclaimer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.petNoteTokens.secondaryText,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class PetsPage extends StatelessWidget {
  const PetsPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    required this.onEditPet,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final ValueChanged<Pet> onEditPet;

  @override
  Widget build(BuildContext context) {
    final pet = store.selectedPet;
    final remindersForSelectedPet = store.remindersForSelectedPet;
    final recordsForSelectedPet = store.recordsForSelectedPet;
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        PageHeader(
          title: '爱宠',
          subtitle: pet == null ? '管理你的宠物档案' : '${pet.name} 的照护档案',
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.pets.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = store.pets[index];
              final selected = pet?.id == item.id;
              return GestureDetector(
                onTap: () => store.selectPet(item.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFF2A65A)
                        : const Color(0xF4FFFFFF),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: selected
                            ? const Color(0x33FFFFFF)
                            : const Color(0xFFE8EEFF),
                        child: Text(
                          item.avatarText,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF335FCA),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFF17181C),
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.ageLabel,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: selected
                                          ? Colors.white70
                                          : const Color(0xFF6C7280),
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (pet == null)
          EmptyCard(
            title: '先添加第一只爱宠',
            subtitle: '建好第一份宠物档案后，提醒、记录和照护观察都会围绕它展开。',
            actionLabel: '开始添加宠物',
            onAction: onAddFirstPet,
          )
        else ...[
          HeroPanel(
            title: pet.name,
            subtitle:
                '${petTypeLabel(pet.type)} · ${pet.breed} · ${pet.ageLabel} · 当前体重 ${pet.weightKg} kg',
            child: Row(
              children: [
                Expanded(
                  child: MetricOverview(
                    metrics: [
                      MetricItem(
                        label: '近期提醒',
                        value: '${remindersForSelectedPet.length}',
                        background: const Color(0xFFEAF0FF),
                        foreground: const Color(0xFF335FCA),
                      ),
                      MetricItem(
                        label: '资料记录',
                        value: '${recordsForSelectedPet.length}',
                        background: const Color(0xFFF5F0FF),
                        foreground: const Color(0xFF6B51C9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: '基础信息',
            trailing: TextButton(
              key: const ValueKey('edit_pet_button'),
              onPressed: () => onEditPet(pet),
              child: const Text('编辑信息'),
            ),
            children: [
              InfoRow(label: '类型', value: petTypeLabel(pet.type)),
              InfoRow(label: '性别', value: pet.sex),
              InfoRow(label: '生日', value: pet.birthday),
              InfoRow(
                  label: '绝育状态', value: petNeuterStatusLabel(pet.neuterStatus)),
              InfoRow(label: '喂养偏好', value: pet.feedingPreferences),
              InfoRow(label: '过敏/禁忌', value: pet.allergies),
              InfoRow(label: '备注', value: pet.note),
            ],
          ),
          SectionCard(
            title: '近期提醒',
            children: remindersForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无提醒',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : remindersForSelectedPet
                    .map(
                      (item) => ListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.scheduledAt)} · ${item.recurrence}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DD),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.notifications_active_rounded,
                              color: Color(0xFFF2A65A)),
                        ),
                        trailing: HyperBadge(
                          text: _reminderKindLabel(item.kind),
                          foreground: const Color(0xFFC57A14),
                          background: const Color(0xFFFFF1DD),
                        ),
                      ),
                    )
                    .toList(),
          ),
          SectionCard(
            title: '资料记录',
            children: recordsForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无资料记录',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : recordsForSelectedPet
                    .map(
                      (item) => ListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.recordDate, withTime: false)} · ${item.summary}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F7EE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.description_rounded,
                              color: Color(0xFF4FB57C)),
                        ),
                        trailing: HyperBadge(
                          text: _recordTypeLabel(item.type),
                          foreground: const Color(0xFF2F8F5B),
                          background: const Color(0xFFE8F7EE),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ],
    );
  }
}

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '我的',
          subtitle: '设备与应用设置',
        ),
        const HeroPanel(
          title: 'PetNote',
          subtitle: '把提醒、记录和照护总结收在一个更轻盈的系统式界面里，方便每天顺手管理。',
          child: SizedBox.shrink(),
        ),
        SectionCard(
          title: 'Theme & Appearance',
          children: [
            ListRow(
              title: 'Current theme',
              subtitle: switch (themePreference) {
                AppThemePreference.system => 'Follow system',
                AppThemePreference.light => 'Light mode',
                AppThemePreference.dark => 'Dark mode',
              },
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_system'),
              title: 'Follow system',
              subtitle: 'Use the device appearance setting automatically.',
              value: AppThemePreference.system,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_light'),
              title: 'Light mode',
              subtitle: 'Keep the current bright interface style.',
              value: AppThemePreference.light,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_dark'),
              title: 'Dark mode',
              subtitle: 'Reduce glare for low-light usage.',
              value: AppThemePreference.dark,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
          ],
        ),
        SectionCard(
          title: '通知与提醒',
          children: const [
            ListRow(title: '提醒权限', subtitle: '后续可接入系统通知与提醒权限管理'),
            ListRow(title: '提醒方式', subtitle: '当前原型使用本地清单和 AI 总览来承接提醒信息'),
          ],
        ),
        SectionCard(
          title: '数据与存储',
          children: const [
            ListRow(title: '备份与恢复', subtitle: '预留本地备份、迁移与恢复入口'),
            ListRow(title: '导出与分享', subtitle: '后续支持导出宠物交接卡和记录摘要'),
          ],
        ),
        SectionCard(
          title: '隐私与关于',
          children: const [
            ListRow(title: '隐私说明', subtitle: '仅用于记录照护信息和生成日常建议'),
            ListRow(title: '关于应用', subtitle: 'AI 总览仅供照护参考，不替代兽医建议'),
          ],
        ),
      ],
    );
  }
}

class _ThemePreferenceTile extends StatelessWidget {
  const _ThemePreferenceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final AppThemePreference value;
  final AppThemePreference groupValue;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.listRowBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: RadioListTile<AppThemePreference>(
        value: value,
        groupValue: groupValue,
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.secondaryText,
                height: 1.45,
              ),
        ),
        activeColor: Theme.of(context).colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
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

String _overviewTitle(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '最近 7 天的总结',
      OverviewRange.oneMonth => '最近 1 个月的总结',
      OverviewRange.threeMonths => '最近 3 个月的总结',
      OverviewRange.sixMonths => '最近 6 个月的总结',
      OverviewRange.oneYear => '最近 1 年的总结',
    };

OverviewRange _rangeFromKey(String key) => switch (key) {
      'sevenDays' => OverviewRange.sevenDays,
      'oneMonth' => OverviewRange.oneMonth,
      'threeMonths' => OverviewRange.threeMonths,
      'sixMonths' => OverviewRange.sixMonths,
      'oneYear' => OverviewRange.oneYear,
      _ => OverviewRange.sevenDays,
    };

String _reminderKindLabel(ReminderKind kind) => switch (kind) {
      ReminderKind.vaccine => '疫苗',
      ReminderKind.deworming => '驱虫',
      ReminderKind.medication => '用药',
      ReminderKind.review => '复诊',
      ReminderKind.grooming => '洗护',
      ReminderKind.custom => '自定义',
    };

String _recordTypeLabel(PetRecordType type) => switch (type) {
      PetRecordType.medical => '病历',
      PetRecordType.receipt => '票据',
      PetRecordType.image => '图片',
      PetRecordType.testResult => '检查结果',
      PetRecordType.other => '其他',
    };
