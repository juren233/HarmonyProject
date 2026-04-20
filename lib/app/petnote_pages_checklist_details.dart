part of 'petnote_pages.dart';

class TodoDetailPage extends StatefulWidget {
  const TodoDetailPage({
    super.key,
    required this.store,
    required this.todoId,
  });

  final PetNoteStore store;
  final String todoId;

  @override
  State<TodoDetailPage> createState() => _TodoDetailPageState();
}

class _TodoDetailPageState extends State<TodoDetailPage> {
  static const List<NotificationLeadTime> _leadTimeOptions =
      <NotificationLeadTime>[
    NotificationLeadTime.none,
    NotificationLeadTime.fiveMinutes,
    NotificationLeadTime.fifteenMinutes,
    NotificationLeadTime.oneHour,
    NotificationLeadTime.oneDay,
  ];

  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  _TodoEditSnapshot? _editingSnapshot;
  String? _petId;
  DateTime? _dueAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;

  bool get _isEditing => _editingSnapshot != null;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final todo = widget.store.todoById(widget.todoId);
        if (todo == null) {
          return _buildDeletedScaffold(context, '待办已不存在');
        }
        final pet =
            widget.store.petById(_petId ?? todo.petId) ?? widget.store.petById(todo.petId);
        if (pet == null) {
          return const SizedBox.shrink();
        }
        if (!_isEditing) {
          _syncDraftFromTodo(todo);
        }

