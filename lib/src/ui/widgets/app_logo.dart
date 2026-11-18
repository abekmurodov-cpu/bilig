import 'package:flutter/material.dart';

/// The Bilig logo, drawn straight on whatever is behind it (no tile): navy
/// features in light mode, white features in dark mode.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        dark ? 'assets/logo/logo_dark.png' : 'assets/logo/logo_light.png',
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
