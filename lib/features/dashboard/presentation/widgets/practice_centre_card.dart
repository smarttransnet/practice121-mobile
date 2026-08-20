import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../design_system/app_spacing.dart';
import '../../../../design_system/widgets/app_buttons.dart';
import '../../../../design_system/widgets/app_card.dart';
import '../../../../design_system/widgets/status_badge.dart';
import '../../data/models/practice_centre.dart';

/// Card widget presenting a concise session summary for a practice centre,
/// including queue metrics, status badge, and the "Start Session" CTA button.
class PracticeCentreCard extends StatelessWidget {
  const PracticeCentreCard({
    super.key,
    required this.summary,
    required this.onStartSession,
    this.isFeatured = false,
  });

  final CentreSessionSummary summary;
  final ValueChanged<CentreSessionSummary> onStartSession;
  final bool isFeatured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centre = summary.centre;

    final (badgeText, badgeType) = switch (summary.status) {
      SessionScheduleStatus.active => (
          'ACTIVE SESSION',
          StatusBadgeType.success,
        ),
      SessionScheduleStatus.upcoming => (
          'UPCOMING',
          StatusBadgeType.info,
        ),
      SessionScheduleStatus.completed => (
          'COMPLETED TODAY',
          StatusBadgeType.neutral,
        ),
      SessionScheduleStatus.notScheduledToday => (
          'NOT SCHEDULED TODAY',
          StatusBadgeType.warning,
        ),
    };

    return AppCard(
      border: isFeatured
          ? Border.all(color: theme.colorScheme.primary, width: 2)
          : null,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Header Row: Featured Indicator + Status Badge
            Row(
              children: [
                if (isFeatured) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'RECOMMENDED NEXT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ] else ...[
                  const Spacer(),
                ],
                StatusBadge(
                  label: badgeText,
                  type: badgeType,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Clinic Name & Location
            Text(
              centre.clinicName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${centre.placeName}, ${centre.districtName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Session Time Range
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  summary.timeRangeLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Queue Metrics Summary Chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MetricChip(
                  label: 'Booked',
                  value: '${summary.totalBookedCount}',
                  icon: Icons.people_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                _MetricChip(
                  label: 'Waiting',
                  value: '${summary.waitingCount}',
                  icon: Icons.hourglass_empty_rounded,
                  color: Colors.orange,
                ),
                _MetricChip(
                  label: 'Active',
                  value: '${summary.activeCount}',
                  icon: Icons.play_arrow_rounded,
                  color: AppColors.success,
                ),
                _MetricChip(
                  label: 'Done',
                  value: '${summary.completedCount}',
                  icon: Icons.check_circle_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Start Session Button
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                onPressed: () => onStartSession(summary),
                icon: Icons.play_circle_outline_rounded,
                label: 'Start Session',
              ),
            ),
          ],
        ),
      );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
