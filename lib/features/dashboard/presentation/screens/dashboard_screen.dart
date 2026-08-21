import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../design_system/widgets/app_buttons.dart';
import '../../../../design_system/widgets/empty_state.dart';
import '../../../../design_system/widgets/status_badge.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/auth_state.dart';
import '../controllers/dashboard_controller.dart';
import '../../data/models/practice_centre.dart';
import '../widgets/practice_centre_card.dart';

/// Doctor Home Dashboard screen displaying assigned practice centres prioritized
/// intelligently according to schedule and current time.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  Future<void> _onStartSession(CentreSessionSummary summary) async {
    final isScheduledToday =
        summary.status != SessionScheduleStatus.notScheduledToday;

    if (!isScheduledToday) {
      final shouldProceed = await _showNotScheduledTodayDialog(context, summary);
      if (!shouldProceed || !mounted) {
        return;
      }
    }

    DaySessionSlot? chosenSlot = summary.selectedSlot;

    // If multiple sessions exist today and none was tapped directly, let doctor pick
    if (summary.todaySlots.length > 1 && chosenSlot == null) {
      chosenSlot = await _showSessionSlotSelectionSheet(context, summary);
      if (!mounted) return;
    }

    if (!mounted) return;

    context.push(
      AppRoutes.patientQueue,
      extra: {
        'doctorId': summary.centre.doctorId.isNotEmpty
            ? summary.centre.doctorId
            : (ref.read(authControllerProvider).doctorId ?? ''),
        'practiceCentreId': summary.centre.id,
        'clinicName': summary.centre.clinicName,
        'practiceCentre': summary.centre,
        'initialSessionId': chosenSlot?.id,
        'initialSessionLabel': chosenSlot != null
            ? '${chosenSlot.label} (${chosenSlot.timeRange})'
            : null,
      },
    );
  }

  Future<DaySessionSlot?> _showSessionSlotSelectionSheet(
    BuildContext context,
    CentreSessionSummary summary,
  ) {
    final theme = Theme.of(context);
    return showModalBottomSheet<DaySessionSlot>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.access_time_filled_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Session Time Slot',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            summary.centre.clinicName,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                ...summary.todaySlots.map((slot) {
                  final isSlotActive =
                      slot.status == SessionScheduleStatus.active;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSlotActive
                              ? AppColors.success
                              : theme.colorScheme.outlineVariant,
                          width: isSlotActive ? 1.5 : 1.0,
                        ),
                      ),
                      tileColor: isSlotActive
                          ? AppColors.success.withValues(alpha: 0.08)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                      leading: CircleAvatar(
                        backgroundColor: isSlotActive
                            ? AppColors.success
                            : theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                        foregroundColor: isSlotActive
                            ? Colors.white
                            : theme.colorScheme.primary,
                        child: Icon(
                          isSlotActive
                              ? Icons.play_arrow_rounded
                              : Icons.schedule_rounded,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '${slot.label} Session',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Time: ${slot.timeRange}'),
                      trailing: isSlotActive
                          ? const StatusBadge(
                              label: 'ACTIVE NOW',
                              type: StatusBadgeType.success)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(sheetContext).pop(slot),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.apps_rounded),
                  label: const Text('Show All Sessions / Entire Queue'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showNotScheduledTodayDialog(
    BuildContext context,
    CentreSessionSummary summary,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: Colors.orange),
              SizedBox(width: 10),
              Text('Session Not Today'),
            ],
          ),
          content: Text(
            'This session (${summary.centre.clinicName}) is not scheduled for today (${summary.timeRangeLabel}). Do you want to proceed anyway?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            AppPrimaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: 'Continue Anyway',
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showSettingsDialog(BuildContext context, AuthState authState) {
    final config = ref.read(appConfigProvider);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isBioAvail = authState.isBiometricAvailable;
            final isBioOn = authState.isBiometricEnabled;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.security_rounded),
                  SizedBox(width: 10),
                  Text('Security Settings'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBioAvail)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Biometric Unlock'),
                      subtitle: const Text(
                        'Require Face ID or Fingerprint when opening the app',
                      ),
                      value: isBioOn,
                      onChanged: (value) async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .setBiometricEnabled(value);
                        setState(() {});
                      },
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Biometric authentication is not supported or configured on this device.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  if (config.hasPrivacyPolicy)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Policy'),
                      onTap: () => _openExternalUrl(config.privacyPolicyUrl),
                    ),
                  if (config.hasAccountDeletionUrl)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Delete account'),
                      subtitle: const Text(
                        'Request deletion of your Practice121 account and data',
                      ),
                      onTap: () => _openExternalUrl(config.accountDeletionUrl),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final dashboardState = ref.watch(dashboardControllerProvider);
    final dashboardNotifier = ref.read(dashboardControllerProvider.notifier);

    final doctorName = authState.doctorName?.isNotEmpty == true
        ? authState.doctorName!
        : 'Doctor';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $doctorName',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Select session to begin consultations',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Queue',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => dashboardNotifier.loadDashboard(),
          ),
          IconButton(
            tooltip: 'Settings & Security',
            icon: const Icon(Icons.security_outlined),
            onPressed: () => _showSettingsDialog(context, authState),
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => dashboardNotifier.loadDashboard(),
          child: Builder(
            builder: (context) {
              if (dashboardState.isLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading assigned practice centres...'),
                    ],
                  ),
                );
              }

              if (dashboardState.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          dashboardState.errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        AppPrimaryButton(
                          onPressed: () => dashboardNotifier.loadDashboard(),
                          icon: Icons.refresh_rounded,
                          label: 'Try Again',
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (dashboardState.summaries.isEmpty) {
                return EmptyState(
                  icon: Icons.local_hospital_outlined,
                  title: 'No Practice Centres Assigned',
                  description: 'Please configure your practice centres in the web settings.',
                  action: AppSecondaryButton(
                    onPressed: () => dashboardNotifier.loadDashboard(),
                    icon: Icons.refresh_rounded,
                    label: 'Check Again',
                  ),
                );
              }

              final summaries = dashboardState.summaries;

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: summaries.length,
                itemBuilder: (context, index) {
                  final summary = summaries[index];
                  final isFeatured = index == 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PracticeCentreCard(
                      summary: summary,
                      isFeatured: isFeatured,
                      onStartSession: (selectedSummary) =>
                          _onStartSession(selectedSummary),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
