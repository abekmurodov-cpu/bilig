import 'package:flutter/material.dart';

/// The Bilig logo on a rounded tile that follows the app theme: white with
/// navy features in light mode, black with white features in dark mode.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: dark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Image.asset(
        dark ? 'assets/logo/logo_dark.png' : 'assets/logo/logo_light.png',
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
