import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../design_system/app_spacing.dart';
import '../../../../design_system/widgets/app_buttons.dart';
import '../../../../design_system/widgets/app_card.dart';
import '../../../../design_system/widgets/empty_state.dart';
import '../../../../design_system/widgets/status_badge.dart';
import '../../../../core/config/app_config.dart';
import '../../data/services/queue_service.dart';
import '../controllers/transcription_controller.dart';
import '../widgets/add_patient_sheet.dart';

/// Screen displaying the active patient queue for a selected practice centre.
///
/// Features:
///   1. Quick Start button ("Start Next Patient") to automatically start consultation with next patient.
///   2. Manual selection: tap any patient in the list to start consultation for that specific patient.
///   3. Auto-refreshes when returning from completed consultations.
class PatientQueueScreen extends ConsumerStatefulWidget {
  const PatientQueueScreen({
    super.key,
    required this.doctorId,
    required this.practiceCentreId,
    required this.clinicName,
  });

  final String doctorId;
  final String practiceCentreId;
  final String clinicName;

  @override
  ConsumerState<PatientQueueScreen> createState() => _PatientQueueScreenState();
}

class _PatientQueueScreenState extends ConsumerState<PatientQueueScreen> {
  List<QueueTicket> _tickets = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final queueService = ref.read(queueServiceProvider);
      final tickets = await queueService.fetchQueueTickets(
        practiceCentreId: widget.practiceCentreId,
        doctorId: widget.doctorId,
        visitDate: todayStr,
      );
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startNextPatient() async {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final res = await controller.advanceNextPatient(
      doctorId: widget.doctorId,
      practiceCentreId: widget.practiceCentreId,
      visitDate: todayStr,
    );

    if (!mounted) return;

    final error = ref.read(transcriptionControllerProvider).errorMessage;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    if (res != null && res.hasNextPatient && res.activePatient != null) {
      context.push(
        AppRoutes.transcription,
        extra: {
          'doctorId': widget.doctorId,
          'practiceCentreId': widget.practiceCentreId,
          'clinicName': widget.clinicName,
        },
      ).then((_) => _loadQueue());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queue is currently empty.')),
      );
    }
  }

  Future<void> _selectPatient(QueueTicket ticket) async {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final queueService = ref.read(queueServiceProvider);

    if (!ticket.hasLinkedPatient) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Link or register this patient before starting consultation.',
          ),
        ),
      );
      return;
    }

    // Update status to In Consultation (3) if waiting
    if (ticket.status < 3) {
      final updated = await queueService.updateTicketStatus(ticket.id, 3);
      if (!updated) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not start consultation. Ensure the patient is linked.',
            ),
          ),
        );
        return;
      }
    }

    controller.setActivePatient(QueuePatient(
      id: ticket.id,
      queueNumber: ticket.queueNumber,
      patientName: ticket.patientName,
      patientMobile: ticket.patientMobile,
      patientId: ticket.patientId!,
    ));

    if (!mounted) return;

    context.push(
      AppRoutes.transcription,
      extra: {
        'doctorId': widget.doctorId,
        'practiceCentreId': widget.practiceCentreId,
        'clinicName': widget.clinicName,
      },
    ).then((_) => _loadQueue());
  }

  Future<void> _viewSavedNote(String patientId) async {
    try {
      final fhirService = ref.read(clinicalNoteFhirServiceProvider);
      final config = ref.read(appConfigProvider);
      final notes = await fhirService.listClinicalNotes(
        baseUrl: Uri.parse(config.fhirNotesUrl),
        patientId: patientId,
      );
      
      if (notes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No notes found for this patient.')),
        );
        return;
      }
      
      final detail = await ref
          .read(transcriptionControllerProvider.notifier)
          .loadClinicalNoteDetail(notes.first.id);
          
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: ListView(
                  controller: controller,
                  children: [
                    Text(
                      'Saved Note (${notes.first.createdAt ?? ""})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(detail.noteText),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading note: $e')),
      );
    }
  }

  Widget _buildPriorityChip(int priority) {
    switch (priority) {
      case 2:
        return const StatusBadge(label: 'Emergency', type: StatusBadgeType.critical);
      case 1:
        return const StatusBadge(label: 'High', type: StatusBadgeType.warning);
      default:
        return const StatusBadge(label: 'Normal', type: StatusBadgeType.neutral);
    }
  }

  Widget _buildStatusChip(int status) {
    switch (status) {
      case 3:
        return const StatusBadge(label: 'In Consultation', type: StatusBadgeType.info);
      case 4:
        return const StatusBadge(label: 'Completed', type: StatusBadgeType.neutral);
      default:
        return const StatusBadge(label: 'Waiting', type: StatusBadgeType.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingTickets = _tickets.where((t) => t.status != 5).toList()
      ..sort((a, b) {
        if (a.status == 4 && b.status != 4) return 1;
        if (a.status != 4 && b.status == 4) return -1;
        return a.queueNumber.compareTo(b.queueNumber);
      });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clinicName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Text('Patient Queue', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQueue,
            tooltip: 'Refresh Queue',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Action Banner with "Add Patient" and "Start Next Patient" Quick Start buttons
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${waitingTickets.length} Patients Waiting',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Active Session',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent),
                      ),
                    ],
                  ),
                  if (waitingTickets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppSecondaryButton(
                            onPressed: _startNextPatient,
                            icon: Icons.play_arrow_rounded,
                            label: 'Start Next',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Queue List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadQueue,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                  const SizedBox(height: 12),
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  AppPrimaryButton(onPressed: _loadQueue, label: 'Retry'),
                                ],
                              ),
                            ),
                          )
                        : waitingTickets.isEmpty
                            ? const EmptyState(
                                title: 'No patients are currently in this session.',
                                description: 'Add a patient directly to start or conduct this consultation session.',
                                icon: Icons.people_outline_rounded,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 12, left: 12, right: 12,
                                  bottom: 80, // Extra space so FAB doesn't cover last item
                                ),
                                itemCount: waitingTickets.length,
                                itemBuilder: (context, index) {
                                  final ticket = waitingTickets[index];
                                  final isInConsultation = ticket.status == 3;
                                  final isCompleted = ticket.status == 4;

                                  return AppCard(
                                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                    color: isCompleted ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
                                    border: isInConsultation
                                        ? Border.all(color: theme.colorScheme.primary, width: 2)
                                        : null,
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: isInConsultation
                                                    ? AppColors.accent
                                                    : (isCompleted ? Colors.grey : theme.colorScheme.primary),
                                                radius: 22,
                                                child: Text(
                                                  '#${ticket.queueNumber}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      ticket.patientName,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: isCompleted ? Colors.grey : null,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      ticket.patientMobile.isNotEmpty ? ticket.patientMobile : 'No contact',
                                                      style: TextStyle(
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isCompleted)
                                                const Icon(Icons.check_circle_rounded, color: Colors.grey, size: 28),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _buildPriorityChip(ticket.priority),
                                                    _buildStatusChip(ticket.status),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              isCompleted
                                                  ? AppTextButton(
                                                      onPressed: ticket.patientId != null
                                                          ? () => _viewSavedNote(ticket.patientId!)
                                                          : null,
                                                      icon: Icons.description,
                                                      label: 'View Note',
                                                    )
                                                  : AppPrimaryButton(
                                                      onPressed: () => _selectPatient(ticket),
                                                      label: isInConsultation ? 'Resume' : 'Start',
                                                    ),
                                            ],
                                          ),
                                        ],
                                      ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await AddPatientSheet.show(
            context,
            doctorId: widget.doctorId,
            practiceCentreId: widget.practiceCentreId,
            existingTickets: _tickets,
          );
          if (added == true) {
            _loadQueue();
          }
        },
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'Add Patient',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        backgroundColor: AppColors.accent,
        elevation: 4,
      ),
    );
  }
}
