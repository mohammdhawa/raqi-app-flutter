import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App version string (e.g. `"1.0.5"`), the single source of truth for every
/// on-screen version caption.
///
/// Overridden in `main()` with the value from `PackageInfo.fromPlatform()`,
/// which resolves to the Android build's `versionName` — itself derived from
/// the `version` field in `pubspec.yaml`. Bumping the version there is now the
/// only edit needed to update the splash, login, and about screens.
final appVersionProvider = Provider<String>((ref) {
  throw UnimplementedError('appVersionProvider must be overridden in main()');
});
