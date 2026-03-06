import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class RepoSyncStatus {
  const RepoSyncStatus({
    required this.isSyncing,
    required this.pendingOps,
    required this.lastSuccessAt,
    this.lastErrorMessage,
  });

  const RepoSyncStatus.initial()
    : isSyncing = false,
      pendingOps = 0,
      lastSuccessAt = null,
      lastErrorMessage = null;

  final bool isSyncing;
  final int pendingOps;
  final DateTime? lastSuccessAt;
  final String? lastErrorMessage;
}

class ManualSyncRepository {
  factory ManualSyncRepository({SupabaseClient? supabase}) {
    _instance ??= ManualSyncRepository._internal(supabase: supabase ?? Supabase.instance.client);
    return _instance!;
  }

  ManualSyncRepository._internal({required this.supabase});

  static ManualSyncRepository? _instance;
  static ManualSyncRepository get instance {
    if (_instance == null) {
      throw StateError('ManualSyncRepository not initialized. call ManualSyncRepository(supabase: ...) first.');
    }
    return _instance!;
  }

  final SupabaseClient supabase;

  Database? _db;
  String? _userId;
  bool _syncing = false;
  bool _disposed = false;
  Timer? _syncTimer;

  final StreamController<List<Map<String, dynamic>>> _categoriesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _examsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _milestonesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _studySessionsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<RepoSyncStatus> _syncStatusController =
      StreamController<RepoSyncStatus>.broadcast();
  RepoSyncStatus _latestSyncStatus = const RepoSyncStatus.initial();
  DateTime? _lastSyncSuccessAt;
  String? _lastSyncErrorMessage;

  Stream<List<Map<String, dynamic>>> get categoriesStream =>
      _categoriesController.stream;
  Stream<List<Map<String, dynamic>>> get examsStream => _examsController.stream;
  Stream<List<Map<String, dynamic>>> get milestonesStream =>
      _milestonesController.stream;
  Stream<List<Map<String, dynamic>>> get studySessionsStream =>
      _studySessionsController.stream;
  Stream<RepoSyncStatus> get syncStatusStream => _syncStatusController.stream;
  RepoSyncStatus get latestSyncStatus => _latestSyncStatus;

