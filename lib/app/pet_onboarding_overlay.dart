import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/pet_onboarding_taxonomy.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class PetOnboardingResult {
  const PetOnboardingResult({
    required this.name,
    required this.type,
    required this.breed,
    required this.sex,
    required this.birthday,
    required this.weightKg,
    required this.neuterStatus,
    required this.feedingPreferences,
    required this.allergies,
    required this.note,
  });

  final String name;
  final PetType type;
  final String breed;
  final String sex;
  final String birthday;
  final double weightKg;
  final PetNeuterStatus neuterStatus;
  final String feedingPreferences;
  final String allergies;
  final String note;
}

class PetOnboardingOverlay extends StatefulWidget {
  const PetOnboardingOverlay({
    super.key,
    required this.onSubmit,
    required this.onDefer,
  });

  final Future<void> Function(PetOnboardingResult result) onSubmit;
  final Future<void> Function() onDefer;

  @override
  State<PetOnboardingOverlay> createState() => _PetOnboardingOverlayState();
}

class _PetOnboardingOverlayState extends State<PetOnboardingOverlay> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox.expand(
      child: Material(
        key: const ValueKey('first_launch_onboarding_overlay'),
        color: theme.scaffoldBackgroundColor.withValues(
          alpha: isDark ? 0.92 : 0.80,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
            ),
          ),
          child: PetOnboardingFlow(
            onSubmit: widget.onSubmit,
            onDefer: widget.onDefer,
          ),
        ),
      ),
    );
  }
}

class PetOnboardingFlow extends StatefulWidget {
  const PetOnboardingFlow({
    super.key,
    required this.onSubmit,
    required this.onDefer,
    this.embedded = false,
  });

  final Future<void> Function(PetOnboardingResult result) onSubmit;
  final Future<void> Function() onDefer;
  final bool embedded;

  @override
  State<PetOnboardingFlow> createState() => _PetOnboardingFlowState();
}

class _PetOnboardingFlowState extends State<PetOnboardingFlow> {
  final _name = TextEditingController();
  final _customBreed = TextEditingController();
  final _feeding = TextEditingController();
  final _allergies = TextEditingController();
  final _note = TextEditingController();
  final _weight = TextEditingController();

  int _stepIndex = 0;
  PetType? _type;
  String? _breed;
  String? _sex;
  DateTime? _birthday;
  PetNeuterStatus? _neuterStatus;
  bool _isSubmitting = false;