        return Scaffold(
          key: ValueKey('todo-detail-page-${todo.id}'),
          appBar: AppBar(
            title: Text(_isEditing ? '编辑待办' : '待办详情'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_isEditing) {
                  _cancelEditing();
                }
                Navigator.pop(context);
              },
            ),
            actions: [
              if (!_isEditing)
                TextButton(
                  key: const ValueKey('todo-detail-edit-button'),
                  onPressed: () => _beginEditing(todo),
                  child: const Text('编辑'),
                )
              else ...[
                TextButton(
                  key: const ValueKey('todo-detail-cancel-button'),
                  onPressed: _cancelEditing,
                  child: const Text('取消'),
                ),
                TextButton(
                  key: const ValueKey('todo-detail-save-button'),
                  onPressed: () => _saveChanges(todo),
                  child: const Text('保存'),
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            children: _isEditing
                ? _buildEditChildren(context, pet)
                : _buildViewChildren(context, pet, todo),
          ),
        );
      },
    );
  }

  List<Widget> _buildViewChildren(
    BuildContext context,
    Pet pet,
    TodoItem todo,
  ) {
    final statusLabel =
        _todoStatusLabelForUi(_effectiveTodoStatusForUi(todo, widget.store.referenceNow));
    return [
      PageHeader(
        title: todo.title,
        subtitle: '${pet.name} · 待办',
      ),
      HeroPanel(
        title: '待办概览',
        subtitle:
            '${formatDate(todo.dueAt)} · ${notificationLeadTimeLabel(todo.notificationLeadTime)}',
        child: HyperBadge(
          text: statusLabel,
          foreground: const Color(0xFF335FCA),
          background: const Color(0xFFEAF0FF),
        ),
      ),
      SectionCard(
        title: '待办信息',
        children: [
          InfoRow(label: '关联爱宠', value: pet.name),
          InfoRow(label: '时间', value: formatDate(todo.dueAt)),
          InfoRow(
            label: '提前通知',
            value: notificationLeadTimeLabel(todo.notificationLeadTime),
          ),
          InfoRow(label: '当前状态', value: statusLabel),
        ],
      ),
      if (todo.note.trim().isNotEmpty)
        SectionCard(
          title: '补充说明',
          children: [
            Text(
              todo.note.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _buildEditChildren(BuildContext context, Pet pet) {
    return [
      PageHeader(
        title: _titleController.text.trim().isEmpty
            ? '编辑待办'
            : _titleController.text.trim(),
        subtitle: '${pet.name} · 调整待办安排',
      ),
      SectionCard(
        title: '待办信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(
            key: const ValueKey('todo-detail-title-field'),
            controller: _titleController,
            hintText: '输入待办标题',
          ),
          const SectionLabel(text: '关联爱宠'),
          PetSelector(
            pets: widget.store.pets,
            value: _petId ?? pet.id,
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SectionLabel(text: '时间'),
          AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('todo-detail-due-at-field'),
            iosDateFieldKey: const ValueKey('todo-detail-due-date-ios'),
            iosTimeFieldKey: const ValueKey('todo-detail-due-time-ios'),
            value: _dueAt ?? DateTime.now(),
            onChanged: (value) => setState(() => _dueAt = value),
          ),
          const SectionLabel(text: '提前通知'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _leadTimeOptions
                .map(
                  (value) => _ChecklistLeadTimeChip(
                    key: ValueKey('todo-detail-lead-time-${value.name}'),
                    label: notificationLeadTimeLabel(value),
                    selected: _notificationLeadTime == value,
                    accentColor: const Color(0xFF4F7BFF),
                    onTap: () => setState(() => _notificationLeadTime = value),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
      SectionCard(
        title: '补充信息',
        children: [
          const SectionLabel(text: '补充说明'),
          HyperTextField(
            key: const ValueKey('todo-detail-note-field'),
            controller: _noteController,
            hintText: '补充背景、要求或注意事项',
            maxLines: 3,
          ),
        ],
      ),
    ];
  }

  void _beginEditing(TodoItem todo) {
    _editingSnapshot = _TodoEditSnapshot.fromTodo(todo);
    _syncDraftFromSnapshot(_editingSnapshot!);
    setState(() {});
  }

  void _cancelEditing() {
    final snapshot = _editingSnapshot;
    if (snapshot == null) {
      return;
    }
    _syncDraftFromSnapshot(snapshot);
    _editingSnapshot = null;
    setState(() {});
  }

  Future<void> _saveChanges(TodoItem todo) async {
    await widget.store.updateTodo(
      todoId: todo.id,
      petId: _petId ?? todo.petId,
      title: _titleController.text.trim(),
      dueAt: _dueAt ?? todo.dueAt,
      notificationLeadTime: _notificationLeadTime,
      note: _noteController.text.trim(),
    );
    _editingSnapshot = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _syncDraftFromTodo(TodoItem todo) {
    _titleController.text = todo.title;
    _noteController.text = todo.note;
    _petId = todo.petId;
    _dueAt = todo.dueAt;
    _notificationLeadTime = todo.notificationLeadTime;
  }

  void _syncDraftFromSnapshot(_TodoEditSnapshot snapshot) {
    _titleController.text = snapshot.title;
    _noteController.text = snapshot.note;
    _petId = snapshot.petId;
    _dueAt = snapshot.dueAt;
    _notificationLeadTime = snapshot.notificationLeadTime;
  }
}

class ReminderDetailPage extends StatefulWidget {
  const ReminderDetailPage({
    super.key,
    required this.store,
    required this.reminderId,
  });

  final PetNoteStore store;
  final String reminderId;

  @override
  State<ReminderDetailPage> createState() => _ReminderDetailPageState();
}

class _ReminderDetailPageState extends State<ReminderDetailPage> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  _ReminderEditSnapshot? _editingSnapshot;
  String? _petId;
  DateTime? _scheduledAt;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.oneDay;
  ReminderKind _kind = ReminderKind.custom;

  bool get _isEditing => _editingSnapshot != null;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final reminder = widget.store.reminderById(widget.reminderId);
        if (reminder == null) {
          return _buildDeletedScaffold(context, '提醒已不存在');
        }
        final pet = widget.store.petById(_petId ?? reminder.petId) ??
            widget.store.petById(reminder.petId);
        if (pet == null) {
          return const SizedBox.shrink();
        }
        if (!_isEditing) {
          _syncDraftFromReminder(reminder);
        }

        return Scaffold(
          key: ValueKey('reminder-detail-page-${reminder.id}'),
          appBar: AppBar(
            title: Text(_isEditing ? '编辑提醒' : '提醒详情'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_isEditing) {
                  _cancelEditing();
                }
                Navigator.pop(context);
              },
            ),
            actions: [
              if (!_isEditing)
                TextButton(
                  key: const ValueKey('reminder-detail-edit-button'),
                  onPressed: () => _beginEditing(reminder),
                  child: const Text('编辑'),
                )
              else ...[
                TextButton(
                  key: const ValueKey('reminder-detail-cancel-button'),
                  onPressed: _cancelEditing,
                  child: const Text('取消'),
                ),
                TextButton(
                  key: const ValueKey('reminder-detail-save-button'),
                  onPressed: () => _saveChanges(reminder),
                  child: const Text('保存'),
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            children: _isEditing
                ? _buildEditChildren(context, pet, reminder)
                : _buildViewChildren(context, pet, reminder),
          ),
        );
      },
    );
  }

  List<Widget> _buildViewChildren(
    BuildContext context,
    Pet pet,
    ReminderItem reminder,
  ) {
    final statusLabel = _petReminderStatusLabel(
      _effectiveReminderStatusForUi(reminder, widget.store.referenceNow),
    );
    return [
      PageHeader(
        title: reminder.title,
        subtitle: '${pet.name} · ${_reminderKindLabel(reminder.kind)}',
      ),
      HeroPanel(
        title: '下次提醒时间',
        subtitle:
            '${formatDate(reminder.scheduledAt)} · ${notificationLeadTimeLabel(reminder.notificationLeadTime)}',
        child: HyperBadge(
          text: statusLabel,
          foreground: const Color(0xFFC57A14),
          background: const Color(0xFFFFF1DD),
        ),
      ),
      SectionCard(
        title: '提醒信息',
        children: [
          InfoRow(label: '关联爱宠', value: pet.name),
          InfoRow(label: '提醒类型', value: _reminderKindLabel(reminder.kind)),
          InfoRow(label: '提醒时间', value: formatDate(reminder.scheduledAt)),
          InfoRow(
            label: '提前通知',
            value: notificationLeadTimeLabel(reminder.notificationLeadTime),
          ),
          InfoRow(label: '重复频率', value: reminder.recurrence),
          InfoRow(label: '当前状态', value: statusLabel),
        ],
      ),
      if (reminder.note.trim().isNotEmpty)
        SectionCard(
          title: '提醒备注',
          children: [
            Text(
              reminder.note.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _buildEditChildren(
    BuildContext context,
    Pet pet,
    ReminderItem reminder,
  ) {
    final leadTimeOptions = _buildReminderLeadTimeOptions(
      current: reminder.notificationLeadTime,
    );
    return [
      PageHeader(
        title: _titleController.text.trim().isEmpty
            ? '编辑提醒'
            : _titleController.text.trim(),
        subtitle: '${pet.name} · 调整提醒安排',
      ),
      SectionCard(
        title: '提醒信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(
            key: const ValueKey('reminder-detail-title-field'),
            controller: _titleController,
            hintText: '输入提醒标题',
          ),
          const SectionLabel(text: '关联爱宠'),
          PetSelector(
            pets: widget.store.pets,
            value: _petId ?? pet.id,
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SectionLabel(text: '提醒类型'),
          ChoiceWrap<ReminderKind>(
            values: ReminderKind.values,
            selected: _kind,
            labelBuilder: _reminderKindLabel,
            onChanged: (value) => setState(() => _kind = value),
          ),
          const SectionLabel(text: '提醒时间'),
          AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('reminder-detail-scheduled-at'),
            iosDateFieldKey:
                const ValueKey('reminder-detail-scheduled-date-ios'),
            iosTimeFieldKey:
                const ValueKey('reminder-detail-scheduled-time-ios'),
            value: _scheduledAt ?? DateTime.now(),
            onChanged: (value) => setState(() => _scheduledAt = value),
          ),
          const SectionLabel(text: '提前通知'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: leadTimeOptions
                .map(
                  (value) => _ChecklistLeadTimeChip(
                    key: ValueKey('reminder-detail-lead-time-${value.name}'),
                    label: notificationLeadTimeLabel(value),
                    selected: _notificationLeadTime == value,
                    accentColor: const Color(0xFFF2A65A),
                    onTap: () => setState(() => _notificationLeadTime = value),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
      SectionCard(
        title: '补充信息',
        children: [
          const SectionLabel(text: '补充说明'),
          HyperTextField(
            key: const ValueKey('reminder-detail-note-field'),
            controller: _noteController,
            hintText: '补充准备事项或注意点',
            maxLines: 3,
          ),
        ],
      ),
    ];
  }

  void _beginEditing(ReminderItem reminder) {
    _editingSnapshot = _ReminderEditSnapshot.fromReminder(reminder);
    _syncDraftFromSnapshot(_editingSnapshot!);
    setState(() {});
  }

  void _cancelEditing() {
    final snapshot = _editingSnapshot;
    if (snapshot == null) {
      return;
    }
    _syncDraftFromSnapshot(snapshot);
    _editingSnapshot = null;
    setState(() {});
  }

  Future<void> _saveChanges(ReminderItem reminder) async {
    await widget.store.updateReminder(
      reminderId: reminder.id,
      petId: _petId ?? reminder.petId,
      kind: _kind,
      title: _titleController.text.trim(),
      scheduledAt: _scheduledAt ?? reminder.scheduledAt,
      notificationLeadTime: _notificationLeadTime,
      note: _noteController.text.trim(),
    );
    _editingSnapshot = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _syncDraftFromReminder(ReminderItem reminder) {
    _titleController.text = reminder.title;
    _noteController.text = reminder.note;
    _petId = reminder.petId;
    _scheduledAt = reminder.scheduledAt;
    _notificationLeadTime = reminder.notificationLeadTime;
    _kind = reminder.kind;
  }

  void _syncDraftFromSnapshot(_ReminderEditSnapshot snapshot) {
    _titleController.text = snapshot.title;
    _noteController.text = snapshot.note;
    _petId = snapshot.petId;
    _scheduledAt = snapshot.scheduledAt;
    _notificationLeadTime = snapshot.notificationLeadTime;
    _kind = snapshot.kind;
  }
}

class _ChecklistLeadTimeChip extends StatelessWidget {
  const _ChecklistLeadTimeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? accentColor : const Color(0xFFF6F7FA),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: selected ? 0.18 : 0.08),
                blurRadius: selected ? 14 : 8,
                offset: Offset(0, selected ? 8 : 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : const Color(0xFF6C7280),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _TodoEditSnapshot {
  const _TodoEditSnapshot({
    required this.petId,
    required this.title,
    required this.dueAt,
    required this.notificationLeadTime,
    required this.note,
  });

  final String petId;
  final String title;
  final DateTime dueAt;
  final NotificationLeadTime notificationLeadTime;
  final String note;

  factory _TodoEditSnapshot.fromTodo(TodoItem todo) {
    return _TodoEditSnapshot(
      petId: todo.petId,
      title: todo.title,
      dueAt: todo.dueAt,
      notificationLeadTime: todo.notificationLeadTime,
      note: todo.note,
    );
  }
}

class _ReminderEditSnapshot {
  const _ReminderEditSnapshot({
    required this.petId,
    required this.title,
    required this.scheduledAt,
    required this.notificationLeadTime,
    required this.kind,
    required this.note,
  });

  final String petId;
  final String title;
  final DateTime scheduledAt;
  final NotificationLeadTime notificationLeadTime;
  final ReminderKind kind;
  final String note;

  factory _ReminderEditSnapshot.fromReminder(ReminderItem reminder) {
    return _ReminderEditSnapshot(
      petId: reminder.petId,
      title: reminder.title,
      scheduledAt: reminder.scheduledAt,
      notificationLeadTime: reminder.notificationLeadTime,
      kind: reminder.kind,
      note: reminder.note,
    );
  }
}

Scaffold _buildDeletedScaffold(BuildContext context, String title) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('详情'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: PageEmptyStateBlock(
      emptyTitle: title,
      emptySubtitle: '这条内容可能已经被删除或同步更新。',
      actionLabel: '返回',
      onAction: () => Navigator.pop(context),
    ),
  );
}

TodoStatus _effectiveTodoStatusForUi(TodoItem item, DateTime referenceNow) {
  if (item.status == TodoStatus.done ||
      item.status == TodoStatus.skipped ||
      item.status == TodoStatus.overdue) {
    return item.status;
  }
  if (item.dueAt.isBefore(referenceNow)) {
    return TodoStatus.overdue;
  }
  return item.status;
}

ReminderStatus _effectiveReminderStatusForUi(
  ReminderItem item,
  DateTime referenceNow,
) {
  if (item.status == ReminderStatus.done ||
      item.status == ReminderStatus.skipped ||
      item.status == ReminderStatus.overdue) {
    return item.status;
  }
  if (item.scheduledAt.isBefore(referenceNow)) {
    return ReminderStatus.overdue;
  }
  return item.status;
}

String _todoStatusLabelForUi(TodoStatus status) {
  switch (status) {
    case TodoStatus.done:
      return '已完成';
    case TodoStatus.postponed:
      return '已延后';
    case TodoStatus.skipped:
      return '已跳过';
    case TodoStatus.overdue:
      return '已逾期';
    case TodoStatus.open:
      return '待处理';
  }
}

List<NotificationLeadTime> _buildReminderLeadTimeOptions({
  required NotificationLeadTime current,
}) {
  const defaults = <NotificationLeadTime>[
    NotificationLeadTime.oneDay,
    NotificationLeadTime.threeDays,
    NotificationLeadTime.sevenDays,
  ];
  if (defaults.contains(current)) {
    return defaults;
  }
  return <NotificationLeadTime>[current, ...defaults];
}
