import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';

enum StatusBadgeType { success, warning, critical, info, neutral }

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeType type;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.type = StatusBadgeType.neutral,
    this.icon,
  });

  Color _getBackgroundColor(ColorScheme colorScheme) {
    switch (type) {
      case StatusBadgeType.success:
        return AppColors.successContainer;
      case StatusBadgeType.warning:
        return AppColors.warningContainer;
      case StatusBadgeType.critical:
        return AppColors.criticalContainer;
      case StatusBadgeType.info:
        return AppColors.infoContainer;
      case StatusBadgeType.neutral:
        return colorScheme.surfaceContainerHighest;
    }
  }

  Color _getTextColor(ColorScheme colorScheme) {
    switch (type) {
      case StatusBadgeType.success:
        return AppColors.successDark;
      case StatusBadgeType.warning:
        return AppColors.warningDark;
      case StatusBadgeType.critical:
        return AppColors.criticalDark;
      case StatusBadgeType.info:
        return AppColors.infoDark;
      case StatusBadgeType.neutral:
        return colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = _getBackgroundColor(colorScheme);
    final textColor = _getTextColor(colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
