import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c),
        );
    return SizedBox(
      height: 40,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.muted),
          prefixIcon: const Icon(Icons.search, size: 18),
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          enabledBorder: b(AppColors.border),
          focusedBorder: b(AppColors.accent),
        ),
      ),
    );
  }
}
