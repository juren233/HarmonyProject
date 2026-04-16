import 'package:flutter/material.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/petnote_store.dart';

class MeasurementDraft {
  MeasurementDraft()
      : keyController = TextEditingController(),
        valueController = TextEditingController(),
        unitController = TextEditingController();

  final TextEditingController keyController;
  final TextEditingController valueController;
  final TextEditingController unitController;

  SemanticMeasurement? toMeasurement() {
    final key = keyController.text.trim();
    final value = valueController.text.trim();
    final unit = unitController.text.trim();
    if (key.isEmpty) {
      return null;
    }
    return SemanticMeasurement(key: key, value: value, unit: unit);
  }

  void dispose() {
    keyController.dispose();
    valueController.dispose();
    unitController.dispose();
  }
}

class MeasurementEditorSection extends StatelessWidget {
  const MeasurementEditorSection({
    super.key,
    required this.prefix,
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
  });

  final String prefix;
  final List<MeasurementDraft> drafts;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < drafts.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _MeasurementRow(
            prefix: prefix,
            index: index,
            draft: drafts[index],
            canRemove: drafts.length > 1,
            onRemove: () => onRemove(index),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('${prefix}_add_measurement_button'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增指标'),
          ),
        ),
      ],
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.prefix,
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final String prefix;
  final int index;
  final MeasurementDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              HyperTextField(
                key: ValueKey('${prefix}_measurement_key_field_$index'),
                controller: draft.keyController,
                hintText: '指标名，例如 weight',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: HyperTextField(
                      key: ValueKey('${prefix}_measurement_value_field_$index'),
                      controller: draft.valueController,
                      hintText: '数值',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HyperTextField(
                      key: ValueKey('${prefix}_measurement_unit_field_$index'),
                      controller: draft.unitController,
                      hintText: '单位',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (canRemove) ...[
          const SizedBox(width: 8),
          IconButton(
            key: ValueKey('${prefix}_remove_measurement_button_$index'),
            tooltip: '删除指标',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ],
    );
  }
}
