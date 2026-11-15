import 'package:flutter/material.dart';
import '../core/theme/colors.dart';

/// Scope untuk berbagi satu AnimationController ke seluruh SkeletonBox di dalamnya.
class _SkeletonScope extends InheritedWidget {
  final Color color;

  const _SkeletonScope({required this.color, required super.child});

  static Color of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    return scope?.color ?? card;
  }

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) => color != oldWidget.color;
}

/// Pembungkus animasi pulse lembut bernuansa cream agar loading nyaman di mata.
class SkeletonPulse extends StatefulWidget {
  final Widget child;
  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _colorAnim = ColorTween(begin: card, end: surface).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnim,
      builder: (_, child) => _SkeletonScope(
        color: _colorAnim.value ?? card,
        child: child!,
      ),
      child: widget.child,
    );
  }
}

/// Kotak placeholder dasar untuk skeleton loading.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _SkeletonScope.of(context),
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder untuk kartu sorotan di Beranda.
class HighlightSkeletonContent extends StatelessWidget {
  const HighlightSkeletonContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 20, height: 20, radius: 6),
              SkeletonBox(width: 34, height: 20, radius: 6),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 78, height: 12, radius: 4),
              SizedBox(height: 6),
              SkeletonBox(width: 52, height: 10, radius: 4),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder feed postingan di Beranda.
class FeedSkeletonList extends StatelessWidget {
  final int count;
  const FeedSkeletonList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        children: List.generate(count, (i) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 6, color: card),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SkeletonBox(width: 40, height: 40, shape: BoxShape.circle),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 130, height: 13, radius: 5),
                            SizedBox(height: 6),
                            SkeletonBox(width: 90, height: 10, radius: 4),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SkeletonBox(width: double.infinity, height: 13, radius: 5),
                    const SizedBox(height: 8),
                    const SkeletonBox(width: 220, height: 13, radius: 5),
                    if (i == 0) ...[
                      const SizedBox(height: 12),
                      const SkeletonBox(width: double.infinity, height: 170, radius: 12),
                    ],
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        SkeletonBox(width: 48, height: 22, radius: 8),
                        SizedBox(width: 14),
                        SkeletonBox(width: 48, height: 22, radius: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Placeholder daftar alumni di Direktori.
class DirectorySkeletonList extends StatelessWidget {
  final int count;
  const DirectorySkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          children: List.generate(count, (_) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 44, height: 44, shape: BoxShape.circle),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 140, height: 14, radius: 5),
                        SizedBox(height: 7),
                        SkeletonBox(width: 180, height: 11, radius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  SkeletonBox(width: 64, height: 28, radius: 14),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Placeholder daftar acara di halaman Acara.
class EventSkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  const EventSkeletonList({
    super.key,
    this.count = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: 22),
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: padding,
        child: Column(
          children: List.generate(count, (_) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: double.infinity, height: 120, radius: 0),
                  Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 72, height: 20, radius: 6),
                        SizedBox(height: 10),
                        SkeletonBox(width: 210, height: 16, radius: 5),
                        SizedBox(height: 8),
                        SkeletonBox(width: 150, height: 12, radius: 4),
                        SizedBox(height: 14),
                        SkeletonBox(width: double.infinity, height: 38, radius: 10),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Placeholder daftar lowongan di Bursa Karier.
class JobSkeletonList extends StatelessWidget {
  final int count;
  const JobSkeletonList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          children: List.generate(count, (_) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 40, height: 40, radius: 10),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 160, height: 15, radius: 5),
                            SizedBox(height: 6),
                            SkeletonBox(width: 110, height: 12, radius: 4),
                          ],
                        ),
                      ),
                      SkeletonBox(width: 64, height: 22, radius: 8),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      SkeletonBox(width: 70, height: 20, radius: 6),
                      SizedBox(width: 8),
                      SkeletonBox(width: 90, height: 20, radius: 6),
                    ],
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Placeholder halaman Profil saat data sedang dimuat.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SkeletonBox(width: 70, height: 70, radius: 18),
              SkeletonBox(width: 96, height: 34, radius: 10),
            ],
          ),
          SizedBox(height: 14),
          SkeletonBox(width: 170, height: 20, radius: 6),
          SizedBox(height: 8),
          SkeletonBox(width: 130, height: 13, radius: 4),
          SizedBox(height: 14),
          SkeletonBox(width: double.infinity, height: 13, radius: 5),
          SizedBox(height: 6),
          SkeletonBox(width: 240, height: 13, radius: 5),
          SizedBox(height: 20),
          SkeletonBox(width: double.infinity, height: 72, radius: 14),
        ],
      ),
    );
  }
}
