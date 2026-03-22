import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

/// Provides a shared [AnimationController] for all shimmer children.
///
/// Wrap a subtree with [ShimmerScope] so that all [ShimmerBox], [ShimmerLine],
/// and [ShimmerCircle] widgets animate in sync.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({super.key, required this.child});
  final Widget child;

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerInherited(controller: _controller, child: widget.child);
  }
}

class _ShimmerInherited extends InheritedWidget {
  const _ShimmerInherited({required this.controller, required super.child});

  final AnimationController controller;

  static AnimationController of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_ShimmerInherited>();
    assert(inherited != null, 'ShimmerScope not found in widget tree');
    return inherited!.controller;
  }

  @override
  bool updateShouldNotify(_ShimmerInherited oldWidget) =>
      controller != oldWidget.controller;
}

/// Rounded rectangle shimmer placeholder.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      width: width,
      height: height,
      borderRadius: borderRadius ?? KoshikaRadius.md,
    );
  }
}

/// Thin rectangle simulating a line of text.
class ShimmerLine extends StatelessWidget {
  const ShimmerLine({
    super.key,
    this.width = double.infinity,
    this.height = 14,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      width: width,
      height: height,
      borderRadius: KoshikaRadius.sm,
    );
  }
}

/// Circle shimmer placeholder.
class ShimmerCircle extends StatelessWidget {
  const ShimmerCircle({super.key, required this.diameter});
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      width: diameter,
      height: diameter,
      borderRadius: BorderRadius.circular(diameter / 2),
    );
  }
}

class _ShimmerBase extends StatelessWidget {
  const _ShimmerBase({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final controller = _ShimmerInherited.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * controller.value, 0),
              end: Alignment(-1.0 + 2.0 * controller.value + 1.0, 0),
              colors: const [
                AppColors.surfaceContainerLow,
                AppColors.surfaceContainerHigh,
                AppColors.surfaceContainerLow,
              ],
            ),
          ),
        );
      },
    );
  }
}
