import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/services/queue_service.dart';
import '../controllers/transcription_controller.dart';

/// Modal Dialog for registering a child dependent under a parent account.
/// Matches Web Image 3 (`Add Child Patient` modal).
class AddChildDialog extends ConsumerStatefulWidget {
  const AddChildDialog({
    super.key,
    this.parentId,
    this.mobileNumber,
    this.doctorId,
  });

  final String? parentId;
  final String? mobileNumber;
  final String? doctorId;

  static Future<PatientRecord?> show(
    BuildContext context, {
    String? parentId,
    String? mobileNumber,
    String? doctorId,
  }) {
    return showDialog<PatientRecord>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddChildDialog(parentId: parentId, mobileNumber: mobileNumber, doctorId: doctorId),
    );
  }

  @override
  ConsumerState<AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends ConsumerState<AddChildDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();

  DateTime? _selectedDob;
  String _gender = 'Male';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  String _formatAge(DateTime dob) {
    final now = DateTime.now();
    int years = now.year - dob.year;
    int months = now.month - dob.month;
    if (now.day < dob.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }
    if (years < 0) return '0 mos';
    final parts = <String>[];
    if (years > 0) parts.add('$years yr${years > 1 ? 's' : ''}');
    if (months > 0 || years == 0) parts.add('$months mo${months != 1 ? 's' : ''}');
    return parts.join(' ');
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final initialDate = _selectedDob ?? DateTime(now.year - 5, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(eighteenYearsAgo) ? initialDate : now,
      firstDate: eighteenYearsAgo.add(const Duration(days: 1)),
      lastDate: now,
      helpText: 'Select Child Date of Birth (< 18 yrs)',
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleSaveChild() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedDob == null) {
      setState(() => _errorMessage = 'Please select date of birth.');
      return;
    }

    final now = DateTime.now();
    int ageYears = now.year - _selectedDob!.year;
    if (now.month < _selectedDob!.month || (now.month == _selectedDob!.month && now.day < _selectedDob!.day)) {
      ageYears--;
    }

    if (ageYears >= 18) {
      setState(() => _errorMessage = 'Child patient age must be strictly under 18 years old.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final queueService = ref.read(queueServiceProvider);
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final fullName = '$firstName $lastName'.trim();
      final dobStr = _dobController.text.trim();

      PatientRecord? newChild;

      if (widget.parentId != null) {
        newChild = await queueService.addChildPatient(
          widget.parentId!,
          firstName: firstName,
          lastName: lastName.isEmpty ? null : lastName,
          fullName: fullName,
          dateOfBirth: dobStr,
          gender: _gender,
        );
      } else if (widget.mobileNumber != null) {
        final newPatientId = await queueService.registerPatient(
          firstName: firstName,
          lastName: lastName.isEmpty ? null : lastName,
          dateOfBirth: dobStr,
          gender: _gender,
          mobileNumber: widget.mobileNumber!,
          isMobileOwner: false,
          createdByDoctorId: widget.doctorId,
        );
        newChild = PatientRecord(
          id: newPatientId,
          firstName: firstName,
          lastName: lastName.isEmpty ? null : lastName,
          mobileNumber: widget.mobileNumber!,
          dateOfBirth: dobStr,
          gender: _gender,
        );
      } else {
        throw Exception('Either parentId or mobileNumber must be provided.');
      }

      if (mounted) {
        Navigator.of(context).pop(newChild);
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.child_care_rounded, color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Child Patient',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Under 18 years of age',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Register a child under the primary parent account.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // First Name *
              TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'First name is required';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Last Name
              TextFormField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Date of Birth *
              TextFormField(
                controller: _dobController,
                readOnly: true,
                onTap: () => _pickDate(context),
                decoration: InputDecoration(
                  labelText: 'Date of Birth *',
                  hintText: 'yyyy-mm-dd',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_rounded, size: 20),
                    onPressed: () => _pickDate(context),
                  ),
                  helperText: _selectedDob != null ? 'Age: ${_formatAge(_selectedDob!)}' : 'Must be under 18 years old',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Date of birth is required';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Gender *
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _gender = val);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleSaveChild,
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.child_care_rounded, size: 18),
          label: Text(_isSubmitting ? 'Saving...' : 'Save Child'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
        ),
      ],
    );
  }
}