  static const List<_StepCopy> _steps = [
    _StepCopy('先认识一下', '先给爱宠起个名字，并告诉我它是什么类型。'),
    _StepCopy('选择品种', '根据类型给你准备了常见品种，也可以直接自填。'),
    _StepCopy('记录性别', '完善基础档案，让后续信息更准确。'),
    _StepCopy('选择生日', '用日期选择器记录生日，后续更方便查看成长阶段。'),
    _StepCopy('补充体重', '体重用 kg 记录，先填当前最接近的一次就可以。'),
    _StepCopy('绝育状态', '这一步可以跳过，后面随时还能再补。'),
    _StepCopy('喂养偏好', '饮食习惯、主粮口味和喂养方式都可以记下来。'),
    _StepCopy('过敏 / 禁忌', '已知过敏原或需要回避的食物、药物都可以先补充。'),
    _StepCopy('最后备注', '把容易忘的小提醒留在这里，保存后就会生成第一份档案。'),
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _name,
      _customBreed,
      _feeding,
      _allergies,
      _note,
      _weight
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _customBreed,
      _feeding,
      _allergies,
      _note,
      _weight
    ]) {
      controller.removeListener(_onFieldChanged);
    }
    _name.dispose();
    _customBreed.dispose();
    _feeding.dispose();
    _allergies.dispose();
    _note.dispose();
    _weight.dispose();
    super.dispose();
  }

  bool get _showSkipButton => _stepIndex >= 5 && _stepIndex <= 7;

  bool get _canContinue {
    switch (_stepIndex) {
      case 0:
        return _name.text.trim().isNotEmpty && _type != null;
      case 1:
        if (_breed == null) {
          return false;
        }
        if (_breed == otherBreedLabel) {
          return _customBreed.text.trim().isNotEmpty;
        }
        return true;
      case 2:
        return _sex != null;
      case 3:
        return _birthday != null;
      case 4:
        final parsed = double.tryParse(_weight.text.trim());
        return parsed != null && parsed > 0;
      case 5:
      case 6:
      case 7:
      case 8:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final step = _steps[_stepIndex];
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    final topInset = widget.embedded ? 8.0 : insets.top + 12;
    final bottomInset = widget.embedded ? 8.0 : insets.bottom + 20;

    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(context),
            const SizedBox(height: 18),
            Text(
              step.title,
              style: theme.textTheme.displaySmall?.copyWith(
                color: tokens.primaryText,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.subtitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: _buildStepCard(context),
              ),
            ),
            const SizedBox(height: 14),
            if (_showSkipButton)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const ValueKey('onboarding_skip_button'),
                    onPressed: _isSubmitting ? null : _skipCurrentStep,
                    child: const Text('跳过'),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey(
                  _stepIndex == _steps.length - 1
                      ? 'onboarding_save_button'
                      : 'onboarding_continue_button',
                ),
                onPressed: _isSubmitting
                    ? null
                    : _stepIndex == _steps.length - 1
                        ? _save
                        : (_canContinue ? _goNext : null),
                child: Text(_stepIndex == _steps.length - 1 ? '保存爱宠' : '继续'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: _stepIndex > 0
                ? IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() => _stepIndex -= 1),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
          ),
          Expanded(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    key: const ValueKey('onboarding_progress_bar'),
                    value: (_stepIndex + 1) / _steps.length,
                    minHeight: 8,
                    backgroundColor: tokens.secondarySurface,
                    valueColor:
                        AlwaysStoppedAnimation(theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: TextButton(
              key: const ValueKey('onboarding_defer_button'),
              onPressed: _isSubmitting ? null : widget.onDefer,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '稍后',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tokens.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(BuildContext context) {
    return SectionCard(
      title: '步骤 ${_stepIndex + 1}',
      children: switch (_stepIndex) {
        0 => _identityStep(),
        1 => _breedStep(),
        2 => _sexStep(),
        3 => _birthdayStep(),
        4 => _weightStep(),
        5 => _neuterStep(),
        6 => _textAreaStep(
            label: '喂养偏好',
            controller: _feeding,
            hintText: '比如主粮口味、喂食频率、零食偏好',
          ),
        7 => _textAreaStep(
            label: '过敏 / 禁忌',
            controller: _allergies,
            hintText: '比如鸡肉敏感、对某些零食不耐受',
          ),
        _ => _textAreaStep(
            label: '备注',
            controller: _note,
            hintText: '比如洗澡会紧张、外出需要安抚等',
          ),
      },
    );
  }

  List<Widget> _identityStep() {
    return [
      const SectionLabel(text: '名字'),
      HyperTextField(
        key: const ValueKey('onboarding_name_field'),
        controller: _name,
        hintText: '给爱宠起个名字',
      ),
      const SectionLabel(text: '宠物类型'),
      _OptionWrap<PetType>(
        values: PetType.values,
        selected: _type,
        labelBuilder: petTypeLabel,
        onTap: (value) => setState(() {
          _type = value;
          _breed = null;
          _customBreed.clear();
        }),
      ),
    ];
  }

  List<Widget> _breedStep() {
    final type = _type ?? PetType.other;
    final presets = petBreedPresets[type] ?? const [otherBreedLabel];
    return [
      SectionLabel(text: '${petTypeLabel(type)}的常见品种'),
      _OptionWrap<String>(
        values: presets,
        selected: _breed,
        labelBuilder: (value) => value,
        onTap: (value) => setState(() => _breed = value),
      ),
      if (_breed == otherBreedLabel) ...[
        const SectionLabel(text: '自定义品种'),
        HyperTextField(
          key: const ValueKey('onboarding_custom_breed_field'),
          controller: _customBreed,
          hintText: '输入具体品种或描述',
        ),
      ],
    ];
  }

  List<Widget> _sexStep() {
    return [
      const SectionLabel(text: '性别'),
      _OptionWrap<String>(
        values: const ['公', '母'],
        selected: _sex,
        labelBuilder: (value) => value,
        onTap: (value) => setState(() => _sex = value),
      ),
    ];
  }

  List<Widget> _birthdayStep() {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    final now = DateTime.now();
    final latestBirthday = DateTime(now.year + 25, 12, 31);
    final calendarTheme = theme.copyWith(
      datePickerTheme: DatePickerThemeData(
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.secondary;
          }
          return tokens.primaryText;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.secondary;
          }
          return tokens.primaryText;
        }),
        todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return Colors.transparent;
        }),
        todayBorder: BorderSide.none,
      ),
    );
    return [
      Text(
        _birthday == null
            ? '请选择生日'
            : '已选择 ${_formatBirthdayDisplay(_birthday!)}',
        style: TextStyle(
          color: tokens.primaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
      Theme(
        data: calendarTheme,
        child: CalendarDatePicker(
          initialDate: _birthday,
          currentDate: now,
          firstDate: DateTime(now.year - 25),
          lastDate: latestBirthday,
          onDateChanged: (value) => setState(() => _birthday = value),
        ),
      ),
    ];
  }

  List<Widget> _weightStep() {
    return [
      const SectionLabel(text: '当前体重（kg）'),
      TextField(
        key: const ValueKey('onboarding_weight_field'),
        controller: _weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '例如 4.2'),
      ),
    ];
  }

  List<Widget> _neuterStep() {
    return [
      const SectionLabel(text: '绝育状态'),
      _OptionWrap<PetNeuterStatus>(
        values: const [
          PetNeuterStatus.neutered,
          PetNeuterStatus.notNeutered,
        ],
        selected: _neuterStatus,
        labelBuilder: petNeuterStatusLabel,
        onTap: (value) => setState(() => _neuterStatus = value),
      ),
    ];
  }

  List<Widget> _textAreaStep({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return [
      SectionLabel(text: label),
      HyperTextField(
        controller: controller,
        hintText: hintText,
        maxLines: 4,
      ),
    ];
  }

  void _goNext() {
    setState(() => _stepIndex += 1);
  }

  void _skipCurrentStep() {
    if (_stepIndex == _steps.length - 1) {
      _save();
      return;
    }
    if (_stepIndex < _steps.length - 1) {
      setState(() => _stepIndex += 1);
    }
  }

  Future<void> _save() async {
    setState(() => _isSubmitting = true);
    try {
      final result = PetOnboardingResult(
        name: _name.text.trim(),
        type: _type ?? PetType.other,
        breed: _breed == otherBreedLabel
            ? _customBreed.text.trim()
            : (_breed ?? otherBreedLabel),
        sex: _sex ?? '未填写',
        birthday: _formatBirthday(_birthday!),
        weightKg: double.parse(_weight.text.trim()),
        neuterStatus: _neuterStatus ?? PetNeuterStatus.unknown,
        feedingPreferences: _textOrDefault(_feeding.text),
        allergies: _textOrDefault(_allergies.text),
        note: _textOrDefault(_note.text),
      );
      await widget.onSubmit(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _textOrDefault(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '未填写' : trimmed;
  }

  String _formatBirthday(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatBirthdayDisplay(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}年$month月$day日';
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _StepCopy {
  const _StepCopy(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _OptionWrap<T> extends StatelessWidget {
  const _OptionWrap({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onTap,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petCareTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values.map((value) {
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? tokens.segmentedSelectedBackground
                  : tokens.secondarySurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              labelBuilder(value),
              style: theme.textTheme.labelLarge?.copyWith(
                color: isSelected ? Colors.white : tokens.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
