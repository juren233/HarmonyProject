import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class PetEditSheet extends StatefulWidget {
  const PetEditSheet({
    super.key,
    required this.store,
    required this.pet,
  });

  final PetCareStore store;
  final Pet pet;

  @override
  State<PetEditSheet> createState() => _PetEditSheetState();
}

class _PetEditSheetState extends State<PetEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _weight;
  late final TextEditingController _feeding;
  late final TextEditingController _allergies;
  late final TextEditingController _note;

  late PetType _type;
  late String _sex;
  late PetNeuterStatus _neuterStatus;
  late DateTime _birthday;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.pet.name);
    _breed = TextEditingController(text: widget.pet.breed);
    _weight = TextEditingController(text: widget.pet.weightKg.toString());
    _feeding = TextEditingController(
      text: _emptyDisplayToBlank(widget.pet.feedingPreferences),
    );
    _allergies = TextEditingController(
      text: _emptyDisplayToBlank(widget.pet.allergies),
    );
    _note = TextEditingController(
      text: _emptyDisplayToBlank(widget.pet.note),
    );
    _type = widget.pet.type;
    _sex = widget.pet.sex;
    _neuterStatus = widget.pet.neuterStatus;
    _birthday = DateTime.parse(widget.pet.birthday);

    for (final controller in [
      _name,
      _breed,
      _weight,
      _feeding,
      _allergies,
      _note,
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _breed,
      _weight,
      _feeding,
      _allergies,
      _note,
    ]) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSave {
    final parsedWeight = double.tryParse(_weight.text.trim());
    return _name.text.trim().isNotEmpty &&
        _breed.text.trim().isNotEmpty &&
        parsedWeight != null &&
        parsedWeight > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9F4EE), Color(0xFFF4F5F8)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0x22000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '编辑爱宠资料',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFF17181C),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '更新名字、基础资料和照护备注，保存后会立刻同步到当前档案。',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF6C7280),
                                    ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: '基础信息',
                  children: [
                    const SectionLabel(text: '名字'),
                    HyperTextField(
                      key: const ValueKey('edit_pet_name_field'),
                      controller: _name,
                      hintText: '给爱宠起个名字',
                    ),
                    const SectionLabel(text: '宠物类型'),
                    _EditOptionWrap<PetType>(
                      values: PetType.values,
                      selected: _type,
                      labelBuilder: petTypeLabel,
                      onTap: (value) => setState(() => _type = value),
                    ),
                    const SectionLabel(text: '品种'),
                    HyperTextField(
                      key: const ValueKey('edit_pet_breed_field'),
                      controller: _breed,
                      hintText: '填写品种',
                    ),
                    const SectionLabel(text: '性别'),
                    _EditOptionWrap<String>(
                      values: const ['公', '母'],
                      selected: _sex,
                      labelBuilder: (value) => value,
                      onTap: (value) => setState(() => _sex = value),
                    ),
                    const SectionLabel(text: '生日'),
                    OutlinedButton(
                      key: const ValueKey('edit_pet_birthday_button'),
                      onPressed: _isSaving ? null : _pickBirthday,
                      child: Text(_formatBirthday(_birthday)),
                    ),
                    const SectionLabel(text: '当前体重（kg）'),
                    TextField(
                      key: const ValueKey('edit_pet_weight_field'),
                      controller: _weight,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: '例如 4.2'),
                    ),
                    const SectionLabel(text: '绝育状态'),
                    _EditOptionWrap<PetNeuterStatus>(
                      values: const [
                        PetNeuterStatus.neutered,
                        PetNeuterStatus.notNeutered,
                      ],
                      selected: _neuterStatus == PetNeuterStatus.unknown
                          ? null
                          : _neuterStatus,
                      labelBuilder: petNeuterStatusLabel,
                      onTap: (value) => setState(() => _neuterStatus = value),
                    ),
                  ],
                ),
                SectionCard(
                  title: '照护补充',
                  children: [
                    const SectionLabel(text: '喂养偏好'),
                    HyperTextField(
                      key: const ValueKey('edit_pet_feeding_field'),
                      controller: _feeding,
                      hintText: '比如主粮口味、喂食频率',
                      maxLines: 3,
                    ),
                    const SectionLabel(text: '过敏 / 禁忌'),
                    HyperTextField(
                      key: const ValueKey('edit_pet_allergies_field'),
                      controller: _allergies,
                      hintText: '比如鸡肉敏感、某些药物不耐受',
                      maxLines: 3,
                    ),
                    const SectionLabel(text: '备注'),
                    HyperTextField(
                      key: const ValueKey('edit_pet_note_field'),
                      controller: _note,
                      hintText: '比如洗澡会紧张、外出需要安抚',
                      maxLines: 4,
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('edit_pet_save_button'),
                    onPressed:
                        _isSaving || !_canSave ? null : _saveChanges,
                    child: const Text('保存修改'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 25, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _birthday = picked);
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await widget.store.updatePet(
        petId: widget.pet.id,
        name: _name.text.trim(),
        type: _type,
        breed: _breed.text.trim(),
        sex: _sex,
        birthday: _formatBirthday(_birthday),
        weightKg: double.parse(_weight.text.trim()),
        neuterStatus: _neuterStatus,
        feedingPreferences: _textOrDefault(_feeding.text),
        allergies: _textOrDefault(_allergies.text),
        note: _textOrDefault(_note.text),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatBirthday(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _textOrDefault(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '未填写' : trimmed;
  }

  String _emptyDisplayToBlank(String value) {
    return value == '未填写' ? '' : value;
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _EditOptionWrap<T> extends StatelessWidget {
  const _EditOptionWrap({
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
                  ? const Color(0xFFF2A65A)
                  : const Color(0xFFF6F7FA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              labelBuilder(value),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? Colors.white : const Color(0xFF6C7280),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
