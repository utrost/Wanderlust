import 'dart:async';
import 'package:flutter/services.dart';

class RecordingBatteryStatus {
  const RecordingBatteryStatus({
    required this.supported,
    required this.exempt,
    required this.reviewed,
    required this.manufacturer,
  });
  factory RecordingBatteryStatus.fromMap(Map<Object?, Object?> value) =>
      RecordingBatteryStatus(
        supported: value['supported'] == true,
        exempt: value['exempt'] == true,
        reviewed: value['reviewed'] == true,
        manufacturer: value['manufacturer'] as String? ?? '',
      );
  final bool supported, exempt, reviewed;
  final String manufacturer;
  bool get needsLaunchHelp =>
      const ['honor', 'huawei'].contains(manufacturer.toLowerCase());
  bool get shouldExplain => supported && !exempt && !reviewed;
}

/// Permission state and the one-time explanation belong to this phone, not backups.
class RecordingBattery {
  const RecordingBattery();
  static const _channel = MethodChannel('wanderlust/battery');

  Future<RecordingBatteryStatus?> status() async {
    try {
      final value = await _channel
          .invokeMapMethod<Object?, Object?>('status')
          .timeout(const Duration(seconds: 2));
      return value == null ? null : RecordingBatteryStatus.fromMap(value);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> markReviewed() async {
    try {
      await _channel
          .invokeMethod<void>('markReviewed')
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      // Optional setup must never prevent recording.
    } on PlatformException {
      // Try again next time if the device could not persist this choice.
    } on TimeoutException {
      // Continue without waiting for an unresponsive platform channel.
    }
  }

  Future<RecordingBatteryStatus?> request() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'requestExemption',
    );
    return value == null ? null : RecordingBatteryStatus.fromMap(value);
  }

  Future<bool> openSettings() async =>
      await _channel.invokeMethod<bool>('openSettings') ?? false;
}
