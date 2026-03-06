import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceSettingsService {
  DeviceSettingsService._();

  static const MethodChannel _channel = MethodChannel('exam_tracker/device');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> openExactAlarmSettings() async {
    if (!_isAndroid) return false;
    final result =
        await _channel.invokeMethod<bool>('openExactAlarmSettings') ?? false;
    return result;
  }

  static Future<bool> openBatteryOptimizationSettings() async {
    if (!_isAndroid) return false;
    final result =
        await _channel.invokeMethod<bool>('openBatteryOptimizationSettings') ??
        false;
    return result;
  }

  static Future<bool> openNotificationSettings() async {
    if (!_isAndroid) return false;
    final result =
        await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
    return result;
  }

  static Future<bool> openAutoStartSettings() async {
    if (!_isAndroid) return false;
    final result =
        await _channel.invokeMethod<bool>('openAutoStartSettings') ?? false;
    return result;
  }

  static Future<bool> canScheduleExactAlarms() async {
    if (!_isAndroid) return true;
    final result =
        await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? false;
    return result;
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    final result =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        false;
    return result;
  }

  static Future<bool> areNotificationsEnabled() async {
    if (!_isAndroid) return true;
    final result =
        await _channel.invokeMethod<bool>('areNotificationsEnabled') ?? false;
    return result;
  }
}
