import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
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

    final (badgeText, badgeColor, badgeBg) = switch (summary.status) {
      SessionScheduleStatus.active => (
          'ACTIVE SESSION',
          AppColors.success,
          AppColors.success.withValues(alpha: 0.15),
        ),
      SessionScheduleStatus.upcoming => (
          'UPCOMING',
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      SessionScheduleStatus.completed => (
          'COMPLETED TODAY',
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        ),
      SessionScheduleStatus.notScheduledToday => (
          'NOT SCHEDULED TODAY',
          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
    };

    return Card(
      elevation: isFeatured ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isFeatured
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isFeatured ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
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
              height: 46,
              child: FilledButton.icon(
                onPressed: () => onStartSession(summary),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  backgroundColor: summary.status == SessionScheduleStatus.active
                      ? AppColors.success
                      : theme.colorScheme.primary,
                ),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                label: const Text(
                  'Start Session',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
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
                fontWeight: FontWeight.extrabold,
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
