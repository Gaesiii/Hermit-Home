class RelayTelemetryModel {
  const RelayTelemetryModel({
    required this.heater,
    required this.mist,
    required this.fan,
    required this.light,
  });

  final bool heater;
  final bool mist;
  final bool fan;
  final bool light;

  factory RelayTelemetryModel.fromJson(Map<String, dynamic> json) {
    return RelayTelemetryModel(
      heater: json['heater'] == true,
      mist: json['mist'] == true,
      fan: json['fan'] == true,
      light: json['light'] == true,
    );
  }
}

class TelemetryModel {
  const TelemetryModel({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.lux,
    required this.sensorFault,
    required this.userOverride,
    required this.relays,
  });

  final String id;
  final String userId;
  final DateTime timestamp;
  final double? temperature;
  final double? humidity;
  final double lux;
  final bool sensorFault;
  final bool userOverride;
  final RelayTelemetryModel relays;

  factory TelemetryModel.fromJson(Map<String, dynamic> json) {
    return TelemetryModel(
      id: (json['id'] as String?) ?? '',
      userId: (json['userId'] as String?) ?? '',
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      temperature: _toNullableDouble(json['temperature']),
      humidity: _toNullableDouble(json['humidity']),
      lux: _toDouble(json['lux']) ?? 0,
      sensorFault: json['sensor_fault'] == true,
      userOverride: json['user_override'] == true,
      relays: RelayTelemetryModel.fromJson(
        (json['relays'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
    );
  }

  static double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    return _toDouble(value);
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
