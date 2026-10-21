import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showBadgeBackground;
  final BorderRadius? borderRadius;

  const AppLogo({
    super.key,
    this.size = 80,
    this.showBadgeBackground = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);

    Widget imageWidget = Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: radius,
          ),
          child: Icon(
            Icons.location_city_rounded,
            size: size * 0.55,
            color: Colors.white,
          ),
        );
      },
    );

    if (showBadgeBackground) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(size * 0.08),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.16),
          child: imageWidget,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: imageWidget,
    );
  }
}

