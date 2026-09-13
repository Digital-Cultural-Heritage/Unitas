import 'package:flutter/material.dart';
import '../core/theme/text_styles.dart';

class UnitasAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;

  const UnitasAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.28,
        ),
      ),
    );
  }
}
