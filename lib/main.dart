import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/notification_service.dart';

Future<void> main() async {
  debugPrint("App starting main()...");
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  }
  debugPrint("Loading local settings...");
  await loadLocalSettings();
  debugPrint("Initializing Supabase...");
  await Supabase.initialize(
    url: 'https://exxcgzcimbqyocodlaiz.supabase.co',
    anonKey: 'sb_publishable_lRxmUkZi05R-y378OQ_3dg_dOjyqY83',
  );
  debugPrint("Supabase initialized. Running App.");
  runApp(const ExamTrackerApp());
  debugPrint("Application running. Initializing notifications...");
  NotificationService.instance.initialize();
  debugPrint("Notifications initialized.");
}
