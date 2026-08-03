import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
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

    final queueCount = await _showLoadingQueueCheck(context, summary);
    if (!mounted) return;

    if (queueCount > 0) {
      context.push(
        AppRoutes.transcription,
        extra: {
          'doctorId': summary.centre.doctorId.isNotEmpty
              ? summary.centre.doctorId
              : (ref.read(authControllerProvider).doctorId ?? ''),
          'practiceCentreId': summary.centre.id,
          'clinicName': summary.centre.clinicName,
        },
      );
    } else {
      _showEmptyQueueDialog(context, summary);
    }
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
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Continue Anyway'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<int> _showLoadingQueueCheck(
    BuildContext context,
    CentreSessionSummary summary,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking patient queue...'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final queueCount = await ref
          .read(dashboardControllerProvider.notifier)
          .checkActiveQueueCount(summary);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return queueCount;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return 0;
    }
  }

  void _showEmptyQueueDialog(
    BuildContext context,
    CentreSessionSummary summary,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Text('No Patients in Queue'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'There are currently no patients waiting in the consultation queue for ${summary.centre.clinicName}.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You will be able to start consultations as soon as patients check in.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog(BuildContext context, AuthState authState) {
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
                        FilledButton.icon(
                          onPressed: () => dashboardNotifier.loadDashboard(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (dashboardState.summaries.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_hospital_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Practice Centres Assigned',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please configure your practice centres in the web settings.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => dashboardNotifier.loadDashboard(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check Again'),
                        ),
                      ],
                    ),
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
