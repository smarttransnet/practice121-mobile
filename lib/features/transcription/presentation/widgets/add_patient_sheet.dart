import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/age_helper.dart';
import '../../../../core/utils/nic_decoder.dart';
import '../../data/services/queue_service.dart';
import '../controllers/transcription_controller.dart';
import 'add_child_dialog.dart';

enum AddPatientMode { input, otp, select, verified, notFound, register }

/// Multi-step Modal sheet for adding a patient to the current session queue.
/// Supports OTP verification, patient lookup, and priority assignment matching Web.
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
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        final bottomPadding = MediaQuery.of(sheetContext).padding.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: bottomInset + bottomPadding + 16,
            ),
            child: AddPatientSheet(
              doctorId: doctorId,
              practiceCentreId: practiceCentreId,
              sessionId: sessionId,
              existingTickets: existingTickets,
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends ConsumerState<AddPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _nicController = TextEditingController();

  // Registration form controllers
  final _regFormKey = GlobalKey<FormState>();
  final _regFirstNameController = TextEditingController();
  final _regLastNameController = TextEditingController();
  final _regDobController = TextEditingController();
  final _regNicController = TextEditingController();
  DateTime? _regSelectedDob;
  String _regGender = '';
  String? _regNicError;
  bool _regAutoFilledFromNic = false;

  AddPatientMode _mode = AddPatientMode.input;
  bool _showAdvancedSearch = false;

  int _priority = 0; // 0: Normal, 1: High, 2: Emergency
  bool _isSubmitting = false;
  String? _errorMessage;

  // OTP State
  String? _otpSessionId;
  String? _maskedMobile;
  String? _pendingMobile;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _mobileController.dispose();
    _otpController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nicController.dispose();
    _regFirstNameController.dispose();
    _regLastNameController.dispose();
    _regDobController.dispose();
    _regNicController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds > 0 ? seconds : 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldownSeconds <= 1) {
        t.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
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

  PatientRecord? _primaryPatientRecord;
  PatientRecord? _verifiedPatient;
  List<PatientRecord> _verifiedChildren = [];
  List<PatientRecord> _searchResults = [];

  Future<void> _handleCheckPatient() async {
    setState(() => _errorMessage = null);

    final rawMobile = _mobileController.text.trim();
    final hasMobile = rawMobile.isNotEmpty;
    final hasAdvanced = _firstNameController.text.trim().isNotEmpty ||
        _lastNameController.text.trim().isNotEmpty ||
        _nicController.text.trim().isNotEmpty;

    if (!hasMobile && !hasAdvanced) {
      setState(() => _errorMessage = 'Please enter a mobile number or advanced search parameters.');
      return;
    }

    if (hasMobile && !_isValidLkMobile(rawMobile)) {
      setState(() => _errorMessage = 'Please enter a valid Sri Lankan mobile number (e.g. 077 123 4567).');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final queueService = ref.read(queueServiceProvider);

      if (hasMobile) {
        final normalized = _normalizeLkMobile(rawMobile);
        _pendingMobile = normalized;

        final otpRes = await queueService.sendPatientOtp(normalized);

        if (otpRes.sessionId != null) {
          _otpSessionId = otpRes.sessionId;
          _maskedMobile = otpRes.maskedMobile ?? normalized;
          _startCooldown(otpRes.cooldownSeconds ?? 60);
          setState(() {
            _mode = AddPatientMode.otp;
            _isSubmitting = false;
          });
          return;
        }

        if (!hasAdvanced) {
          setState(() {
            _mode = AddPatientMode.notFound;
            _isSubmitting = false;
          });
          return;
        }
      }

      if (hasAdvanced) {
        final results = await queueService.searchPatients(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          nicNumber: _nicController.text.trim(),
        );

        if (results.isNotEmpty) {
          setState(() {
            _searchResults = results;
            _mode = AddPatientMode.select;
            _isSubmitting = false;
          });
          return;
        }
      }

      setState(() {
        _mode = AddPatientMode.notFound;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit OTP code.');
      return;
    }

    if (_otpSessionId == null || _pendingMobile == null) {
      setState(() => _errorMessage = 'Session expired. Please request a new OTP.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final queueService = ref.read(queueServiceProvider);
      final verifyRes = await queueService.verifyPatientOtp(_otpSessionId!, code);

      if (verifyRes.verified) {
        final lookup = await queueService.getPatientByMobile(
          _pendingMobile!,
          verificationToken: verifyRes.verificationToken,
        );

        if (lookup != null && lookup.primaryPatient.id.isNotEmpty) {
          setState(() {
            _primaryPatientRecord = lookup.primaryPatient;
            _verifiedChildren = List.from(lookup.children);
            _verifiedPatient = lookup.primaryPatient;
            _mode = AddPatientMode.verified;
            _isSubmitting = false;
          });
          return;
        } else {
          // New mobile number with no records -> Go directly to register patient step
          _regFirstNameController.clear();
          _regLastNameController.clear();
          _regDobController.clear();
          _regNicController.clear();
          _regSelectedDob = null;
          _regGender = '';
          _regNicError = null;
          _regAutoFilledFromNic = false;
          setState(() {
            _mode = AddPatientMode.register;
            _isSubmitting = false;
          });
          return;
        }
      }

      setState(() {
        _errorMessage = verifyRes.errorMessage ?? 'OTP verification failed. Please try again.';
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleOpenAddChildDialog() async {
    final parent = _primaryPatientRecord ?? _verifiedPatient;
    if (parent == null || parent.id.isEmpty) {
      setState(() => _errorMessage = 'Primary parent account is required to register a child.');
      return;
    }

    final newChild = await AddChildDialog.show(context, parentId: parent.id);
    if (newChild != null && mounted) {
      setState(() {
        _verifiedChildren.add(newChild);
        _verifiedPatient = newChild; // Auto-select newly registered child!
      });
    }
  }

  Future<void> _handleResendOtp() async {
    if (_cooldownSeconds > 0 || _otpSessionId == null) return;
    try {
      final queueService = ref.read(queueServiceProvider);
      final success = await queueService.resendPatientOtp(_otpSessionId!);
      if (success) {
        _startCooldown(30);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP has been resent.')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not resend OTP: $e');
    }
  }

  Future<void> _handleSelectPatientRecord(PatientRecord p) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final queueService = ref.read(queueServiceProvider);
      final rawMobile = _mobileController.text.trim();

      if (rawMobile.isNotEmpty) {
        final normalized = _normalizeLkMobile(rawMobile);
        if (normalized != p.mobileNumber) {
          await queueService.updatePatientMobile(p.id, normalized);
        }
      }

      setState(() {
        _primaryPatientRecord = p;
        _verifiedChildren = [];
        _verifiedPatient = p;
        _mode = AddPatientMode.verified;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select patient: $e';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleFinalConfirm() async {
    final targetMobile = _verifiedPatient?.mobileNumber.isNotEmpty ?? false
        ? _verifiedPatient!.mobileNumber
        : _mobileController.text.trim();

    if (targetMobile.isEmpty) {
      setState(() => _errorMessage = 'Patient mobile number is required.');
      return;
    }

    final normalizedMobile = _normalizeLkMobile(targetMobile);

    // Client-side duplicate check for active tickets in current session
    final isDuplicate = widget.existingTickets.any((ticket) {
      if (ticket.status >= 4) return false; // Completed/Cancelled allowed
      if (_verifiedPatient != null && ticket.id.isNotEmpty && ticket.patientName == _verifiedPatient!.firstName) {
        return true;
      }
      final ticketMobile = _normalizeLkMobile(ticket.patientMobile);
      return ticketMobile.isNotEmpty && ticketMobile == normalizedMobile;
    });

    if (isDuplicate) {
      final name = _verifiedPatient != null
          ? '${_verifiedPatient!.firstName} ${_verifiedPatient!.lastName ?? ''}'.trim()
          : targetMobile;
      setState(() {
        _errorMessage = 'Patient ($name) is already in the queue for this session.';
      });
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final queueService = ref.read(queueServiceProvider);

      await queueService.addPatientQueueTicket(
        patientMobile: targetMobile,
        doctorId: widget.doctorId,
        practiceCentreId: widget.practiceCentreId,
        priority: _priority,
        visitDate: todayStr,
        patientId: _verifiedPatient?.id,
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
            // Header Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _mode == AddPatientMode.otp
                        ? Icons.lock_clock_rounded
                        : _mode == AddPatientMode.verified
                            ? Icons.verified_user_rounded
                            : Icons.person_add_alt_1_rounded,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _mode == AddPatientMode.otp
                        ? 'Verify Patient OTP'
                        : _mode == AddPatientMode.verified
                            ? 'Patient Verified'
                            : _mode == AddPatientMode.select
                                ? 'Select Patient Record'
                                : _mode == AddPatientMode.register
                                    ? 'Register New Patient'
                                    : 'Add Patient to Queue',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

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

            // Body modes
            if (_mode == AddPatientMode.input) _buildInputStep(theme),
            if (_mode == AddPatientMode.otp) _buildOtpStep(theme),
            if (_mode == AddPatientMode.select) _buildSelectStep(theme),
            if (_mode == AddPatientMode.notFound) _buildNotFoundStep(theme),
            if (_mode == AddPatientMode.register) _buildRegisterStep(theme),
            if (_mode == AddPatientMode.verified) _buildVerifiedStep(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        ),
        const SizedBox(height: 12),

        InkWell(
          onTap: () => setState(() => _showAdvancedSearch = !_showAdvancedSearch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _showAdvancedSearch ? Icons.arrow_drop_down_circle_rounded : Icons.search_rounded,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  _showAdvancedSearch ? 'Hide Advanced Search' : 'Advanced Search (Name / NIC)',
                  style: theme.textTheme.labelLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),

        if (_showAdvancedSearch) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              hintText: 'First Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              hintText: 'Last Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nicController,
            decoration: const InputDecoration(
              hintText: 'NIC Number',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],

        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleCheckPatient,
          icon: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search_rounded),
          label: Text(_isSubmitting ? 'Verifying Patient...' : 'Lookup & Verify Patient'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Security OTP Verification Required',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'A 6-digit OTP security code has been sent to ${_maskedMobile ?? _pendingMobile}. Enter code below to access patient record.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          scrollPadding: const EdgeInsets.fromLTRB(24, 40, 24, 180),
          decoration: const InputDecoration(
            hintText: '••••••',
            counterText: '',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _cooldownSeconds > 0 ? null : _handleResendOtp,
              child: Text(
                _cooldownSeconds > 0 ? 'Resend OTP in ${_cooldownSeconds}s' : 'Resend OTP',
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _mode = AddPatientMode.input),
              child: const Text('Change Number'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleVerifyOtp,
          icon: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded),
          label: Text(_isSubmitting ? 'Verifying OTP...' : 'Verify OTP & View Details'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Patient Record',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _searchResults.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final p = _searchResults[index];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                title: Text('${p.firstName} ${p.lastName ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Mobile: ${p.mobileNumber} ${p.nicNumber != null ? '| NIC: ${p.nicNumber}' : ''}'),
                trailing: FilledButton(
                  onPressed: () => _handleSelectPatientRecord(p),
                  child: const Text('Select'),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => setState(() => _mode = AddPatientMode.input),
          child: const Text('Back to Search'),
        ),
      ],
    );
  }

  Widget _buildNotFoundStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.person_off_rounded, size: 48, color: Colors.orange),
        const SizedBox(height: 12),
        Text(
          'No Existing Patient Found',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'No patient record was found for ${_mobileController.text.trim()}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: () {
            // Pre-clear registration fields
            _regFirstNameController.clear();
            _regLastNameController.clear();
            _regDobController.clear();
            _regNicController.clear();
            _regSelectedDob = null;
            _regGender = '';
            setState(() => _mode = AddPatientMode.register);
          },
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('Register New Patient'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _mode = AddPatientMode.input),
          child: const Text('Back to Search'),
        ),
      ],
    );
  }

  void _onRegNicChanged(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _regNicError = null;
        _regAutoFilledFromNic = false;
      });
      return;
    }

    final decode = decodeNic(trimmed);
    if (decode.isValid && decode.normalizedNic != null) {
      setState(() {
        _regNicError = null;
        _regAutoFilledFromNic = true;
        if (decode.dateOfBirth != null) {
          _regDobController.text = decode.dateOfBirth!;
          _regSelectedDob = DateTime.tryParse(decode.dateOfBirth!);
        }
        if (decode.gender != null) {
          _regGender = decode.gender!;
        }
      });
    } else {
      setState(() {
        _regAutoFilledFromNic = false;
        if (trimmed.length >= 10) {
          _regNicError = decode.error ?? 'Please enter a valid Sri Lankan NIC number.';
        } else {
          _regNicError = null;
        }
      });
    }
  }

  Future<void> _pickRegDob(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _regSelectedDob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select Patient Date of Birth',
    );
    if (picked != null) {
      final dobStr =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _regSelectedDob = picked;
        _regDobController.text = dobStr;

        // Cross-check with NIC if entered
        final nic = _regNicController.text.trim();
        if (nic.isNotEmpty) {
          final decode = decodeNic(nic);
          if (decode.isValid && decode.dateOfBirth != null && decode.dateOfBirth != dobStr) {
            _regNicError = 'Date of birth does not match the provided NIC. Please check both values.';
          } else if (decode.isValid) {
            _regNicError = null;
          }
        }
      });
    }
  }

  Future<void> _handleRegisterPatient() async {
    if (!(_regFormKey.currentState?.validate() ?? false)) return;

    final firstName = _regFirstNameController.text.trim();
    if (firstName.isEmpty) {
      setState(() => _errorMessage = 'First name is required');
      return;
    }

    final dobStr = _regDobController.text.trim();
    final nic = _regNicController.text.trim();

    // Age validation: if over 18, NIC is required
    final age = calculateAge(dobStr);
    if (age.years > 18 && nic.isEmpty) {
      setState(() => _errorMessage = 'NIC is required for patients over 18 years old.');
      return;
    }

    // NIC validation and cross-check
    if (nic.isNotEmpty) {
      final decode = decodeNic(nic);
      if (!decode.isValid) {
        setState(() => _errorMessage = decode.error ?? 'Please enter a valid Sri Lankan NIC number.');
        return;
      }

      if (dobStr.isNotEmpty && decode.dateOfBirth != null && decode.dateOfBirth != dobStr) {
        setState(() => _errorMessage = 'Date of birth does not match the provided NIC. Please check both values.');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final queueService = ref.read(queueServiceProvider);
      final mobile = _pendingMobile ?? _normalizeLkMobile(_mobileController.text.trim());

      final newPatientId = await queueService.registerPatient(
        firstName: firstName,
        lastName: _regLastNameController.text.trim().isNotEmpty ? _regLastNameController.text.trim() : null,
        dateOfBirth: dobStr.isNotEmpty ? dobStr : null,
        nicNumber: nic.isNotEmpty ? normalizeNic(nic) : null,
        gender: _regGender.isNotEmpty ? _regGender : null,
        mobileNumber: mobile,
        isMobileOwner: true,
        createdByDoctorId: widget.doctorId,
      );

      // Registration succeeded — set verified patient and proceed to queue step
      setState(() {
        _verifiedPatient = PatientRecord(
          id: newPatientId,
          firstName: firstName,
          lastName: _regLastNameController.text.trim().isNotEmpty ? _regLastNameController.text.trim() : null,
          mobileNumber: mobile,
          nicNumber: nic.isNotEmpty ? normalizeNic(nic) : null,
          dateOfBirth: dobStr.isNotEmpty ? dobStr : null,
          gender: _regGender.isNotEmpty ? _regGender : null,
        );
        _primaryPatientRecord = _verifiedPatient;
        _verifiedChildren = [];
        _mode = AddPatientMode.verified;
        _isSubmitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildRegisterStep(ThemeData theme) {
    final dobStr = _regDobController.text.trim();
    final ageInfo = calculateAge(dobStr);

    return Form(
      key: _regFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verified Mobile: ${_pendingMobile ?? _mobileController.text.trim()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // First Name *
          TextFormField(
            controller: _regFirstNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'First Name *',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_rounded, size: 20),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'First name is required';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Last Name
          TextFormField(
            controller: _regLastNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Last Name',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),

          // Date of Birth
          TextFormField(
            controller: _regDobController,
            readOnly: true,
            onTap: () => _pickRegDob(context),
            decoration: InputDecoration(
              labelText: 'Date of Birth',
              hintText: 'yyyy-mm-dd',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.calendar_today_rounded, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today_rounded, size: 20),
                onPressed: () => _pickRegDob(context),
              ),
              helperText: dobStr.isNotEmpty ? 'Age: ${ageInfo.formatted}' : 'Required if over 18 years old',
            ),
          ),
          const SizedBox(height: 12),

          // NIC Number
          TextFormField(
            controller: _regNicController,
            onChanged: _onRegNicChanged,
            decoration: InputDecoration(
              labelText: 'NIC Number (Optional if under 18)',
              hintText: 'e.g. 882441524V or 199824401524',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_rounded, size: 20),
              errorText: _regNicError,
              helperText: _regAutoFilledFromNic ? 'DOB and Gender auto-filled from NIC' : null,
              helperStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),

          // Gender
          DropdownButtonFormField<String>(
            key: ValueKey(_regGender),
            initialValue: _regGender.isEmpty ? null : _regGender,
            decoration: InputDecoration(
              labelText: 'Gender',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.wc_rounded, size: 20),
              helperText: _regAutoFilledFromNic ? 'Auto-filled from NIC' : null,
            ),
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _regGender = val);
            },
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => setState(() => _mode = AddPatientMode.input),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _handleRegisterPatient,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.person_add_rounded),
                  label: Text(_isSubmitting ? 'Registering...' : 'Save & Continue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedStep(ThemeData theme) {
    final parent = _primaryPatientRecord ?? _verifiedPatient!;
    final selectedId = _verifiedPatient?.id ?? parent.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Patient record found. Select who this appointment/queue ticket is for:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section Title + Add Child Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Who is this appointment for?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _handleOpenAddChildDialog,
              icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.accent),
              label: const Text(
                'Add Child',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 1. Primary Account Option Card
        _buildPatientOptionCard(
          theme: theme,
          title: '${parent.firstName} ${parent.lastName ?? ''}'.trim(),
          subtitle: 'Primary Account (Self) ${parent.nicNumber != null && parent.nicNumber!.isNotEmpty ? '• NIC: ${parent.nicNumber}' : ''}',
          isSelected: selectedId == parent.id,
          onTap: () => setState(() => _verifiedPatient = parent),
        ),

        // 2. Children Option Cards
        for (final child in _verifiedChildren) ...[
          const SizedBox(height: 8),
          _buildPatientOptionCard(
            theme: theme,
            title: '${child.firstName} ${child.lastName ?? ''}'.trim(),
            subtitle: 'Dependent (Child) • ${child.gender != null ? 'Gender: ${child.gender}' : 'Child Patient'}',
            isSelected: selectedId == child.id,
            onTap: () => setState(() => _verifiedPatient = child),
          ),
        ],

        const SizedBox(height: 18),

        // Queue Priority
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
          onSelectionChanged: (set) => setState(() => _priority = set.first),
        ),
        const SizedBox(height: 24),

        // Confirm & Add to Queue Action Button
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleFinalConfirm,
          icon: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded),
          label: Text(_isSubmitting ? 'Adding Ticket...' : 'Confirm & Add to Queue'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPatientOptionCard({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.accent : theme.colorScheme.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSelected ? Icons.person_rounded : Icons.person_outline_rounded,
                color: isSelected ? AppColors.accent : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.accent : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? AppColors.accent : theme.colorScheme.outlineVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
