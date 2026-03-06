import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<int, Timer> _inAppTimers = <int, Timer>{};
  bool _initialized = false;
  bool _available = true;
  bool _canScheduleExact = true;

  Future<void> initialize() async {
    if (_initialized) return;
    
    // Even if not fully available (e.g. web/desktop), we mark as initialized to prevent loops.
    // Real availability check happens inside platform blocks.
    _initialized = true; 

    tz_data.initializeTimeZones();

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: androidInit, iOS: ios);
      await _plugin.initialize(settings);

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
      final exactPermission = await androidPlugin
          ?.canScheduleExactNotifications();
      if (exactPermission != null) {
        _canScheduleExact = exactPermission;
      }
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);


    } on MissingPluginException {
      // Happens after adding plugin and doing hot-restart only.
      _available = false;
    }
  }

  Future<void> cancelExamNotifications(int examLocalId) async {
    return cancelExamNotificationsWithOffsets(
      examLocalId,
      offsetsMinutes: null,
    );
  }

  Future<void> cancelExamNotificationsWithOffsets(
    int examLocalId, {
    required Set<int>? offsetsMinutes,
  }) async {
    await initialize();
    if (!_available) return;
    final offsets = offsetsMinutes == null || offsetsMinutes.isEmpty
        ? _fallbackCancelOffsets
        : offsetsMinutes;
    for (final offset in offsets) {
      final id = _idFor(examLocalId, offset);
      _cancelInAppTimer(id);
      await _plugin.cancel(id);
    }
    final liveId = _idForLive(examLocalId);
    _cancelInAppTimer(liveId);
    await _plugin.cancel(liveId);
  }

  Future<void> scheduleExamNotifications({
    required int examLocalId,
    required String title,
    required DateTime examLocalDateTime,
    required Set<int> offsetsMinutes,
  }) async {
    await initialize();
    if (!_available) return;
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) return;
    await cancelExamNotificationsWithOffsets(
      examLocalId,
      offsetsMinutes: offsetsMinutes,
    );

    final sortedOffsets = offsetsMinutes.toList()..sort();
    final now = DateTime.now();
    var scheduledAny = false;

    for (final offset in sortedOffsets) {
      final trigger = examLocalDateTime.subtract(Duration(minutes: offset));
      final scheduleAt = _resolveScheduleTime(
        trigger: trigger,
        examAt: examLocalDateTime,
        now: now,
      );
      if (scheduleAt == null) continue;
      final body = '$title starts in ${_offsetLabel(offset)}';
      await _scheduleAt(
        id: _idFor(examLocalId, offset),
        title: 'Exam Reminder',
        body: body,
        scheduleAt: scheduleAt,
      );
      scheduledAny = true;
    }

    // If all configured reminders are already in the past but exam is still
    // ahead, fire a single near-immediate fallback reminder.
    if (!scheduledAny &&
        examLocalDateTime.isAfter(now) &&
        sortedOffsets.isNotEmpty) {
      final fallbackOffset = sortedOffsets.first;
      await _scheduleAt(
        id: _idFor(examLocalId, fallbackOffset),
        title: 'Exam Reminder',
        body: '$title is coming up soon',
        scheduleAt: now.add(const Duration(seconds: 5)),
      );
    }

    final liveAt = _resolveLiveScheduleTime(
      examAt: examLocalDateTime,
      now: now,
    );
    if (liveAt != null) {
      await _scheduleAt(
        id: _idForLive(examLocalId),
        title: 'Exam LIVE',
        body: '$title is live now',
        scheduleAt: liveAt,
      );
    }
  }

  Future<void> rescheduleAllFromRows(
    List<Map<String, dynamic>> examRows,
  ) async {
    await initialize();
    if (!_available) return;
    for (final row in examRows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final offsets = _parseReminderOffsets(
        row['reminder_offsets']?.toString(),
      );
      final rawDate = row['exam_datetime']?.toString() ?? '';
      final date = DateTime.tryParse(rawDate)?.toLocal();
      if (date == null) continue;
      final isCompletedRaw = row['is_completed'];
      final isCompleted =
          isCompletedRaw == true ||
          isCompletedRaw == 1 ||
          '$isCompletedRaw'.toLowerCase() == 'true';
      if (isCompleted) {
        await cancelExamNotificationsWithOffsets(id, offsetsMinutes: offsets);
        continue;
      }
      await scheduleExamNotifications(
        examLocalId: id,
        title: (row['title'] as String?) ?? 'Exam',
        examLocalDateTime: date,
        offsetsMinutes: offsets,
      );
    }
  }

  int _idFor(int localExamId, int offsetMinutes) {
    return (localExamId * 100000) + offsetMinutes;
  }

  int _idForLive(int localExamId) {
    return (localExamId * 100000) + 99999;
  }

  Future<bool> sendTestNotification() async {
    await initialize();
    if (!_available) return false;
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) return false;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      'ExamTracker Test',
      'Notifications are working on this device.',
      _notificationDetails,
    );
    return true;
  }

  Future<NotificationSetupStatus> getSetupStatus() async {
    await initialize();
    if (!_available) {
      return const NotificationSetupStatus(
        notificationsEnabled: false,
        exactAlarmsEnabled: false,
      );
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return const NotificationSetupStatus(
        notificationsEnabled: true,
        exactAlarmsEnabled: true,
      );
    }

    final notificationsEnabled =
        await android.areNotificationsEnabled() ?? true;
    final exactAlarmsEnabled =
        await android.canScheduleExactNotifications() ?? true;
    _canScheduleExact = exactAlarmsEnabled;
    return NotificationSetupStatus(
      notificationsEnabled: notificationsEnabled,
      exactAlarmsEnabled: exactAlarmsEnabled,
    );
  }

  String _offsetLabel(int minutes) {
    if (minutes >= 1440) {
      final days = minutes ~/ 1440;
      return '$days ${days == 1 ? 'day' : 'days'}';
    }
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return '$minutes min';
  }

  static const Set<int> _fallbackCancelOffsets = <int>{
    15,
    30,
    45,
    60,
    90,
    120,
    180,
    240,
    360,
    720,
    1440,
    2880,
    4320,
    10080,
    20160,
    43200,
  };

  Set<int> _parseReminderOffsets(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <int>{60};
    final parsed = raw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((e) => e > 0 && e <= 60 * 24 * 30)
        .toSet();
    if (parsed.isEmpty) return <int>{60};
    return parsed;
  }

  DateTime? _resolveScheduleTime({
    required DateTime trigger,
    required DateTime examAt,
    required DateTime now,
  }) {
    if (trigger.isAfter(now)) return trigger;
    if (!examAt.isAfter(now)) return null;
    final lateness = now.difference(trigger);
    if (lateness <= const Duration(minutes: 2)) {
      return now.add(const Duration(seconds: 3));
    }
    return null;
  }

  DateTime? _resolveLiveScheduleTime({
    required DateTime examAt,
    required DateTime now,
  }) {
    if (examAt.isAfter(now)) return examAt;
    final lateness = now.difference(examAt);
    if (lateness <= const Duration(minutes: 2)) {
      return now.add(const Duration(seconds: 3));
    }
    return null;
  }

  Future<void> _scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime scheduleAt,
  }) async {
    final target = tz.TZDateTime.from(scheduleAt.toUtc(), tz.UTC);
    _scheduleInAppTimer(
      id: id,
      title: title,
      body: body,
      scheduleAt: scheduleAt,
    );

    final preferredMode = _canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        _notificationDetails,
        androidScheduleMode: preferredMode,
      );
      return;
    } on PlatformException {
      if (preferredMode == AndroidScheduleMode.exactAllowWhileIdle) {
        _canScheduleExact = false;
      } else {
        return;
      }
    } catch (_) {
      // In-app timer fallback is already scheduled above.
      return;
    }

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // In-app timer fallback is already scheduled above.
    }
  }

  void _scheduleInAppTimer({
    required int id,
    required String title,
    required String body,
    required DateTime scheduleAt,
  }) {
    _cancelInAppTimer(id);
    final delay = scheduleAt.difference(DateTime.now());
    if (delay <= Duration.zero || delay > const Duration(days: 7)) {
      return;
    }
    _inAppTimers[id] = Timer(delay, () async {
      _inAppTimers.remove(id);
      try {
        await _plugin.show(id, title, body, _notificationDetails);
      } catch (_) {}
    });
  }

  void _cancelInAppTimer(int id) {
    _inAppTimers.remove(id)?.cancel();
  }

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'exam_reminders',
      'Exam Reminders',
      channelDescription: 'Notifies before exams begin',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<bool> _ensurePermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidEnabled = await android?.areNotificationsEnabled();
    if (androidEnabled == false) {
      await android?.requestNotificationsPermission();
      final recheck = await android?.areNotificationsEnabled();
      if (recheck == false) return false;
    }
    await android?.requestExactAlarmsPermission();
    final exactAlarmsEnabled = await android?.canScheduleExactNotifications();
    if (exactAlarmsEnabled != null) {
      _canScheduleExact = exactAlarmsEnabled;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final ok = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (ok == false) return false;
    }

    return true;
  }
}

class NotificationSetupStatus {
  const NotificationSetupStatus({
    required this.notificationsEnabled,
    required this.exactAlarmsEnabled,
  });

  final bool notificationsEnabled;
  final bool exactAlarmsEnabled;
}
