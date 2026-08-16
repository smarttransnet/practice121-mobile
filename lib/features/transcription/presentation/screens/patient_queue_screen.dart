import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
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
    final res = await controller.advanceNextPatient(
      doctorId: widget.doctorId,
      practiceCentreId: widget.practiceCentreId,
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

  Widget _buildPriorityChip(int priority) {
    switch (priority) {
      case 2:
        return const Chip(
          label: Text('Emergency', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          backgroundColor: Colors.red,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      case 1:
        return const Chip(
          label: Text('High', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          backgroundColor: Colors.orange,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      default:
        return const Chip(
          label: Text('Normal', style: TextStyle(fontSize: 11)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
    }
  }

  Widget _buildStatusChip(int status) {
    switch (status) {
      case 3:
        return const Chip(
          label: Text('In Consultation', style: TextStyle(color: Colors.white, fontSize: 11)),
          backgroundColor: AppColors.accent,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      case 4:
        return const Chip(
          label: Text('Completed', style: TextStyle(color: Colors.white, fontSize: 11)),
          backgroundColor: Colors.grey,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      default:
        return const Chip(
          label: Text('Waiting', style: TextStyle(fontSize: 11)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: waitingTickets.isNotEmpty ? _startNextPatient : null,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Start Next'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                                  ElevatedButton(onPressed: _loadQueue, child: const Text('Retry')),
                                ],
                              ),
                            ),
                          )
                        : waitingTickets.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.people_outline_rounded,
                                          color: AppColors.accent,
                                          size: 56,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        'No patients are currently in this session.',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Add a patient directly to start or conduct this consultation session.',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 24),
                                      FilledButton.icon(
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
                                        icon: const Icon(Icons.person_add_rounded),
                                        label: const Text('Add Patient'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: _loadQueue,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Refresh Queue'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: waitingTickets.length,
                                itemBuilder: (context, index) {
                                  final ticket = waitingTickets[index];
                                  final isInConsultation = ticket.status == 3;
                                  final isCompleted = ticket.status == 4;

                                  return Card(
                                    elevation: isInConsultation ? 3 : (isCompleted ? 0 : 1),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    color: isCompleted ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: isInConsultation
                                          ? const BorderSide(color: AppColors.accent, width: 2)
                                          : BorderSide.none,
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      leading: CircleAvatar(
                                        backgroundColor: isInConsultation
                                            ? AppColors.accent
                                            : (isCompleted ? Colors.grey : theme.colorScheme.primary),
                                        radius: 22,
                                        child: Text(
                                          '#${ticket.queueNumber}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(
                                        ticket.patientName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isCompleted ? Colors.grey : null,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(ticket.patientMobile.isNotEmpty ? ticket.patientMobile : 'No contact'),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              _buildPriorityChip(ticket.priority),
                                              const SizedBox(width: 8),
                                              _buildStatusChip(ticket.status),
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: isCompleted
                                          ? const Icon(Icons.check_circle_rounded, color: Colors.grey, size: 28)
                                          : FilledButton(
                                              onPressed: () => _selectPatient(ticket),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: isInConsultation ? Colors.orange : theme.colorScheme.primary,
                                              ),
                                              child: Text(isInConsultation ? 'Resume' : 'Start'),
                                            ),
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