  Future<void> initialize(String userId) async {
    _userId = userId;
    await _database();
    await _emitAll();

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  Future<void> dispose() async {
    _disposed = true;
    _syncTimer?.cancel();
    await _categoriesController.close();
    await _examsController.close();
    await _milestonesController.close();
    await _studySessionsController.close();
    await _syncStatusController.close();
    await _db?.close();
  }

  Future<void> addCategory(String name) async {
    final db = await _database();
    final uid = _requireUserId();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert('categories_local', {
      'remote_id': null,
      'user_id': uid,
      'name': name.trim(),
      'is_deleted': 0,
      'pending_op': 'insert',
      'updated_at_ms': nowMs,
      'created_at_ms': nowMs,
    });
    await _emitCategories();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  Future<void> deleteCategory(int localCategoryId) async {
    final db = await _database();
    final uid = _requireUserId();
    final row = await db.query(
      'categories_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localCategoryId, uid],
      limit: 1,
    );
    if (row.isEmpty) return;

    final current = row.first;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final pending = '${current['pending_op']}';
    final remoteId = current['remote_id'] as int?;

    final nextPending = remoteId == null && pending == 'insert'
        ? 'insert'
        : 'delete';

    await db.update(
      'categories_local',
      {'is_deleted': 1, 'pending_op': nextPending, 'updated_at_ms': nowMs},
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localCategoryId, uid],
    );

    final examRows = await db.query(
      'exams_local',
      where: 'category_local_id = ? AND user_id = ? AND is_deleted = 0',
      whereArgs: [localCategoryId, uid],
    );
    for (final exam in examRows) {
      final examLocalId = (exam['local_id'] as num).toInt();
      final examPending = '${exam['pending_op']}';
      await db.update(
        'exams_local',
        {
          'category_local_id': null,
          'pending_op': examPending == 'insert' ? 'insert' : 'update',
          'updated_at_ms': nowMs,
        },
        where: 'local_id = ? AND user_id = ?',
        whereArgs: [examLocalId, uid],
      );
    }

    await _emitAll();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  Future<void> addExam({
    required String title,
    required DateTime examDateTime,
    required int categoryLocalId,
    required String difficulty,
    Set<int> reminderOffsetsMinutes = const <int>{60},
  }) async {
    await addExamAndReturnId(
      title: title,
      examDateTime: examDateTime,
      categoryLocalId: categoryLocalId,
      difficulty: difficulty,
      reminderOffsetsMinutes: reminderOffsetsMinutes,
    );
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.rawQuery(
      '''
      SELECT local_id AS id, name 
      FROM categories_local 
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY LOWER(name) ASC
      ''',
      [uid],
    );
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<int> addExamAndReturnId({
    required String title,
    required DateTime examDateTime,
    required int categoryLocalId,
    required String difficulty,
    Set<int> reminderOffsetsMinutes = const <int>{60},
  }) async {
    final db = await _database();
    final uid = _requireUserId();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final localId = await db.insert('exams_local', {
      'remote_id': null,
      'user_id': uid,
      'title': title.trim(),
      'exam_datetime': examDateTime.toUtc().toIso8601String(),
      'category_local_id': categoryLocalId,
      'difficulty': difficulty.trim(),
      'reminder_offsets': _serializeReminderOffsets(reminderOffsetsMinutes),
      'is_completed': 0,
      'is_deleted': 0,
      'pending_op': 'insert',
      'updated_at_ms': nowMs,
      'created_at_ms': nowMs,
    });
    await _emitExams();
    await _emitSyncStatus();
    unawaited(syncNow());

    // Schedule notifications immediately
    await NotificationService.instance.scheduleExamNotifications(
      examLocalId: localId,
      title: title,
      examLocalDateTime: examDateTime,
      offsetsMinutes: reminderOffsetsMinutes,
    );

    return localId;
  }

  Future<bool> updateExam({
    required int localExamId,
    required String title,
    required DateTime examDateTime,
    required int categoryLocalId,
    required String difficulty,
    Set<int> reminderOffsetsMinutes = const <int>{60},
  }) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'exams_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final pending = '${rows.first['pending_op']}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final isFuture = examDateTime.isAfter(DateTime.now());
    final currentCompleted = (rows.first['is_completed'] as num?)?.toInt() ?? 0;

    await db.update(
      'exams_local',
      {
        'title': title.trim(),
        'exam_datetime': examDateTime.toUtc().toIso8601String(),
        'category_local_id': categoryLocalId,
        'difficulty': difficulty.trim(),
        'reminder_offsets': _serializeReminderOffsets(reminderOffsetsMinutes),
        'is_completed': isFuture ? 0 : currentCompleted,
        'pending_op': pending == 'insert' ? 'insert' : 'update',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
    );
    await _emitExams();
    await _emitSyncStatus();
    unawaited(syncNow());

    // Update notifications
    await NotificationService.instance.cancelExamNotifications(localExamId);
    await NotificationService.instance.scheduleExamNotifications(
      examLocalId: localExamId,
      title: title,
      examLocalDateTime: examDateTime,
      offsetsMinutes: reminderOffsetsMinutes,
    );

    return true;
  }

  Future<bool> markExamComplete(int localExamId) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'exams_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final pending = '${rows.first['pending_op']}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'exams_local',
      {
        'is_completed': 1,
        'pending_op': pending == 'insert' ? 'insert' : 'update',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
    );
    await _emitExams();
    await _emitSyncStatus();
    unawaited(syncNow());

    // Cancel notifications for completed exam
    await NotificationService.instance.cancelExamNotifications(localExamId);

    return true;
  }

  Future<void> deleteExam(int localExamId) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'exams_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final pending = '${row['pending_op']}';
    final remoteId = row['remote_id'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'exams_local',
      {
        'is_deleted': 1,
        'pending_op': remoteId == null && pending == 'insert'
            ? 'insert'
            : 'delete',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
    );
    await _emitExams();
    await _emitSyncStatus();
    unawaited(syncNow());

    // Cancel notifications for deleted exam
    await NotificationService.instance.cancelExamNotifications(localExamId);
  }

  // --- MILESTONES ---

  Future<void> addMilestone(int examLocalId, String name) async {
    final db = await _database();
    final uid = _requireUserId();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert('milestones_local', {
      'remote_id': null,
      'user_id': uid,
      'exam_local_id': examLocalId,
      'name': name.trim(),
      'is_completed': 0,
      'is_deleted': 0,
      'pending_op': 'insert',
      'updated_at_ms': nowMs,
      'created_at_ms': nowMs,
    });
    await _emitMilestones();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  Future<void> toggleMilestone(int localMilestoneId, bool isCompleted) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'milestones_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localMilestoneId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final pending = '${rows.first['pending_op']}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'milestones_local',
      {
        'is_completed': isCompleted ? 1 : 0,
        'pending_op': pending == 'insert' ? 'insert' : 'update',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localMilestoneId, uid],
    );
    await _emitMilestones();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  Future<void> deleteMilestone(int localMilestoneId) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'milestones_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localMilestoneId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final pending = '${rows.first['pending_op']}';
    final remoteId = rows.first['remote_id'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'milestones_local',
      {
        'is_deleted': 1,
        'pending_op': remoteId == null && pending == 'insert'
            ? 'insert'
            : 'delete',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localMilestoneId, uid],
    );
    await _emitMilestones();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  // --- STUDY SESSIONS ---

  Future<void> addStudySession(
    int examLocalId,
    DateTime startTime,
    int durationMinutes,
  ) async {
    final db = await _database();
    final uid = _requireUserId();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert('study_sessions_local', {
      'remote_id': null,
      'user_id': uid,
      'exam_local_id': examLocalId,
      'start_time': startTime.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'is_deleted': 0,
      'pending_op': 'insert',
      'updated_at_ms': nowMs,
      'created_at_ms': nowMs,
    });
    await _emitStudySessions();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  Future<void> deleteStudySession(int localSessionId) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'study_sessions_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localSessionId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final pending = '${rows.first['pending_op']}';
    final remoteId = rows.first['remote_id'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'study_sessions_local',
      {
        'is_deleted': 1,
        'pending_op': remoteId == null && pending == 'insert'
            ? 'insert'
            : 'delete',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localSessionId, uid],
    );
    await _emitStudySessions();
    await _emitSyncStatus();
    unawaited(syncNow());
  }

  // --- EXAMS CONTINUED ---


  Future<void> undoDeleteExam(int localExamId) async {
    final db = await _database();
    final uid = _requireUserId();
    final rows = await db.query(
      'exams_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final remoteId = row['remote_id'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'exams_local',
      {
        'is_deleted': 0,
        'pending_op': remoteId == null ? 'insert' : 'none',
        'updated_at_ms': nowMs,
      },
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
    );
    await _emitExams();
    await _emitSyncStatus();
    unawaited(syncNow());

    // Reschedule notifications for restored exam
    // We need to fetch the exam details to reschedule correctly
    final examRows = await db.query(
      'exams_local',
      where: 'local_id = ?',
      whereArgs: [localExamId],
    );
    if (examRows.isNotEmpty) {
      final exam = examRows.first;
      final offsets = _parseReminderOffsets('${exam['reminder_offsets']}');
      final dateRaw = exam['exam_datetime'] as String?;
      final date = DateTime.tryParse(dateRaw ?? '')?.toLocal();
      if (date != null) {
        await NotificationService.instance.scheduleExamNotifications(
          examLocalId: localExamId,
          title: (exam['title'] as String?) ?? 'Exam',
          examLocalDateTime: date,
          offsetsMinutes: offsets,
        );
      }
    }
  }

  Future<void> syncNow() async {
    if (_syncing || _disposed || _userId == null) return;
    _syncing = true;
    final db = await _database();
    await _emitSyncStatus(syncing: true);
    try {
      await _pushCategories(db);
      await _pushExams(db);
      await _pullFromRemote(db);
      await _pushCategories(db);
      await _pushExams(db);
      _lastSyncSuccessAt = DateTime.now();
      _lastSyncErrorMessage = null;
    } catch (_) {
      // Keep the app usable offline; retry on next periodic/manual sync.
      _lastSyncErrorMessage = 'Last sync failed. Will retry automatically.';
    } finally {
      _syncing = false;
      await _emitAll();
      await _emitSyncStatus(syncing: false);
    }
  }

  Future<void> _pushCategories(Database db) async {
    final uid = _requireUserId();
    final pendingRows = await db.query(
      'categories_local',
      where: 'user_id = ? AND pending_op != ?',
      whereArgs: [uid, 'none'],
      orderBy: 'local_id ASC',
    );

    for (final row in pendingRows) {
      final localId = (row['local_id'] as num).toInt();
      final remoteId = (row['remote_id'] as num?)?.toInt();
      final name = (row['name'] as String?) ?? 'Untitled';
      final isDeleted = (row['is_deleted'] as num?)?.toInt() == 1;
      final pending = '${row['pending_op']}';

      try {
        if (pending == 'insert') {
          if (isDeleted) {
            await _hardDeleteCategory(db, localId);
            continue;
          }
          final inserted = await supabase
              .from('categories')
              .insert({'name': name, 'user_id': uid})
              .select('id')
              .single();
          await db.update(
            'categories_local',
            {
              'remote_id': (inserted['id'] as num).toInt(),
              'pending_op': 'none',
              'is_deleted': 0,
            },
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        } else if (pending == 'update') {
          if (remoteId == null) {
            await db.update(
              'categories_local',
              {'pending_op': 'insert'},
              where: 'local_id = ? AND user_id = ?',
              whereArgs: [localId, uid],
            );
            continue;
          }
          if (isDeleted) {
            await db.update(
              'categories_local',
              {'pending_op': 'delete'},
              where: 'local_id = ? AND user_id = ?',
              whereArgs: [localId, uid],
            );
            continue;
          }
          await supabase
              .from('categories')
              .update({'name': name})
              .eq('id', remoteId)
              .eq('user_id', uid);
          await db.update(
            'categories_local',
            {'pending_op': 'none'},
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        } else if (pending == 'delete') {
          if (remoteId != null) {
            await supabase
                .from('categories')
                .delete()
                .eq('id', remoteId)
                .eq('user_id', uid);
          }
          await _hardDeleteCategory(db, localId);
        }
      } catch (_) {
        // Leave row pending for next sync.
      }
    }
  }

  Future<void> _pushExams(Database db) async {
    final uid = _requireUserId();
    final pendingRows = await db.query(
      'exams_local',
      where: 'user_id = ? AND pending_op != ?',
      whereArgs: [uid, 'none'],
      orderBy: 'local_id ASC',
    );

    for (final row in pendingRows) {
      final localId = (row['local_id'] as num).toInt();
      final remoteId = (row['remote_id'] as num?)?.toInt();
      final isDeleted = (row['is_deleted'] as num?)?.toInt() == 1;
      final pending = '${row['pending_op']}';
      final title = (row['title'] as String?) ?? 'Untitled Exam';
      final examDateTime = (row['exam_datetime'] as String?) ?? '';
      final difficulty = (row['difficulty'] as String?) ?? 'Medium';
      final isCompleted = (row['is_completed'] as num?)?.toInt() == 1;
      final categoryLocalId = (row['category_local_id'] as num?)?.toInt();
      final grade = row['grade'] as String?;
      final targetGrade = row['target_grade'] as String?;
      final credits = (row['credits'] as num?)?.toDouble();

      int? categoryRemoteId;
      if (categoryLocalId != null) {
        final categoryRows = await db.query(
          'categories_local',
          where: 'local_id = ? AND user_id = ?',
          whereArgs: [categoryLocalId, uid],
          limit: 1,
        );
        if (categoryRows.isNotEmpty) {
          final c = categoryRows.first;
          final categoryDeleted = (c['is_deleted'] as num?)?.toInt() == 1;
          if (!categoryDeleted) {
            categoryRemoteId = (c['remote_id'] as num?)?.toInt();
          }
        }
      }

      try {
        if (pending == 'insert') {
          if (isDeleted) {
            await _hardDeleteExam(db, localId);
            continue;
          }
          if (categoryRemoteId == null) {
            continue;
          }
          final payload = <String, dynamic>{
            'title': title,
            'exam_datetime': examDateTime,
            'category_id': categoryRemoteId,
            'difficulty': difficulty,
            'is_completed': isCompleted,
            'user_id': uid,
            if (grade != null) 'grade': grade,
            if (targetGrade != null) 'target_grade': targetGrade,
            if (credits != null) 'credits': credits,
          };
          final inserted = await _insertExamRemote(payload);
          await db.update(
            'exams_local',
            {
              'remote_id': (inserted['id'] as num).toInt(),
              'pending_op': 'none',
              'is_deleted': 0,
            },
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        } else if (pending == 'update') {
          if (remoteId == null) {
            await db.update(
              'exams_local',
              {'pending_op': 'insert'},
              where: 'local_id = ? AND user_id = ?',
              whereArgs: [localId, uid],
            );
            continue;
          }
          if (isDeleted) {
            await db.update(
              'exams_local',
              {'pending_op': 'delete'},
              where: 'local_id = ? AND user_id = ?',
              whereArgs: [localId, uid],
            );
            continue;
          }
          if (categoryRemoteId == null) continue;
          final payload = <String, dynamic>{
            'title': title,
            'exam_datetime': examDateTime,
            'category_id': categoryRemoteId,
            'difficulty': difficulty,
            'is_completed': isCompleted,
            'grade': grade,
            'target_grade': targetGrade,
            'credits': credits,
          };
          await _updateExamRemote(remoteId, uid, payload);
          await db.update(
            'exams_local',
            {'pending_op': 'none'},
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        } else if (pending == 'delete') {
          if (remoteId != null) {
            await supabase
                .from('exams')
                .delete()
                .eq('id', remoteId)
                .eq('user_id', uid);
          }
          await _hardDeleteExam(db, localId);
        }
      } catch (_) {
        // Leave row pending for next sync.
      }
    }
  }

  Future<void> _pullFromRemote(Database db) async {
    final uid = _requireUserId();
    final categoriesRemote = await supabase
        .from('categories')
        .select('id, name')
        .eq('user_id', uid)
        .order('name');

    final categoryLocalByRemote = <int, int>{};
    final remoteCategoryIds = <int>{};

    for (final dynamic raw in categoriesRemote) {
      final row = Map<String, dynamic>.from(raw as Map);
      final remoteId = (row['id'] as num).toInt();
      remoteCategoryIds.add(remoteId);
      final name = (row['name'] as String?) ?? 'Unnamed';
      final existing = await db.query(
        'categories_local',
        where: 'remote_id = ? AND user_id = ?',
        whereArgs: [remoteId, uid],
        limit: 1,
      );
      if (existing.isEmpty) {
        final localId = await db.insert('categories_local', {
          'remote_id': remoteId,
          'user_id': uid,
          'name': name,
          'is_deleted': 0,
          'pending_op': 'none',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
        categoryLocalByRemote[remoteId] = localId;
      } else {
        final existingRow = existing.first;
        final localId = (existingRow['local_id'] as num).toInt();
        categoryLocalByRemote[remoteId] = localId;
        final pending = '${existingRow['pending_op']}';
        if (pending == 'none') {
          await db.update(
            'categories_local',
            {
              'name': name,
              'is_deleted': 0,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        }
      }
    }

    final localCategories = await db.query(
      'categories_local',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    for (final local in localCategories) {
      final localId = (local['local_id'] as num).toInt();
      final pending = '${local['pending_op']}';
      final remoteId = (local['remote_id'] as num?)?.toInt();
      if (remoteId == null) continue;
      if (pending != 'none') continue;
      if (!remoteCategoryIds.contains(remoteId)) {
        await _hardDeleteCategory(db, localId);
      }
    }

    final examsRemote = await supabase
        .from('exams')
        .select(
          'id, title, exam_datetime, category_id, difficulty, is_completed, grade, target_grade, credits',
        )
        .eq('user_id', uid)
        .order('exam_datetime');

    final remoteExamIds = <int>{};
    for (final dynamic raw in examsRemote) {
      final row = Map<String, dynamic>.from(raw as Map);
      final remoteId = (row['id'] as num).toInt();
      remoteExamIds.add(remoteId);
      final title = (row['title'] as String?) ?? 'Untitled Exam';
      final examDateTime = (row['exam_datetime'] as String?) ?? '';
      final difficulty = (row['difficulty'] as String?) ?? 'Medium';
      final isCompleted =
          row['is_completed'] == true ||
          row['is_completed'] == 1 ||
          '${row['is_completed']}'.toLowerCase() == 'true';
      final grade = row['grade'] as String?;
      final targetGrade = row['target_grade'] as String?;
      final credits = (row['credits'] as num?)?.toDouble();
      final categoryRemoteId = (row['category_id'] as num?)?.toInt();
      final categoryLocalId = categoryRemoteId == null
          ? null
          : categoryLocalByRemote[categoryRemoteId];

      final existing = await db.query(
        'exams_local',
        where: 'remote_id = ? AND user_id = ?',
        whereArgs: [remoteId, uid],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('exams_local', {
          'remote_id': remoteId,
          'user_id': uid,
          'title': title,
          'exam_datetime': examDateTime,
          'category_local_id': categoryLocalId,
          'difficulty': difficulty,
          'reminder_offsets': '60',
          'is_completed': isCompleted ? 1 : 0,
          'grade': grade,
          'target_grade': targetGrade,
          'credits': credits,
          'is_deleted': 0,
          'pending_op': 'none',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        final existingRow = existing.first;
        final localId = (existingRow['local_id'] as num).toInt();
        final pending = '${existingRow['pending_op']}';
        if (pending == 'none') {
          await db.update(
            'exams_local',
            {
              'title': title,
              'exam_datetime': examDateTime,
              'category_local_id': categoryLocalId,
              'difficulty': difficulty,
              'is_completed': isCompleted ? 1 : 0,
              'grade': grade,
              'target_grade': targetGrade,
              'credits': credits,
              'is_deleted': 0,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'local_id = ? AND user_id = ?',
            whereArgs: [localId, uid],
          );
        }
      }
    }

    final localExams = await db.query(
      'exams_local',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    for (final local in localExams) {
      final localId = (local['local_id'] as num).toInt();
      final pending = '${local['pending_op']}';
      final remoteId = (local['remote_id'] as num?)?.toInt();
      if (remoteId == null) continue;
      if (pending != 'none') continue;
      if (!remoteExamIds.contains(remoteId)) {
        await _hardDeleteExam(db, localId);
      }
    }
  }

  Future<Map<String, dynamic>> _insertExamRemote(
    Map<String, dynamic> payload,
  ) async {
    try {
      final inserted = await supabase
          .from('exams')
          .insert(payload)
          .select('id')
          .single();
      return Map<String, dynamic>.from(inserted);
    } on PostgrestException catch (error) {
      final lowered = error.message.toLowerCase();
      if (lowered.contains('is_completed')) {
        payload.remove('is_completed');
      }
      final inserted = await supabase
          .from('exams')
          .insert(payload)
          .select('id')
          .single();
      return Map<String, dynamic>.from(inserted);
    }
  }

  Future<void> _updateExamRemote(
    int remoteId,
    String uid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await supabase
          .from('exams')
          .update(payload)
          .eq('id', remoteId)
          .eq('user_id', uid);
    } on PostgrestException catch (error) {
      final lowered = error.message.toLowerCase();
      if (lowered.contains('is_completed')) {
        payload.remove('is_completed');
        await supabase
            .from('exams')
            .update(payload)
            .eq('id', remoteId)
            .eq('user_id', uid);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _hardDeleteCategory(Database db, int localCategoryId) async {
    final uid = _requireUserId();
    await db.update(
      'exams_local',
      {'category_local_id': null},
      where: 'category_local_id = ? AND user_id = ?',
      whereArgs: [localCategoryId, uid],
    );
    await db.delete(
      'categories_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localCategoryId, uid],
    );
  }

  Future<void> _hardDeleteExam(Database db, int localExamId) async {
    final uid = _requireUserId();
    await db.delete(
      'exams_local',
      where: 'local_id = ? AND user_id = ?',
      whereArgs: [localExamId, uid],
    );
  }

  Future<void> _emitAll() async {
    await _emitCategories();
    await _emitExams();
    await _emitMilestones();
    await _emitStudySessions();
  }

  Future<void> _emitSyncStatus({bool? syncing}) async {
    if (_disposed || _userId == null) return;
    final db = await _database();
    final uid = _requireUserId();
    final categoryPending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM categories_local '
            'WHERE user_id = ? AND pending_op != ?',
            [uid, 'none'],
          ),
        ) ??
        0;
    final examPending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM exams_local '
            'WHERE user_id = ? AND pending_op != ?',
            [uid, 'none'],
          ),
        ) ??
        0;

    _latestSyncStatus = RepoSyncStatus(
      isSyncing: syncing ?? _syncing,
      pendingOps: categoryPending + examPending,
      lastSuccessAt: _lastSyncSuccessAt,
      lastErrorMessage: _lastSyncErrorMessage,
    );
    if (!_syncStatusController.isClosed) {
      _syncStatusController.add(_latestSyncStatus);
    }
  }

  Future<void> _emitCategories() async {
    if (_disposed || _userId == null) return;
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        local_id AS id,
        name
      FROM categories_local
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY LOWER(name) ASC
      ''',
      [_requireUserId()],
    );
    if (!_categoriesController.isClosed) {
      _categoriesController.add(
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    }
  }

  Future<void> _emitExams() async {
    if (_disposed || _userId == null) return;
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        local_id AS id,
        title,
        exam_datetime,
        category_local_id AS category_id,
        difficulty,
        reminder_offsets,
        is_completed,
        grade,
        target_grade,
        credits
      FROM exams_local
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY exam_datetime ASC
      ''',
      [_requireUserId()],
    );
    if (!_examsController.isClosed) {
      _examsController.add(
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    }
  }

  Future<void> _emitMilestones() async {
    if (_disposed || _userId == null) return;
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        local_id AS id,
        exam_local_id AS exam_id,
        name,
        is_completed
      FROM milestones_local
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY created_at_ms ASC
      ''',
      [_requireUserId()],
    );
    if (!_milestonesController.isClosed) {
      _milestonesController.add(
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    }
  }

  Future<void> _emitStudySessions() async {
    if (_disposed || _userId == null) return;
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        local_id AS id,
        exam_local_id AS exam_id,
        start_time,
        duration_minutes
      FROM study_sessions_local
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY start_time DESC
      ''',
      [_requireUserId()],
    );
    if (!_studySessionsController.isClosed) {
      _studySessionsController.add(
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> getActiveExamRows() async {
    if (_disposed || _userId == null) return const [];
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        local_id AS id,
        title,
        exam_datetime,
        reminder_offsets,
        is_completed,
        grade,
        target_grade,
        credits
      FROM exams_local
      WHERE user_id = ? AND is_deleted = 0
      ORDER BY exam_datetime ASC
      ''',
      [_requireUserId()],
    );
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _requireUserId() {
    final uid = _userId;
    if (uid == null) {
      throw StateError('ManualSyncRepository used before initialize()');
    }
    return uid;
  }

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

  String _serializeReminderOffsets(Set<int> offsets) {
    final sanitized =
        offsets.where((e) => e > 0 && e <= 60 * 24 * 30).toSet().toList()
          ..sort();
    if (sanitized.isEmpty) return '60';
    return sanitized.join(',');
  }

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, 'exam_tracker_offline.db');
    _db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories_local (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id INTEGER,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            pending_op TEXT NOT NULL DEFAULT 'none',
            updated_at_ms INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL
          );
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_categories_remote_user '
          'ON categories_local(remote_id, user_id);',
        );
        await db.execute(
          'CREATE INDEX idx_categories_user '
          'ON categories_local(user_id);',
        );

        await db.execute('''
          CREATE TABLE exams_local (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id INTEGER,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            exam_datetime TEXT NOT NULL,
            category_local_id INTEGER,
            difficulty TEXT NOT NULL,
            reminder_offsets TEXT NOT NULL DEFAULT '60',
            grade TEXT,
            target_grade TEXT,
            credits REAL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            pending_op TEXT NOT NULL DEFAULT 'none',
            updated_at_ms INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL
          );
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_exams_remote_user '
          'ON exams_local(remote_id, user_id);',
        );
        await db.execute(
          'CREATE INDEX idx_exams_user '
          'ON exams_local(user_id);',
        );

        await db.execute('''
          CREATE TABLE milestones_local (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id INTEGER,
            user_id TEXT NOT NULL,
            exam_local_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            pending_op TEXT NOT NULL DEFAULT 'none',
            updated_at_ms INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL
          );
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_milestones_remote_user '
          'ON milestones_local(remote_id, user_id);',
        );
        await db.execute(
          'CREATE INDEX idx_milestones_exam '
          'ON milestones_local(exam_local_id);',
        );

        await db.execute('''
          CREATE TABLE study_sessions_local (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id INTEGER,
            user_id TEXT NOT NULL,
            exam_local_id INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            pending_op TEXT NOT NULL DEFAULT 'none',
            updated_at_ms INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL
          );
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_study_sessions_remote_user '
          'ON study_sessions_local(remote_id, user_id);',
        );
        await db.execute(
          'CREATE INDEX idx_study_sessions_exam '
          'ON study_sessions_local(exam_local_id);',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE exams_local ADD COLUMN reminder_offsets TEXT NOT NULL DEFAULT '60';",
          );
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE exams_local ADD COLUMN grade TEXT;");
          await db.execute(
            "ALTER TABLE exams_local ADD COLUMN target_grade TEXT;",
          );
          await db.execute("ALTER TABLE exams_local ADD COLUMN credits REAL;");

          await db.execute('''
            CREATE TABLE milestones_local (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              remote_id INTEGER,
              user_id TEXT NOT NULL,
              exam_local_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              is_completed INTEGER NOT NULL DEFAULT 0,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              pending_op TEXT NOT NULL DEFAULT 'none',
              updated_at_ms INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL
            );
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX idx_milestones_remote_user '
            'ON milestones_local(remote_id, user_id);',
          );
          await db.execute(
            'CREATE INDEX idx_milestones_exam '
            'ON milestones_local(exam_local_id);',
          );

          await db.execute('''
            CREATE TABLE study_sessions_local (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              remote_id INTEGER,
              user_id TEXT NOT NULL,
              exam_local_id INTEGER NOT NULL,
              start_time TEXT NOT NULL,
              duration_minutes INTEGER NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              pending_op TEXT NOT NULL DEFAULT 'none',
              updated_at_ms INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL
            );
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX idx_study_sessions_remote_user '
            'ON study_sessions_local(remote_id, user_id);',
          );
          await db.execute(
            'CREATE INDEX idx_study_sessions_exam '
            'ON study_sessions_local(exam_local_id);',
          );
        }
      },
    );
    return _db!;
  }
}
