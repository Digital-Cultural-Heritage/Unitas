import 'package:flutter/material.dart';
import '../core/theme/text_styles.dart';

class UnitasAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  final String? avatarUrl;

  const UnitasAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 42,
    this.avatarUrl,
  });

  Widget _fallback() {
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

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    if (url != null && url.isNotEmpty) {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 1024);
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          cacheWidth: px,
          cacheHeight: px,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (_, child, progress) => progress == null ? child : _fallback(),
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }
}
