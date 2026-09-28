import 'package:flutter/material.dart';
import 'package:kazumi/utils/surface_theme.dart';

const double tonalCardRadius = 24;

class TonalCard extends StatelessWidget {
  const TonalCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: cardShape(context, tonalCardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}
