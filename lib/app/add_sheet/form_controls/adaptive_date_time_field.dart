import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_pages.dart';

import '../pickers/date_time_pickers.dart';

class AdaptiveDateTimeField extends StatelessWidget {
  const AdaptiveDateTimeField({
    super.key,
    required this.materialFieldKey,
    required this.iosDateFieldKey,
    required this.iosTimeFieldKey,
    required this.value,
    required this.onChanged,
  });

  final Key materialFieldKey;
  final Key iosDateFieldKey;
  final Key iosTimeFieldKey;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      final tokens = context.petNoteTokens;
      return InkWell(
        key: materialFieldKey,
        borderRadius: BorderRadius.circular(22),
        onTap: () => _pickMaterialDateTime(context),
        child: InputDecorator(
          decoration: const InputDecoration(),
          child: Text(
            formatDate(value),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.primaryText,
                ),
          ),
        ),
      );
    }

    final tokens = context.petNoteTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.panelBorder, width: 1.1),
      ),
      child: Column(
        children: [
          _IosPickerRow(
            key: iosDateFieldKey,
            icon: CupertinoIcons.calendar,
            label: '日期',
            value: formatIosDateLabel(value),
            onTap: () => _pickIosDate(context),
          ),
          Divider(height: 1, color: tokens.panelBorder),
          _IosPickerRow(
            key: iosTimeFieldKey,
            icon: CupertinoIcons.time,
            label: '时间',
            value: formatIosTimeLabel(value),
            onTap: () => _pickIosTime(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMaterialDateTime(BuildContext context) async {
    final nextDateTime = await pickAdaptiveDateTime(
      context,
      initialValue: value,
    );
    if (nextDateTime == null || !context.mounted) {
      return;
    }
    onChanged(nextDateTime);
  }

  Future<void> _pickIosDate(BuildContext context) async {
    final nextDate = await pickCupertinoDatePart(
      context,
      initialValue: value,
    );
    if (nextDate == null || !context.mounted) {
      return;
    }
    onChanged(
      DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        value.hour,
        value.minute,
      ),
    );
  }

  Future<void> _pickIosTime(BuildContext context) async {
    final nextDateTime = await pickCupertinoTimePart(
      context,
      initialValue: value,
    );
    if (nextDateTime == null || !context.mounted) {
      return;
    }
    onChanged(
      DateTime(
        value.year,
        value.month,
        value.day,
        nextDateTime.hour,
        nextDateTime.minute,
      ),
    );
  }
}

class OptionalAdaptiveDateTimeField extends StatelessWidget {
  const OptionalAdaptiveDateTimeField({
    super.key,
    required this.materialFieldKey,
    required this.iosDateFieldKey,
    required this.iosTimeFieldKey,
    required this.value,
    required this.placeholder,
    required this.onPickDateTime,
    required this.onPickDate,
    required this.onPickTime,
    this.clearButtonKey,
    this.onClear,
  });

  final Key materialFieldKey;
  final Key iosDateFieldKey;
  final Key iosTimeFieldKey;
  final DateTime? value;
  final String placeholder;
  final Future<void> Function() onPickDateTime;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;
  final Key? clearButtonKey;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final resolvedValue = value;
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      final tokens = context.petNoteTokens;
      return Row(
        children: [
          Expanded(
            child: InkWell(
              key: materialFieldKey,
              borderRadius: BorderRadius.circular(22),
              onTap: onPickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(),
                child: Text(
                  resolvedValue == null
                      ? placeholder
                      : formatDate(resolvedValue),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: resolvedValue == null
                            ? tokens.secondaryText
                            : tokens.primaryText,
                      ),
                ),
              ),
            ),
          ),
          if (resolvedValue != null && onClear != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: clearButtonKey,
              onPressed: onClear,
              child: const Text('清空'),
            ),
          ],
        ],
      );
    }

    final tokens = context.petNoteTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: tokens.panelBackground,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: tokens.panelBorder, width: 1.1),
          ),
          child: Column(
            children: [
              _IosPickerRow(
                key: iosDateFieldKey,
                icon: CupertinoIcons.calendar,
                label: '日期',
                value: resolvedValue == null
                    ? '选择'
                    : formatIosDateLabel(resolvedValue),
                onTap: onPickDate,
              ),
              Divider(height: 1, color: tokens.panelBorder),
              _IosPickerRow(
                key: iosTimeFieldKey,
                icon: CupertinoIcons.time,
                label: '时间',
                value: resolvedValue == null
                    ? '选择'
                    : formatIosTimeLabel(resolvedValue),
                onTap: onPickTime,
              ),
            ],
          ),
        ),
        if (resolvedValue != null && onClear != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: clearButtonKey,
              onPressed: onClear,
              child: const Text('清空'),
            ),
          ),
      ],
    );
  }
}

class _IosPickerRow extends StatelessWidget {
  const _IosPickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: tokens.secondaryText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
