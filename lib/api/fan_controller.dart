import 'api_select_stub.dart' if (dart.library.io) 'api_select_io.dart';

/// A single fan's current state.
class FanInfo {
  const FanInfo({
    required this.id,
    required this.label,
    this.rpm,
    this.speedPercent,
    this.canControl = false,
    this.isAuto = true,
  });

  final String id;
  final String label;
  final int? rpm;

  /// Current speed as 0–100, or null when the backend can't read it.
  final int? speedPercent;

  /// Whether [FanController.setSpeed] works for this fan.
  final bool canControl;

  /// Whether the fan is under automatic (firmware) control — false once a
  /// manual override is active.
  final bool isAuto;
}

/// What the backend supports on this machine.
class FanCapabilities {
  const FanCapabilities({required this.canReadRpm, required this.canSetSpeed});

  static const none =
      FanCapabilities(canReadRpm: false, canSetSpeed: false);

  final bool canReadRpm;
  final bool canSetSpeed;
}

/// Failure from the platform backend. Never escapes as a crash — callers catch
/// this and surface state to the UI.
class FanControlException implements Exception {
  const FanControlException(this.message);

  final String message;

  @override
  String toString() => 'FanControlException: $message';
}

/// Platform-agnostic fan control boundary.
///
/// Implemented per-OS in `lib/api/<os>/`. Contracts here must be implementable
/// on Windows today and macOS later — no OS-specific types leak through.
abstract class FanController {
  /// Returns the controller for the current platform, or an
  /// [UnsupportedFanController] on platforms without an implementation.
  factory FanController.forCurrentPlatform() => createPlatformFanController();

  /// Most recent fan snapshot.
  List<FanInfo> get fans;

  /// Fan snapshots emitted on each backend poll.
  Stream<List<FanInfo>> get fanStream;

  /// What the backend can do on this machine. Never assume a fan is
  /// controllable — check per-fan [FanInfo.canControl].
  FanCapabilities get capabilities;

  /// Overrides [fanId] to [percent] (0–100).
  Future<void> setSpeed(String fanId, int percent);

  /// Returns [fanId] to automatic (firmware) control.
  Future<void> resetToAuto(String fanId);

  /// Releases polling timers and channels.
  Future<void> dispose();
}
