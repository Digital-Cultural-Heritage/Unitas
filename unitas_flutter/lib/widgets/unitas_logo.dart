import 'package:flutter/material.dart';

class UnitasLogo extends StatelessWidget {
  final double size;

  const UnitasLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/unitas_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
