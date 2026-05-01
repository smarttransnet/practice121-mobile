import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Application-wide logger.
///
/// Wraps the `logger` package in a thin facade so the rest of the codebase
/// does not depend on a specific implementation. In release mode we only
/// surface warnings and above to keep mobile log noise (and battery cost) low.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: !kReleaseMode,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static void d(String message) => _logger.d(message);
  static void i(String message) => _logger.i(message);
  static void w(String message, [Object? error, StackTrace? stack]) =>
      _logger.w(message, error: error, stackTrace: stack);
  static void e(String message, [Object? error, StackTrace? stack]) =>
      _logger.e(message, error: error, stackTrace: stack);
}
