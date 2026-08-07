import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/services/queue_service.dart';
import '../controllers/transcription_controller.dart';

/// Modal sheet for adding a patient to the current session queue.
class AddPatientSheet extends ConsumerStatefulWidget {
  const AddPatientSheet({
    super.key,
    required this.doctorId,
    required this.practiceCentreId,
    this.sessionId,
    this.existingTickets = const [],
    this.onPatientAdded,
  });

  final String doctorId;
  final String practiceCentreId;
  final String? sessionId;
  final List<QueueTicket> existingTickets;
  final VoidCallback? onPatientAdded;

  static Future<bool?> show(
    BuildContext context, {
    required String doctorId,
    required String practiceCentreId,
    String? sessionId,
    List<QueueTicket> existingTickets = const [],
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddPatientSheet(
          doctorId: doctorId,
          practiceCentreId: practiceCentreId,
          sessionId: sessionId,
          existingTickets: existingTickets,
        ),
      ),
    );
  }

  @override
  ConsumerState<AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends ConsumerState<AddPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();

  int _priority = 0; // 0: Normal, 1: High, 2: Emergency
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  bool _isValidLkMobile(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('94')) {
      return digits.length == 11 && digits.startsWith('947');
    }
    return digits.length == 10 && digits.startsWith('07');
  }

  String _normalizeLkMobile(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('94')) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  Future<void> _handleSubmit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final rawMobile = _mobileController.text.trim();
    if (!_isValidLkMobile(rawMobile)) {
      setState(() {
        _errorMessage = 'Please enter a valid Sri Lankan mobile number (e.g. 0771234567).';
      });
      return;
    }

    final normalizedMobile = _normalizeLkMobile(rawMobile);

    // Client-side duplicate check for active tickets in this session
    final isDuplicate = widget.existingTickets.any((ticket) {
      if (ticket.status >= 4) return false; // Completed / Cancelled allow re-adding
      final ticketMobile = _normalizeLkMobile(ticket.patientMobile);
      return ticketMobile.isNotEmpty && ticketMobile == normalizedMobile;
    });

    if (isDuplicate) {
      setState(() {
        _errorMessage = 'Patient ($rawMobile) is already in the queue for this session.';
      });
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final queueService = ref.read(queueServiceProvider);

      await queueService.addPatientQueueTicket(
        patientMobile: rawMobile,
        doctorId: widget.doctorId,
        practiceCentreId: widget.practiceCentreId,
        priority: _priority,
        visitDate: todayStr,
        sessionId: widget.sessionId,
      );

      if (mounted) {
        widget.onPatientAdded?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add Patient to Queue',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              'Patient Mobile Number',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              scrollPadding: const EdgeInsets.fromLTRB(24, 40, 24, 180),
              decoration: const InputDecoration(
                hintText: 'e.g. 077 123 4567',
                prefixIcon: Icon(Icons.phone_android_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Patient mobile number is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text(
              'Queue Priority',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 0, label: Text('Normal')),
                ButtonSegment<int>(value: 1, label: Text('High')),
                ButtonSegment<int>(value: 2, label: Text('Emergency')),
              ],
              selected: {_priority},
              onSelectionChanged: (set) {
                setState(() {
                  _priority = set.first;
                });
              },
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_isSubmitting ? 'Adding Patient...' : 'Add Patient to Queue'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
