import 'api_select_stub.dart' if (dart.library.io) 'api_select_io.dart';

/// OS-integration boundary: launch-at-startup and window/tray glue.
///
/// Implemented per-OS in `lib/api/<os>/` next to the fan backend.
abstract class SystemIntegration {
  /// Returns the integration for the current platform, or an
  /// [UnsupportedSystemIntegration] elsewhere.
  factory SystemIntegration.forCurrentPlatform() =>
      createPlatformSystemIntegration();

  /// Whether the app is registered to start on user login.
  Future<bool> isLaunchAtStartupEnabled();

  /// Registers/unregisters the app to start on login.
  Future<void> setLaunchAtStartup(bool enabled);

  /// Brings the app window to the foreground.
  Future<void> showWindow();

  /// Quits the app (as opposed to hiding the window to the tray).
  Future<void> quitApp();

  /// Loads the persisted settings blob (a JSON string owned by the app
  /// layer), or null when nothing has been saved yet.
  Future<String?> loadSettings();

  /// Persists the settings blob. Best-effort — storage failures must not
  /// take the app down.
  Future<void> saveSettings(String json);
}
