import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand_mark.dart';

/// Logo, name and a typed-out tagline with a blinking cursor.
/// Navigation away is driven by the router once the session check finishes.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _tagline = 'Build. Debug. Understand. Ship.';
  int _chars = 0;
  bool _cursor = true;
  Timer? _typing;
  Timer? _blink;

  @override
  void initState() {
    super.initState();
    _typing = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (_chars >= _tagline.length) return t.cancel();
      setState(() => _chars++);
    });
    _blink = Timer.periodic(const Duration(milliseconds: 530),
        (_) => setState(() => _cursor = !_cursor));
  }

  @override
  void dispose() {
    _typing?.cancel();
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) =>
                  Opacity(opacity: v.clamp(0, 1) as double, child: Transform.scale(scale: v, child: child)),
              child: const BrandMark(size: 76),
            ),
            const SizedBox(height: 24),
            Text('AI Developer Assistant',
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SizedBox(
              height: 24,
              child: Text(
                '${_tagline.substring(0, _chars)}${_cursor ? '▍' : ' '}',
                style: AppTheme.mono(color: AppColors.accent, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
