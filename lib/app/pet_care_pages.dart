import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class ChecklistPage extends StatelessWidget {
  const ChecklistPage({
    super.key,
    required this.store,
    required this.activeSectionKey,
    required this.onSectionChanged,
  });

  final PetCareStore store;
  final String activeSectionKey;
  final ValueChanged<String> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final section = store.checklistSections.firstWhere(
      (item) => item.key == activeSectionKey,
      orElse: () => store.checklistSections.first,
    );
    final pagePadding = pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    final today = store.checklistSections[0];
    final upcoming = store.checklistSections[1];
    final overdue = store.checklistSections[2];

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
              item: item,
              onComplete: () => store.markChecklistDone(item.sourceType, item.id),
              onPostpone: () => store.postponeChecklist(item.sourceType, item.id),
              onSkip: () => store.skipChecklist(item.sourceType, item.id),
            ),
          ),
      ],
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.store});

  final PetCareStore store;

  @override
  Widget build(BuildContext context) {
    final snapshot = store.overviewSnapshot;
    final pagePadding = pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
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
                onChanged: (value) => store.setOverviewRange(_rangeFromKey(value)),
              ),
            ],
          ),
        ),
        ...snapshot.sections.map(
          (section) => SectionCard(
            title: section.title,
            children: section.items.map((item) => BulletText(text: item)).toList(),
          ),
        ),
        SectionCard(
          title: '说明',
          children: [
            Text(
              snapshot.disclaimer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6C7280),
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
  const PetsPage({super.key, required this.store});

  final PetCareStore store;

  @override
  Widget build(BuildContext context) {
    final pet = store.selectedPet;
    final pagePadding = pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF14161C) : const Color(0xF4FFFFFF),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 22,
                              offset: Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: selected ? const Color(0x33FFFFFF) : const Color(0xFFE8EEFF),
                        child: Text(
                          item.avatarText,
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFF335FCA),
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
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: selected ? Colors.white : const Color(0xFF17181C),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.ageLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: selected ? Colors.white70 : const Color(0xFF6C7280),
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
          const EmptyCard(
            title: '还没有爱宠档案',
            subtitle: '点击底部中间的 +，先为你的第一只爱宠创建完整档案。',
          )
        else ...[
          HeroPanel(
            title: pet.name,
            subtitle: '${pet.breed} · ${pet.ageLabel} · 当前体重 ${pet.weightKg} kg',
            child: Row(
              children: [
                Expanded(
                  child: MetricOverview(
                    metrics: [
                      MetricItem(
                        label: '近期提醒',
                        value: '${store.remindersForSelectedPet.length}',
                        background: const Color(0xFFEAF0FF),
                        foreground: const Color(0xFF335FCA),
                      ),
                      MetricItem(
                        label: '资料记录',
                        value: '${store.recordsForSelectedPet.length}',
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
            children: [
              InfoRow(label: '性别', value: pet.sex),
              InfoRow(label: '生日', value: pet.birthday),
              InfoRow(label: '喂养偏好', value: pet.feedingPreferences),
              InfoRow(label: '过敏/禁忌', value: pet.allergies),
              InfoRow(label: '备注', value: pet.note),
            ],
          ),
          SectionCard(
            title: '近期提醒',
            children: store.remindersForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无提醒',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : store.remindersForSelectedPet
                    .map(
                      (item) => ListRow(
                        title: item.title,
                        subtitle: '${formatDate(item.scheduledAt)} · ${item.recurrence}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF5B8CFF)),
                        ),
                        trailing: HyperBadge(
                          text: _reminderKindLabel(item.kind),
                          foreground: const Color(0xFF335FCA),
                          background: const Color(0xFFEAF0FF),
                        ),
                      ),
                    )
                    .toList(),
          ),
          SectionCard(
            title: '资料记录',
            children: store.recordsForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无资料记录',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : store.recordsForSelectedPet
                    .map(
                      (item) => ListRow(
                        title: item.title,
                        subtitle: '${formatDate(item.recordDate, withTime: false)} · ${item.summary}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3D8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.description_rounded, color: Color(0xFF9C760A)),
                        ),
                        trailing: HyperBadge(
                          text: _recordTypeLabel(item.type),
                          foreground: const Color(0xFF8B6B10),
                          background: const Color(0xFFFFF3D8),
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
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pagePadding = pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '我的',
          subtitle: '设备与应用设置',
        ),
        const HeroPanel(
          title: 'Pet Care',
          subtitle: '把提醒、记录和照护总结收在一个更轻盈的系统式界面里，方便每天顺手管理。',
          child: SizedBox.shrink(),
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
