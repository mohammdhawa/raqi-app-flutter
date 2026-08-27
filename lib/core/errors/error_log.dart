import 'package:flutter/foundation.dart';

/// Logs an unexpected failure without leaking its detail in release builds.
///
/// `debugPrint` is NOT compiled out of release builds — it forwards to
/// `print`, which on Android lands in logcat, readable over `adb` and by
/// anything holding `READ_LOGS` on older devices. So `debugPrint('$e')` in a
/// catch block publishes whatever the exception happened to say: a
/// `FileSystemException` carries an absolute on-device path, a `DioException`
/// dumps the request (headers and body included), and a stack trace names
/// every frame.
///
/// In release only the exception's TYPE is written. A type is useful for
/// triage and cannot carry a path, a token, a bound value or response
/// content. Full detail, including the stack, stays in debug builds.
void logUnexpected(String context, Object error, [StackTrace? stackTrace]) {
  for (final line in unexpectedLogLines(
    context,
    error,
    stackTrace,
    debug: kDebugMode,
  )) {
    debugPrint(line);
  }
}

/// Exactly what [logUnexpected] writes, as a pure function.
///
/// Split out because the whole point of this helper is its RELEASE behaviour,
/// and the test suite always runs with `kDebugMode == true` — passing [debug]
/// explicitly is the only way to assert that the release path stays quiet.
@visibleForTesting
List<String> unexpectedLogLines(
  String context,
  Object error,
  StackTrace? stackTrace, {
  required bool debug,
}) {
  if (!debug) {
    return ['$context: ${error.runtimeType}'];
  }
  return [
    '$context: $error',
    if (stackTrace != null) '$stackTrace',
  ];
}
