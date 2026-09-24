import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: AppColors.accent, width: 1.4),
      ),
      child: Text(
        '{ }',
        style: AppTheme.mono(
            size: size * 0.4, color: AppColors.accent, weight: FontWeight.w700),
      ),
    );
  }
}
