import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/pet_care_pages.dart';
import 'package:pet_care_harmony/app/pet_onboarding_overlay.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

enum AddAction { none, todo, reminder, record, pet }

enum _AddSheetStage { actions, expandedForm, petOnboarding }

class AddActionSheet extends StatefulWidget {
  const AddActionSheet({
    super.key,
    required this.store,
  });

  final PetCareStore store;

  @override
  State<AddActionSheet> createState() => _AddActionSheetState();
}

class _AddActionSheetState extends State<AddActionSheet> {
  static const _compactSheetHeight = 430.0;
  static const _sheetRadius = 36.0;

  AddAction _action = AddAction.none;
  Timer? _transitionTimer;
  bool _showTransitionGrid = false;

  bool get _isActionGrid => _action == AddAction.none;
  bool get _isPetOnboarding => _action == AddAction.pet;
  _AddSheetStage get _stage {
    if (_isPetOnboarding) {
      return _AddSheetStage.petOnboarding;
    }
    if (_isActionGrid) {
      return _AddSheetStage.actions;
    }
    return _AddSheetStage.expandedForm;
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.padding.top - 12;
    final isPetOnboarding = _isPetOnboarding;
    final tokens = context.petCareTokens;
    final sheetHeight = switch (_stage) {
      _AddSheetStage.actions => _compactSheetHeight,
      _AddSheetStage.expandedForm => availableHeight,
      _AddSheetStage.petOnboarding => availableHeight,
    };

    return ClipRRect(
      key: const ValueKey('add_sheet_shell'),
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: sheetHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 4,
              bottom: mediaQuery.viewInsets.bottom + 18,
            ),
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _buildHeader(context),
                ),
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (!_isActionGrid) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    return Padding(
      key: ValueKey(_stage),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _action == AddAction.none ? '新增内容' : _sheetTitle(_action),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _action == AddAction.none
                      ? '今天要给小宝加点什么新内容？'
                      : '保存后会自动跳转详情页面。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (!_isActionGrid)
            IconButton(
              onPressed: () => setState(() => _action = AddAction.none),
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              color: tokens.secondaryText,
              splashRadius: 18,
              tooltip: '返回',
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isPetOnboarding) {
      return _buildExpandedTransition(
        key: const ValueKey('manual_onboarding_sheet_transition'),
        child: PetOnboardingFlow(
          embedded: true,
          onSubmit: _submitPetOnboarding,
          onDefer: _closePetOnboarding,
        ),
      );
    }

    if (_isActionGrid) {
      return Align(
        key: const ValueKey('add_actions_boundary'),
        alignment: Alignment.topCenter,
        child: RepaintBoundary(
          child: _ActionGrid(
            key: const ValueKey('actions'),
            onSelect: _selectAction,
          ),
        ),
      );
    }

    return _buildExpandedTransition(
      key: const ValueKey('manual_expanded_form_transition'),
      child: RepaintBoundary(
        key: const ValueKey('add_form_boundary'),
        child: _ExpandedFormShell(
          title: _sheetTitle(_action),
          onBack: _resetToActions,
          child: KeyedSubtree(
            key: ValueKey('${_action.name}_${widget.store.pets.isEmpty}'),
            child: _buildExpandedFormBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedFormBody() {
    if (widget.store.pets.isEmpty) {
      return _MissingPetPrerequisite(
        action: _action,
        onAddPet: _openPetOnboarding,
      );
    }

    return switch (_action) {
      AddAction.todo =>
        _TodoForm(key: const ValueKey('todo'), store: widget.store),
      AddAction.reminder =>
        _ReminderForm(key: const ValueKey('reminder'), store: widget.store),
      AddAction.record =>
        _RecordForm(key: const ValueKey('record'), store: widget.store),
      AddAction.pet => const SizedBox.shrink(),
      AddAction.none => const SizedBox.shrink(),
    };
  }

  Widget _buildExpandedTransition({
    required Key key,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, progress, expandedChild) {
        final collapseProgress =
            Curves.easeInCubic.transform((progress / 0.3).clamp(0.0, 1.0));
        final revealProgress = Curves.easeOutCubic
            .transform(((progress - 0.38) / 0.62).clamp(0.0, 1.0));

        return Stack(
          fit: StackFit.expand,
          children: [
            if (_showTransitionGrid)
              IgnorePointer(
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1 - collapseProgress,
                    child: Transform.translate(
                      offset: Offset(0, -48 * collapseProgress),
                      child: Opacity(
                        opacity: 1 - collapseProgress,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: RepaintBoundary(
                            child: _ActionGrid(
                              onSelect: (_) {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            IgnorePointer(
              ignoring: revealProgress < 0.999,
              child: Transform.translate(
                offset: Offset(0, 44 * (1 - revealProgress)),
                child: Opacity(
                  opacity: revealProgress,
                  child: expandedChild,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitPetOnboarding(PetOnboardingResult result) async {
    await widget.store.addPet(
      name: result.name,
      type: result.type,
      breed: result.breed,
      sex: result.sex,
      birthday: result.birthday,
      weightKg: result.weightKg,
      neuterStatus: result.neuterStatus,
      feedingPreferences: result.feedingPreferences,
      allergies: result.allergies,
      note: result.note,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _closePetOnboarding() async {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _selectAction(AddAction action) {
    _transitionTimer?.cancel();
    if (action == AddAction.none) {
      _resetToActions();
      return;
    }

    setState(() {
      _action = action;
      _showTransitionGrid = true;
    });
    _transitionTimer = Timer(const Duration(milliseconds: 96), () {
      if (!mounted) {
        return;
      }
      setState(() => _showTransitionGrid = false);
    });
  }

  void _resetToActions() {
    _transitionTimer?.cancel();
    setState(() {
      _action = AddAction.none;
      _showTransitionGrid = false;
    });
  }

  void _openPetOnboarding() {
    _transitionTimer?.cancel();
    setState(() {
      _action = AddAction.pet;
      _showTransitionGrid = false;
    });
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({super.key, required this.onSelect});

  final ValueChanged<AddAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petCareTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                title: '新增待办',
                subtitle: '补货、清洁和轻任务',
                icon: Icons.check_circle_outline_rounded,
                color: tokens.badgeBlueBackground,
                iconColor: tokens.badgeBlueForeground,
                onTap: () => onSelect(AddAction.todo),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                title: '新增提醒',
                subtitle: '疫苗、驱虫和复诊',
                icon: Icons.notifications_active_rounded,
                color: tokens.badgeGoldBackground,
                iconColor: tokens.badgeGoldForeground,
                onTap: () => onSelect(AddAction.reminder),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                title: '新增记录',
                subtitle: '病历、票据和照片',
                icon: Icons.description_rounded,
                color:
                    isDark ? const Color(0xFF271F3B) : const Color(0xFFF4EEFF),
                iconColor:
                    isDark ? const Color(0xFFD2BEFF) : const Color(0xFF7250D0),
                onTap: () => onSelect(AddAction.record),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                title: '新增爱宠',
                subtitle: '新建宠物完整档案',
                icon: Icons.pets_rounded,
                color:
                    isDark ? const Color(0xFF173126) : const Color(0xFFEAF8EF),
                iconColor:
                    isDark ? const Color(0xFF9EDBBC) : const Color(0xFF2F8B63),
                onTap: () => onSelect(AddAction.pet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    return FrostedPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryText,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodoForm extends StatefulWidget {
  const _TodoForm({super.key, required this.store});

  final PetCareStore store;

  @override
  State<_TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<_TodoForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  final _dueAt = DateTime.parse('2026-03-25T09:00:00+08:00');
  late final TextEditingController _dueAtText;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _dueAtText = TextEditingController(text: formatDate(_dueAt));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _dueAtText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          title: '基础信息',
          children: [
            const SectionLabel(text: '标题'),
            HyperTextField(controller: _title, hintText: '例如：补货主粮'),
            const SectionLabel(text: '关联爱宠'),
            _PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value)),
            const SectionLabel(text: '时间'),
            HyperTextField(controller: _dueAtText, readOnly: true),
            const SectionLabel(text: '备注'),
            HyperTextField(
                controller: _note, hintText: '记录一下补货偏好', maxLines: 3),
          ],
        ),
        FilledButton(
          onPressed: () {
            widget.store.addTodo(
                title: _title.text.trim(),
                petId: _petId,
                dueAt: _dueAt,
                note: _note.text.trim());
            Navigator.pop(context);
          },
          child: const Text('保存待办'),
        ),
      ],
    );
  }
}

class _ReminderForm extends StatefulWidget {
  const _ReminderForm({super.key, required this.store});

  final PetCareStore store;

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _recurrence = TextEditingController(text: '单次');
  late String _petId;
  ReminderKind _kind = ReminderKind.custom;
  final _scheduledAt = DateTime.parse('2026-03-25T20:00:00+08:00');
  late final TextEditingController _scheduledAtText;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _scheduledAtText = TextEditingController(text: formatDate(_scheduledAt));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _recurrence.dispose();
    _scheduledAtText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          title: '提醒信息',
          children: [
            const SectionLabel(text: '标题'),
            HyperTextField(controller: _title, hintText: '例如：体内驱虫'),
            const SectionLabel(text: '关联爱宠'),
            _PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value)),
            const SectionLabel(text: '提醒类型'),
            _ChoiceWrap<ReminderKind>(
              values: ReminderKind.values,
              selected: _kind,
              labelBuilder: _reminderKindLabel,
              onChanged: (value) => setState(() => _kind = value),
            ),
            const SectionLabel(text: '时间'),
            HyperTextField(controller: _scheduledAtText, readOnly: true),
            const SectionLabel(text: '重复规则'),
            HyperTextField(controller: _recurrence),
            const SectionLabel(text: '备注'),
            HyperTextField(controller: _note, maxLines: 3),
          ],
        ),
        FilledButton(
          onPressed: () {
            widget.store.addReminder(
              title: _title.text.trim(),
              petId: _petId,
              scheduledAt: _scheduledAt,
              kind: _kind,
              recurrence: _recurrence.text.trim(),
              note: _note.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text('保存提醒'),
        ),
      ],
    );
  }
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({super.key, required this.store});

  final PetCareStore store;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  PetRecordType _type = PetRecordType.other;
  final _recordDate = DateTime.parse('2026-03-24T19:00:00+08:00');
  late final TextEditingController _recordDateText;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _recordDateText = TextEditingController(text: formatDate(_recordDate));
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _note.dispose();
    _recordDateText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          title: '资料信息',
          children: [
            const SectionLabel(text: '关联爱宠'),
            _PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value)),
            const SectionLabel(text: '记录类型'),
            _ChoiceWrap<PetRecordType>(
              values: PetRecordType.values,
              selected: _type,
              labelBuilder: _recordTypeLabel,
              onChanged: (value) => setState(() => _type = value),
            ),
            const SectionLabel(text: '标题'),
            HyperTextField(controller: _title, hintText: '例如：体检结果'),
            const SectionLabel(text: '时间'),
            HyperTextField(controller: _recordDateText, readOnly: true),
            const SectionLabel(text: '摘要'),
            HyperTextField(controller: _summary, maxLines: 3),
            const SectionLabel(text: '备注'),
            HyperTextField(controller: _note, maxLines: 3),
          ],
        ),
        FilledButton(
          onPressed: () {
            widget.store.addRecord(
              petId: _petId,
              type: _type,
              title: _title.text.trim(),
              recordDate: _recordDate,
              summary: _summary.text.trim(),
              note: _note.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text('保存记录'),
        ),
      ],
    );
  }
}

class _PetForm extends StatefulWidget {
  const _PetForm({super.key, required this.store});

  final PetCareStore store;

  @override
  State<_PetForm> createState() => _PetFormState();
}

class _PetFormState extends State<_PetForm> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _sex = TextEditingController(text: '未填写');
  final _birthday = TextEditingController(text: '2026-03-24');
  final _weight = TextEditingController(text: '3.5');
  final _feeding = TextEditingController();
  final _allergies = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _sex.dispose();
    _birthday.dispose();
    _weight.dispose();
    _feeding.dispose();
    _allergies.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormShell(
      title: '新增爱宠',
      child: Column(
        children: [
          SectionCard(
            title: '档案信息',
            children: [
              const SectionLabel(text: '名字'),
              HyperTextField(controller: _name),
              const SectionLabel(text: '品种'),
              HyperTextField(controller: _breed),
              const SectionLabel(text: '性别'),
              HyperTextField(controller: _sex),
              const SectionLabel(text: '生日'),
              HyperTextField(controller: _birthday),
              const SectionLabel(text: '体重'),
              HyperTextField(controller: _weight),
              const SectionLabel(text: '喂养偏好'),
              HyperTextField(controller: _feeding, maxLines: 3),
              const SectionLabel(text: '过敏/禁忌'),
              HyperTextField(controller: _allergies, maxLines: 3),
              const SectionLabel(text: '备注'),
              HyperTextField(controller: _note, maxLines: 3),
            ],
          ),
          FilledButton(
            onPressed: () async {
              await widget.store.addPet(
                name: _name.text.trim(),
                type: PetType.other,
                breed: _breed.text.trim(),
                sex: _sex.text.trim(),
                birthday: _birthday.text.trim(),
                weightKg: double.tryParse(_weight.text.trim()) ?? 0,
                neuterStatus: PetNeuterStatus.unknown,
                feedingPreferences: _feeding.text.trim(),
                allergies: _allergies.text.trim(),
                note: _note.text.trim(),
              );
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
            },
            child: const Text('保存爱宠'),
          ),
        ],
      ),
    );
  }
}

class _FormShell extends StatelessWidget {
  const _FormShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF17181C),
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _ExpandedFormShell extends StatelessWidget {
  const _ExpandedFormShell({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  key: const ValueKey('expanded_form_back_button'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: tokens.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: theme.textTheme.displaySmall?.copyWith(
            color: tokens.primaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: child,
          ),
        ),
      ],
    );
  }
}

class _MissingPetPrerequisite extends StatelessWidget {
  const _MissingPetPrerequisite({
    required this.action,
    required this.onAddPet,
  });

  final AddAction action;
  final VoidCallback onAddPet;

  @override
  Widget build(BuildContext context) {
    final message = switch (action) {
      AddAction.todo => '待办需要先关联一只爱宠，建好第一份档案后再安排补货、清洁和轻任务。',
      AddAction.reminder => '提醒需要先关联一只爱宠，建好第一份档案后再安排疫苗、驱虫和复诊。',
      AddAction.record => '记录需要先关联一只爱宠，建好第一份档案后再保存病历、票据和照片。',
      AddAction.pet => '先完成第一只爱宠建档。',
      AddAction.none => '先添加第一只爱宠。',
    };

    return EmptyCard(
      title: '先添加第一只爱宠',
      subtitle: message,
      actionLabel: '开始添加宠物',
      onAction: onAddPet,
    );
  }
}

class _PetSelector extends StatelessWidget {
  const _PetSelector({
    required this.pets,
    required this.value,
    required this.onChanged,
  });

  final List<Pet> pets;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petCareTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: pets
          .map(
            (pet) => GestureDetector(
              onTap: () => onChanged(pet.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: value == pet.id
                      ? tokens.segmentedSelectedBackground
                      : tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pet.name,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: value == pet.id
                            ? Colors.white
                            : tokens.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petCareTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values
          .map(
            (value) => GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected == value
                      ? tokens.segmentedSelectedBackground
                      : tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labelBuilder(value),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected == value
                            ? Colors.white
                            : tokens.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

String _sheetTitle(AddAction action) => switch (action) {
      AddAction.todo => '新增待办',
      AddAction.reminder => '新增提醒',
      AddAction.record => '新增记录',
      AddAction.pet => '新增爱宠',
      AddAction.none => '新增内容',
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
