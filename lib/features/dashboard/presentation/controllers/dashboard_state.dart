import '../data/models/practice_centre.dart';

enum DashboardStatus {
  initial,
  loading,
  loaded,
  error,
}

class DashboardState {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.summaries = const [],
    this.errorMessage,
  });

  final DashboardStatus status;
  final List<CentreSessionSummary> summaries;
  final String? errorMessage;

  bool get isLoading => status == DashboardStatus.loading;
  bool get hasError => status == DashboardStatus.error && errorMessage != null;

  /// Returns the top prioritized session summary if available.
  CentreSessionSummary? get prioritizedSummary =>
      summaries.isNotEmpty ? summaries.first : null;

  DashboardState copyWith({
    DashboardStatus? status,
    List<CentreSessionSummary>? summaries,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DashboardState(
      status: status ?? this.status,
      summaries: summaries ?? this.summaries,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
