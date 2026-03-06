import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kPrimaryBlue = Color(0xFF2563EB);
const Color kDarkText = Color(0xFF1E2A42);
const Color kMutedText = Color(0xFF6E7B91);
const Color kBorder = Color(0xFFD5DDE8);
const Color kSurfaceCard = Color(0xFFE7ECF3);

final supabase = Supabase.instance.client;
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);
final ValueNotifier<int> examDurationHours = ValueNotifier(1);
final ValueNotifier<bool> showTestNotificationButton = ValueNotifier(true);
final ValueNotifier<Set<int>> reminderOffsetsMinutes = ValueNotifier<Set<int>>(
  <int>{60},
);
final ValueNotifier<Set<int>> reminderOptionMinutes = ValueNotifier<Set<int>>(
  <int>{60, 120, 180, 1440, 10080},
);

const List<int> kReminderOptionsMinutes = <int>[60, 120, 180, 1440, 10080];

const String _themeModeKey = 'theme_mode';
const String _examDurationHoursKey = 'default_exam_duration_hours';
const String _showTestButtonKey = 'show_test_notification_button';
const String _reminderOffsetsKey = 'reminder_offsets_minutes';
const String _reminderOptionsKey = 'reminder_option_minutes';
const String kAppVersion = '1.0.0+1';

Future<void> loadLocalSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString(_themeModeKey);
  if (savedTheme == ThemeMode.dark.name) {
    appThemeMode.value = ThemeMode.dark;
  } else if (savedTheme == ThemeMode.light.name) {
    appThemeMode.value = ThemeMode.light;
  }

  final savedDuration = prefs.getInt(_examDurationHoursKey);
  if (savedDuration != null && savedDuration >= 1 && savedDuration <= 4) {
    examDurationHours.value = savedDuration;
  }

  final savedShowTestButton = prefs.getBool(_showTestButtonKey);
  if (savedShowTestButton != null) {
    showTestNotificationButton.value = savedShowTestButton;
  }

  final savedOffsets = prefs.getStringList(_reminderOffsetsKey);
  if (savedOffsets != null && savedOffsets.isNotEmpty) {
    final parsed = savedOffsets
        .map(int.tryParse)
        .whereType<int>()
        .where((e) => e > 0 && e <= 60 * 24 * 30)
        .toSet();
    if (parsed.isNotEmpty) {
      reminderOffsetsMinutes.value = parsed;
    }
  }

  final savedOptions = prefs.getStringList(_reminderOptionsKey);
  if (savedOptions != null && savedOptions.isNotEmpty) {
    final parsed = savedOptions
        .map(int.tryParse)
        .whereType<int>()
        .where((e) => e > 0 && e <= 60 * 24 * 30)
        .toSet();
    if (parsed.isNotEmpty) {
      reminderOptionMinutes.value = parsed;
    }
  }
}

Future<void> persistThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_themeModeKey, mode.name);
}

Future<void> persistExamDuration(int hours) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_examDurationHoursKey, hours);
}

Future<void> persistShowTestNotificationButton(bool show) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_showTestButtonKey, show);
}

Future<void> persistReminderOffsets(Set<int> offsets) async {
  final prefs = await SharedPreferences.getInstance();
  final safe = offsets.where((e) => e > 0 && e <= 60 * 24 * 30).toSet();
  if (safe.isEmpty) {
    safe.add(60);
  }
  await prefs.setStringList(
    _reminderOffsetsKey,
    safe.map((e) => '$e').toList(),
  );
}

Future<void> persistReminderOptions(Set<int> options) async {
  final prefs = await SharedPreferences.getInstance();
  final safe = options.where((e) => e > 0 && e <= 60 * 24 * 30).toSet();
  if (safe.isEmpty) {
    safe.addAll(kReminderOptionsMinutes);
  }
  await prefs.setStringList(
    _reminderOptionsKey,
    (safe.toList()..sort()).map((e) => '$e').toList(),
  );
}
