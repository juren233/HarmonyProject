part of 'petnote_pages.dart';

class PetDetailsPage extends StatelessWidget {
  const PetDetailsPage({
    super.key,
    required this.pet,
    required this.reminders,
    required this.records,
    required this.detailType,
  });

  final Pet pet;
  final List<ReminderItem> reminders;
  final List<PetRecord> records;
  final PetDetailType detailType;

  @override
  Widget build(BuildContext context) {
    const pagePadding = EdgeInsets.fromLTRB(18, 8, 18, 20);

    return Scaffold(
      appBar: AppBar(
        title: Text(detailType == PetDetailType.reminders ? '近期提醒' : '资料记录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          PageHeader(
            title: pet.name,
            subtitle:
                '${petTypeLabel(pet.type)} · ${pet.breed} · ${pet.ageLabel}',
          ),
          const SizedBox(height: 8),
          if (detailType == PetDetailType.reminders)
            _buildRemindersSection(context, reminders)
          else
            _buildRecordsSection(context, records),
        ],
      ),
    );
  }

  Widget _buildRemindersSection(
    BuildContext context,
    List<ReminderItem> reminders,
  ) {
    if (reminders.isEmpty) {
      return PageEmptyStateBlock(
        emptyTitle: '暂无提醒',
        emptySubtitle: '当前宠物暂无任何提醒记录。',
        actionLabel: '返回',
        onAction: () => Navigator.pop(context),
      );
    }

    return SectionCard(
      title: '近期提醒',
      children: reminders
          .map(
            (item) => StatusListRow(
              title: item.title,
              subtitle: '${formatDate(item.scheduledAt)} · ${item.recurrence}',
              leadingIcon: Icons.notifications_active_rounded,
              leadingBackgroundColor: const Color(0xFFFFF1DD),
              leadingIconColor: const Color(0xFFF2A65A),
              trailing: HyperBadge(
                text: _reminderKindLabel(item.kind),
                foreground: const Color(0xFFC57A14),
                background: const Color(0xFFFFF1DD),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRecordsSection(BuildContext context, List<PetRecord> records) {
    if (records.isEmpty) {
      return PageEmptyStateBlock(
        emptyTitle: '暂无资料记录',
        emptySubtitle: '当前宠物暂无任何资料记录。',
        actionLabel: '返回',
        onAction: () => Navigator.pop(context),
      );
    }

    return SectionCard(
      title: '资料记录',
      children: records
          .map(
            (item) => StatusListRow(
              title: item.title,
              subtitle:
                  '${formatDate(item.recordDate, withTime: false)} · ${item.summary}',
              leadingIcon: Icons.description_rounded,
              leadingBackgroundColor: const Color(0xFFE8F7EE),
              leadingIconColor: const Color(0xFF4FB57C),
              trailing: HyperBadge(
                text: _recordTypeLabel(item.type),
                foreground: const Color(0xFF2F8F5B),
                background: const Color(0xFFE8F7EE),
              ),
            ),
          )
          .toList(),
    );
  }

  String _reminderKindLabel(ReminderKind kind) {
    switch (kind) {
      case ReminderKind.medication:
        return '用药';
      case ReminderKind.review:
        return '就诊';
      case ReminderKind.vaccine:
        return '疫苗';
      case ReminderKind.grooming:
        return '美容';
      case ReminderKind.deworming:
        return '驱虫';
      case ReminderKind.custom:
        return '其他';
    }
  }

  String _recordTypeLabel(PetRecordType type) {
    switch (type) {
      case PetRecordType.medical:
        return '就诊';
      case PetRecordType.testResult:
        return '检查';
      case PetRecordType.receipt:
        return '收据';
      case PetRecordType.image:
        return '图片';
      case PetRecordType.other:
        return '其他';
    }
  }
}

enum PetDetailType {
  reminders,
  records,
}
