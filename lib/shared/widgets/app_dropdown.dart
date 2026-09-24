import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: fieldDecoration(label)
          .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceHigh,
          hint: hint == null ? null : Text(hint!, style: TextStyle(color: AppColors.muted)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
