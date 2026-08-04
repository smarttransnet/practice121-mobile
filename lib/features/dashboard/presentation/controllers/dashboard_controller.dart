import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/models/practice_centre.dart';
import '../../data/services/practice_centre_service.dart';
import '../../domain/session_prioritizer.dart';
import 'dashboard_state.dart';

final practiceCentreServiceProvider = Provider<PracticeCentreService>((ref) {
  return PracticeCentreService();
});

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
  final config = ref.watch(appConfigProvider);
  final authState = ref.watch(authControllerProvider);
  final practiceCentreService = ref.watch(practiceCentreServiceProvider);

  return DashboardController(
    practiceCentreService: practiceCentreService,
    config: config,
    accessToken: authState.accessToken,
    doctorId: authState.doctorId,
  );
});

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required PracticeCentreService practiceCentreService,
    required AppConfig config,
    required String? accessToken,
    required String? doctorId,
  })  : _practiceCentreService = practiceCentreService,
        _config = config,
        _accessToken = accessToken,
        _doctorId = doctorId,
        super(const DashboardState()) {
    if (_accessToken != null && _accessToken.isNotEmpty) {
      loadDashboard();
    }
  }

  final PracticeCentreService _practiceCentreService;
  final AppConfig _config;
  final String? _accessToken;
  final String? _doctorId;

  Future<void> loadDashboard() async {
    if (_accessToken == null || _accessToken.isEmpty) {
      state = state.copyWith(
        status: DashboardStatus.error,
        errorMessage: 'User is unauthenticated.',
      );
      return;
    }

    state = state.copyWith(
      status: DashboardStatus.loading,
      clearError: true,
    );

    try {
      AppLogger.i('DashboardController: loading centres for doctor $_doctorId');
      final centres = await _practiceCentreService.getDoctorPracticeCentres(
        baseUrl: _config.clientApiBaseUrl,
        accessToken: _accessToken,
      );

      final queueMetricsMap = <String, Map<String, int>>{};

      // Fetch queue stats for each centre in parallel
      await Future.wait(
        centres.map((centre) async {
          final metrics = await _practiceCentreService.getQueueMetrics(
            baseUrl: _config.clientApiBaseUrl,
            accessToken: _accessToken,
            practiceCentreId: centre.id,
            doctorId: centre.doctorId.isNotEmpty ? centre.doctorId : (_doctorId ?? ''),
          );
          queueMetricsMap[centre.id] = metrics;
        }),
      );

      // Run prioritization algorithm
      final prioritizedSummaries = SessionPrioritizer.prioritizeCentres(
        centres: centres,
        queueMetricsMap: queueMetricsMap,
      );

      state = state.copyWith(
        status: DashboardStatus.loaded,
        summaries: prioritizedSummaries,
      );
    } catch (e) {
      AppLogger.e('DashboardController: error loading dashboard', e);
      final msg =
          e is Failure ? e.message : 'Failed to load dashboard data: $e';
      state = state.copyWith(
        status: DashboardStatus.error,
        errorMessage: msg,
      );
    }
  }

  /// Fetches latest active patient queue count (waiting + in-consultation) for a session.
  Future<int> checkActiveQueueCount(CentreSessionSummary summary) async {
    if (_accessToken == null || _accessToken.isEmpty) {
      return 0;
    }

    try {
      final docId = summary.centre.doctorId.isNotEmpty
          ? summary.centre.doctorId
          : (_doctorId ?? '');

      final metrics = await _practiceCentreService.getQueueMetrics(
        baseUrl: _config.clientApiBaseUrl,
        accessToken: _accessToken,
        practiceCentreId: summary.centre.id,
        doctorId: docId,
      );

      final waiting = metrics['waiting'] ?? 0;
      final active = metrics['active'] ?? 0;
      final completed = metrics['completed'] ?? 0;
      final total = metrics['total'] ?? 0;

      final activeCount = waiting + active;
      AppLogger.i(
          'DashboardController: queue check for ${summary.centre.clinicName} -> waiting=$waiting, active=$active, completed=$completed, total=$total');
      return activeCount;
    } catch (e) {
      AppLogger.w('DashboardController: error checking queue count: $e');
      return 0;
    }
  }
}
