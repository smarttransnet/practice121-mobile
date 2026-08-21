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
import '../../../dashboard/data/models/practice_centre.dart';
import '../../data/services/clinical_note_fhir_service.dart';
import '../../data/services/queue_service.dart';
import '../controllers/transcription_controller.dart';
import '../widgets/add_patient_sheet.dart';

/// Screen displaying the active patient queue for a selected practice centre.
///
/// Features:
///   1. Multi-Session Selector: Filter tickets session-wise (e.g. Morning, Evening, Show All).
///   2. Quick Start button ("Start Next Patient") to automatically start consultation with next patient in session.
///   3. Manual selection: tap any patient in the list to start consultation for that specific patient.
///   4. Add Patient: Add patients directly to the currently active or selected session slot.
///   5. Auto-refreshes when returning from completed consultations.
class PatientQueueScreen extends ConsumerStatefulWidget {
  const PatientQueueScreen({
    super.key,
    required this.doctorId,
    required this.practiceCentreId,
    required this.clinicName,
    this.practiceCentre,
    this.initialSessionId,
    this.initialSessionLabel,
  });

  final String doctorId;
  final String practiceCentreId;
  final String clinicName;
  final PracticeCentre? practiceCentre;
  final String? initialSessionId;
  final String? initialSessionLabel;

  @override
  ConsumerState<PatientQueueScreen> createState() => _PatientQueueScreenState();
}

class _PatientQueueScreenState extends ConsumerState<PatientQueueScreen> {
  List<QueueTicket> _tickets = [];
  bool _isLoading = true;
  String? _error;

