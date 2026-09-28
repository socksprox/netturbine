/// One knot in a fan curve: at [temp] °C, run the fan at [percent] 0–100.
class CurvePoint {
  const CurvePoint({required this.temp, required this.percent});

  final int temp;
  final int percent;

  Map<String, dynamic> toJson() => {'temp': temp, 'percent': percent};

  static CurvePoint fromJson(Map<String, dynamic> json) => CurvePoint(
        temp: (json['temp'] as num).round().clamp(0, 120),
        percent: (json['percent'] as num).round().clamp(0, 100),
      );

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.temp == temp && other.percent == percent;

  @override
  int get hashCode => Object.hash(temp, percent);
}

/// A named temperature→speed curve. One profile drives all controllable
/// fans off a single sensor ([sensorId], matching [TempSensor.id]).
///
/// Built-in profiles ship with the app; users can rename/edit them and
/// duplicate them into custom profiles. Persisted as JSON via
/// `SystemIntegration.saveSettings`.
class FanProfile {
  FanProfile({
    required this.id,
    required this.name,
    required this.sensorId,
    required List<CurvePoint> points,
    this.builtIn = false,
  }) : points = List.unmodifiable(
          [...points]..sort((a, b) => a.temp.compareTo(b.temp)),
        );

  final String id;
  final String name;

  /// [TempSensor.id] of the sensor that drives this curve.
  final String sensorId;

  /// Curve knots, sorted by ascending temperature. Needs at least one.
  final List<CurvePoint> points;

  /// True for the shipped Quiet/Balanced/Performance presets — customs can
  /// be deleted, built-ins only reset via [factoryVersion].
  final bool builtIn;

  /// Piecewise-linear interpolation. Below the first point and above the
  /// last, the end point's percent holds. Returns null when [celsius] is
  /// unavailable or the curve has no points — callers should treat that
  /// as "cannot evaluate" and fall back to firmware control.
  int? speedFor(int? celsius) {
    if (celsius == null || points.isEmpty) return null;
    if (celsius <= points.first.temp) return points.first.percent;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (celsius <= b.temp) {
        if (b.temp == a.temp) return b.percent;
        final t = (celsius - a.temp) / (b.temp - a.temp);
        return (a.percent + t * (b.percent - a.percent)).round();
      }
    }
    return points.last.percent;
  }

  /// Whether the curve itself (sensor + points) matches — ignores name.
  bool curveSameAs(FanProfile other) =>
      sensorId == other.sensorId && _listEquals(points, other.points);

  /// Whether this profile differs from its shipped factory version.
  /// Always false for custom profiles.
  bool get isModified {
    final factory = _factories[id];
    return builtIn && factory != null && this != factory();
  }

  FanProfile copyWith({
    String? name,
    String? sensorId,
    List<CurvePoint>? points,
  }) =>
      FanProfile(
        id: id,
        name: name ?? this.name,
        sensorId: sensorId ?? this.sensorId,
        points: points ?? this.points,
        builtIn: builtIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sensorId': sensorId,
        'points': [for (final p in points) p.toJson()],
        if (!builtIn) 'custom': true,
      };

  static FanProfile? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final sensorId = json['sensorId'];
    final rawPoints = json['points'];
    if (id is! String || name is! String || sensorId is! String) return null;
    if (rawPoints is! List || rawPoints.isEmpty) return null;
    final points = <CurvePoint>[];
    for (final p in rawPoints) {
      if (p is Map) {
        points.add(CurvePoint.fromJson(Map<String, dynamic>.from(p)));
      }
    }
    if (points.isEmpty) return null;
    return FanProfile(
      id: id,
      name: name,
      sensorId: sensorId,
      points: points,
      builtIn: _factories.containsKey(id) && json['custom'] != true,
    );
  }

  /// The shipped factory version of a built-in profile, or null for ids
  /// that aren't built in.
  static FanProfile? factoryVersion(String id) => _factories[id]?.call();

  static final Map<String, FanProfile Function()> _factories = {
    'quiet': _quiet,
    'balanced': _balanced,
    'performance': _performance,
  };

  static List<FanProfile> get builtInProfiles =>
      [_quiet(), _balanced(), _performance()];

  static FanProfile _quiet() => FanProfile(
        id: 'quiet',
        name: 'Quiet',
        sensorId: 'cpu',
        builtIn: true,
        points: const [
          CurvePoint(temp: 45, percent: 0),
          CurvePoint(temp: 60, percent: 15),
          CurvePoint(temp: 75, percent: 35),
          CurvePoint(temp: 90, percent: 60),
          CurvePoint(temp: 95, percent: 100),
        ],
      );

  static FanProfile _balanced() => FanProfile(
        id: 'balanced',
        name: 'Balanced',
        sensorId: 'cpu',
        builtIn: true,
        points: const [
          CurvePoint(temp: 40, percent: 20),
          CurvePoint(temp: 55, percent: 30),
          CurvePoint(temp: 70, percent: 50),
          CurvePoint(temp: 85, percent: 75),
          CurvePoint(temp: 95, percent: 100),
        ],
      );

  static FanProfile _performance() => FanProfile(
        id: 'performance',
        name: 'Performance',
        sensorId: 'cpu',
        builtIn: true,
        points: const [
          CurvePoint(temp: 35, percent: 40),
          CurvePoint(temp: 50, percent: 55),
          CurvePoint(temp: 65, percent: 70),
          CurvePoint(temp: 80, percent: 85),
          CurvePoint(temp: 95, percent: 100),
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is FanProfile &&
      other.id == id &&
      other.name == name &&
      other.sensorId == sensorId &&
      other.builtIn == builtIn &&
      _listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(id, name, sensorId, builtIn);

  static bool _listEquals(List<CurvePoint> a, List<CurvePoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
