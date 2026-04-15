class DeviceControlState {
  const DeviceControlState({
    required this.fan,
    required this.heater,
    required this.mist,
    required this.light,
  });

  final bool fan;
  final bool heater;
  final bool mist;
  final bool light;

  static const DeviceControlState initial = DeviceControlState(
    fan: false,
    heater: false,
    mist: false,
    light: false,
  );

  DeviceControlState copyWith({
    bool? fan,
    bool? heater,
    bool? mist,
    bool? light,
  }) {
    return DeviceControlState(
      fan: fan ?? this.fan,
      heater: heater ?? this.heater,
      mist: mist ?? this.mist,
      light: light ?? this.light,
    );
  }

  bool valueForKey(String key) {
    switch (key) {
      case 'fan':
        return fan;
      case 'heater':
        return heater;
      case 'mist':
        return mist;
      case 'light':
        return light;
      default:
        return false;
    }
  }

  DeviceControlState withKey(String key, bool value) {
    switch (key) {
      case 'fan':
        return copyWith(fan: value);
      case 'heater':
        return copyWith(heater: value);
      case 'mist':
        return copyWith(mist: value);
      case 'light':
        return copyWith(light: value);
      default:
        return this;
    }
  }

  DeviceControlState applyPatch(Map<String, dynamic> patch) {
    DeviceControlState next = this;

    final fanValue = patch['fan'];
    if (fanValue is bool) {
      next = next.copyWith(fan: fanValue);
    }

    final heaterValue = patch['heater'];
    if (heaterValue is bool) {
      next = next.copyWith(heater: heaterValue);
    }

    final mistValue = patch['mist'];
    if (mistValue is bool) {
      next = next.copyWith(mist: mistValue);
    }

    final lightValue = patch['light'];
    if (lightValue is bool) {
      next = next.copyWith(light: lightValue);
    }

    return next;
  }
}

class DeviceControlSnapshot {
  const DeviceControlSnapshot({
    required this.state,
    required this.historyCount,
    this.lastUpdatedAt,
  });

  final DeviceControlState state;
  final int historyCount;
  final DateTime? lastUpdatedAt;
}

class DeviceControlApplyResult {
  const DeviceControlApplyResult({
    required this.appliedValue,
    required this.mistLockedOff,
  });

  final bool appliedValue;
  final bool mistLockedOff;
}