  List<DaySessionSlot> _daySessions = [];
  String _selectedSessionFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _computeDaySessions();
    _loadQueue();
  }

  void _computeDaySessions() {
    if (widget.practiceCentre == null) {
      if (widget.initialSessionId != null && widget.initialSessionId!.isNotEmpty) {
        _selectedSessionFilter = widget.initialSessionId!;
      }
      return;
    }

    final now = DateTime.now();
    final dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final currentDayAbbr = dayNames[now.weekday - 1];
    final currentTimeInMinutes = now.hour * 60 + now.minute;
    final dateStr = now.toIso8601String().split('T').first;

    final slots = <DaySessionSlot>[];

    for (final group in widget.practiceCentre!.sessionGroups) {
      if (group.daysOff.contains(dateStr)) continue;

      final isSpecificDateMatch =
          group.specificDate == dateStr || group.specificDates.contains(dateStr);
      final isDayOfWeekMatch = group.daysOfWeek.contains(currentDayAbbr);

      if (isSpecificDateMatch || isDayOfWeekMatch) {
        if (group.timeBlocks.isNotEmpty) {
          for (final tb in group.timeBlocks) {
            final startMin = _parseTimeToMinutes(tb.startTime);
            final endMin = _parseTimeToMinutes(tb.endTime);
            SessionScheduleStatus slotStatus;

            if (currentTimeInMinutes >= startMin && currentTimeInMinutes <= endMin) {
              slotStatus = SessionScheduleStatus.active;
            } else if (currentTimeInMinutes < startMin) {
              slotStatus = SessionScheduleStatus.upcoming;
            } else {
              slotStatus = SessionScheduleStatus.completed;
            }

            slots.add(
              DaySessionSlot(
                id: tb.id.isNotEmpty ? tb.id : group.id,
                groupId: group.id,
                label: tb.label.isNotEmpty ? tb.label : 'Session',
                startTime: tb.startTime,
                endTime: tb.endTime,
                timeRange: '${tb.startTime} - ${tb.endTime}',
                status: slotStatus,
              ),
            );
          }
        } else {
          slots.add(
            DaySessionSlot(
              id: group.id,
              groupId: group.id,
              label: 'Scheduled Session',
              startTime: '09:00',
              endTime: '17:00',
              timeRange: group.daysOfWeek.join(', '),
              status: SessionScheduleStatus.active,
            ),
          );
        }
      }
    }

    slots.sort((a, b) =>
        _parseTimeToMinutes(a.startTime).compareTo(_parseTimeToMinutes(b.startTime)));

    _daySessions = slots;

    // Set initial filter selection
    if (widget.initialSessionId != null && widget.initialSessionId!.isNotEmpty) {
      _selectedSessionFilter = widget.initialSessionId!;
    } else {
      final activeSlot = slots.where((s) => s.status == SessionScheduleStatus.active).firstOrNull;
      if (activeSlot != null) {
        _selectedSessionFilter = activeSlot.id;
      } else if (slots.isNotEmpty) {
        _selectedSessionFilter = 'ALL';
      }
    }
  }

  int _parseTimeToMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 9 * 60;
  }

  Future<void> _loadQueue() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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

  List<QueueTicket> get _allActiveTickets {
    return _tickets.where((t) => t.status != 5).toList();
  }

  List<QueueTicket> get _filteredTickets {
    final active = _allActiveTickets;
    if (_selectedSessionFilter == 'ALL') {
      return active;
    }

    final sidLower = _selectedSessionFilter.toLowerCase();
    final matchingSlot = _daySessions.where((s) => s.id == _selectedSessionFilter).firstOrNull;

    return active.where((t) {
      if (t.sessionId != null && t.sessionId!.isNotEmpty) {
        if (t.sessionId!.toLowerCase() == sidLower) return true;
        if (matchingSlot != null && t.sessionId!.toLowerCase() == matchingSlot.groupId.toLowerCase()) return true;
      }
      if (matchingSlot != null && t.sessionName != null && t.sessionName!.isNotEmpty) {
        if (t.sessionName!.toLowerCase().contains(matchingSlot.label.toLowerCase())) return true;
      }
      return false;
    }).toList();
  }

  int _countForSession(String sessionId) {
    final sidLower = sessionId.toLowerCase();
    final matchingSlot = _daySessions.where((s) => s.id == sessionId).firstOrNull;

    return _allActiveTickets.where((t) {
      if (t.sessionId != null && t.sessionId!.isNotEmpty) {
        if (t.sessionId!.toLowerCase() == sidLower) return true;
        if (matchingSlot != null && t.sessionId!.toLowerCase() == matchingSlot.groupId.toLowerCase()) return true;
      }
      if (matchingSlot != null && t.sessionName != null && t.sessionName!.isNotEmpty) {
        if (t.sessionName!.toLowerCase().contains(matchingSlot.label.toLowerCase())) return true;
      }
      return false;
    }).length;
  }

  String _resolveTicketSessionLabel(QueueTicket ticket) {
    if (ticket.sessionName != null && ticket.sessionName!.isNotEmpty) {
      return ticket.sessionName!;
    }
    if (ticket.sessionId != null && ticket.sessionId!.isNotEmpty) {
      final sid = ticket.sessionId!.toLowerCase();
      final match = _daySessions.where((s) => s.id.toLowerCase() == sid || s.groupId.toLowerCase() == sid).firstOrNull;
      if (match != null) {
        return '${match.label} (${match.timeRange})';
      }
    }
    return '';
  }

  Future<void> _startNextPatient() async {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    String? selectedSessionId;
    if (_selectedSessionFilter != 'ALL') {
      selectedSessionId = _selectedSessionFilter;
    }

    final res = await controller.advanceNextPatient(
      doctorId: widget.doctorId,
      practiceCentreId: widget.practiceCentreId,
      visitDate: todayStr,
      sessionId: selectedSessionId,
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
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: ListView(
                  controller: scrollController,
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
    final filtered = _filteredTickets
      ..sort((a, b) {
        if (a.status == 4 && b.status != 4) return 1;
        if (a.status != 4 && b.status == 4) return -1;
        return a.queueNumber.compareTo(b.queueNumber);
      });

    final waitingInFilter = filtered.where((t) => t.status <= 1).toList();

    DaySessionSlot? currentSelectedSlot;
    if (_selectedSessionFilter != 'ALL') {
      currentSelectedSlot =
          _daySessions.where((s) => s.id == _selectedSessionFilter).firstOrNull;
    }

    final activeSessionTitle = currentSelectedSlot != null
        ? '${currentSelectedSlot.label} (${currentSelectedSlot.timeRange})'
        : (_daySessions.isNotEmpty ? 'All Sessions (${_allActiveTickets.length})' : 'Active Session');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clinicName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} • Patient Queue',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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
            // --- Multi-Session Horizontal Filter Bar ---
            if (_daySessions.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // "Show All" Chip
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('Show All (${_allActiveTickets.length})'),
                          selected: _selectedSessionFilter == 'ALL',
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedSessionFilter = 'ALL');
                          },
                          selectedColor: theme.colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            fontWeight:
                                _selectedSessionFilter == 'ALL' ? FontWeight.bold : FontWeight.w500,
                            color: _selectedSessionFilter == 'ALL'
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),

                      // Individual Session Slot Chips
                      ..._daySessions.map((slot) {
                        final isSelected = _selectedSessionFilter == slot.id;
                        final count = _countForSession(slot.id);
                        final isActiveNow = slot.status == SessionScheduleStatus.active;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: isActiveNow
                                ? const Icon(Icons.fiber_manual_record,
                                    size: 12, color: AppColors.success)
                                : null,
                            label: Text(
                              '${slot.label} (${slot.timeRange}) • $count',
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedSessionFilter = slot.id);
                            },
                            selectedColor: isActiveNow
                                ? AppColors.success.withValues(alpha: 0.2)
                                : theme.colorScheme.primaryContainer,
                            side: isSelected && isActiveNow
                                ? const BorderSide(color: AppColors.success, width: 1.5)
                                : null,
                            labelStyle: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? (isActiveNow ? AppColors.success : theme.colorScheme.onPrimaryContainer)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],

            // Top Action Banner with "Start Next Patient" Quick Start button
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${waitingInFilter.length} Patients Waiting',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            activeSessionTitle,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (waitingInFilter.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppSecondaryButton(
                            onPressed: _startNextPatient,
                            icon: Icons.play_arrow_rounded,
                            label: 'Start Next Patient',
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
                                  const Icon(Icons.error_outline,
                                      color: Colors.red, size: 48),
                                  const SizedBox(height: 12),
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  AppPrimaryButton(
                                      onPressed: _loadQueue, label: 'Retry'),
                                ],
                              ),
                            ),
                          )
                        : filtered.isEmpty
                            ? EmptyState(
                                title: _selectedSessionFilter == 'ALL'
                                    ? 'No patients are currently in the queue.'
                                    : 'No patients in ${currentSelectedSlot?.label ?? "this"} session.',
                                description:
                                    'Tap "+ Add Patient" to add or register a patient for this session.',
                                icon: Icons.people_outline_rounded,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  left: 12,
                                  right: 12,
                                  bottom: 80, // Extra space so FAB doesn't cover last item
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final ticket = filtered[index];
                                  final isInConsultation = ticket.status == 3;
                                  final isCompleted = ticket.status == 4;
                                  final sessionLabel = _resolveTicketSessionLabel(ticket);

                                  return AppCard(
                                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                    color: isCompleted
                                        ? theme.colorScheme.surfaceContainerHighest
                                            .withValues(alpha: 0.5)
                                        : null,
                                    border: isInConsultation
                                        ? Border.all(
                                            color: theme.colorScheme.primary, width: 2)
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
                                                  : (isCompleted
                                                      ? Colors.grey
                                                      : theme.colorScheme.primary),
                                              radius: 22,
                                              child: Text(
                                                '#${ticket.queueNumber}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
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
                                                  Row(
                                                    children: [
                                                      Text(
                                                        ticket.patientMobile.isNotEmpty
                                                            ? ticket.patientMobile
                                                            : 'No contact',
                                                        style: TextStyle(
                                                          color: theme.colorScheme
                                                              .onSurfaceVariant,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      if (sessionLabel.isNotEmpty &&
                                                          _selectedSessionFilter == 'ALL') ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: theme.colorScheme
                                                                .surfaceContainerHighest,
                                                            borderRadius:
                                                                BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            sessionLabel,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: theme.colorScheme.primary,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isCompleted)
                                              const Icon(Icons.check_circle_rounded,
                                                  color: Colors.grey, size: 28),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
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
                                                        ? () => _viewSavedNote(
                                                            ticket.patientId!)
                                                        : null,
                                                    icon: Icons.description,
                                                    label: 'View Note',
                                                  )
                                                : AppPrimaryButton(
                                                    onPressed: () =>
                                                        _selectPatient(ticket),
                                                    label: isInConsultation
                                                        ? 'Resume'
                                                        : 'Start',
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
            sessionId: _selectedSessionFilter != 'ALL' ? _selectedSessionFilter : null,
            availableSessions: _daySessions,
            existingTickets: _tickets,
          );
          if (added == true) {
            _loadQueue();
          }
        },
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'Add Patient',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        backgroundColor: AppColors.accent,
        elevation: 4,
      ),
    );
  }
}
