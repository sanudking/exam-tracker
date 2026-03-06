import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import '../core/device_settings_service.dart';
import '../core/manual_sync_repository.dart';
import '../core/notification_service.dart';
import 'auth_screens.dart';
import 'add_exam_sheet.dart';
import 'exam_detail_screen.dart';
import '../core/models.dart';

class ExamTrackerPage extends StatefulWidget {
  const ExamTrackerPage({super.key});

  @override
  State<ExamTrackerPage> createState() => _ExamTrackerPageState();
}

class _ExamTrackerPageState extends State<ExamTrackerPage> {
  int? _selectedCategoryId;
  final Set<String> _hiddenExamKeys = <String>{};
  final Set<String> _forceDoneExamKeys = <String>{};
  StreamSubscription? _examsSub;
  late final ManualSyncRepository _repo;
  bool _repoReady = false;
  bool _repoInitializing = false;
  String? _repoInitError;

  String? _activeUserId() => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _repo = ManualSyncRepository(supabase: supabase);
    unawaited(_initializeRepository());
  }

  @override
  void dispose() {
    _examsSub?.cancel();
    unawaited(_repo.dispose());
    super.dispose();
  }

  Future<void> _initializeRepository() async {
    if (_repoReady || _repoInitializing) return;
    final uid = _activeUserId();
    if (uid == null) return;
    _repoInitializing = true;
    try {
      await _repo.initialize(uid);
      if (!mounted) return;
      setState(() {
        _repoReady = true;
        _repoInitError = null;
      });
      _examsSub = _repo.examsStream.listen((rows) {
        final allExams = rows.map((r) => ExamItem.fromMap(r)).toList();
        _syncAllWidgets(allExams);
      });

      // Notifications should never block page readiness.
      unawaited(NotificationService.instance.initialize().catchError((_) {}));
    } catch (error) {
      if (!mounted) return;
      setState(() => _repoInitError = '$error');
    } finally {
      _repoInitializing = false;
    }
  }

  Stream<List<Map<String, dynamic>>> _categoriesStream() {
    return _repo.categoriesStream;
  }

  Stream<List<Map<String, dynamic>>> _examsStream() {
    return _repo.examsStream;
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final inserted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. Mid, End, Quiz',
                labelText: 'Category name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Category name is required';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final uid = _activeUserId();
                if (uid == null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      duration: Duration(seconds: 3),
                      content: Text('Please login again.'),
                    ),
                  );
                  return;
                }
                try {
                  await _repo.addCategory(controller.text.trim());
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (inserted == true && mounted) setState(() {});
  }

  // Note: Local _showAddExamSheet removed; now handled by MainDashboard globally.

  Future<void> _refreshData() async {
    await _repo.syncNow();
  }

  Future<void> _sendTestNotification() async {
    final ok = await NotificationService.instance.sendTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          ok
              ? 'Test notification sent.'
              : 'Notifications are disabled. Enable permission and try again.',
        ),
      ),
    );
  }

  _SyncBadgeMeta _syncMeta(RepoSyncStatus status, {required bool isDark}) {
    if (status.isSyncing) {
      return _SyncBadgeMeta(
        label: 'Syncing...',
        icon: Icons.sync_rounded,
        bgColor: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE5EEFF),
        textColor: isDark ? const Color(0xFFDBEAFE) : const Color(0xFF1D4ED8),
      );
    }
    if (status.pendingOps > 0) {
      return _SyncBadgeMeta(
        label: 'Pending ${status.pendingOps}',
        icon: Icons.schedule_rounded,
        bgColor: isDark ? const Color(0xFF3F2E14) : const Color(0xFFFFF4DE),
        textColor: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
      );
    }
    if (status.lastErrorMessage != null) {
      return _SyncBadgeMeta(
        label: 'Sync issue',
        icon: Icons.error_outline_rounded,
        bgColor: isDark ? const Color(0xFF4C1D1D) : const Color(0xFFFDE8E8),
        textColor: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
      );
    }
    return _SyncBadgeMeta(
      label: 'Synced',
      icon: Icons.cloud_done_rounded,
      bgColor: isDark ? const Color(0xFF123026) : const Color(0xFFE8F8EF),
      textColor: isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534),
    );
  }

  Future<void> _markComplete(ExamItem exam) async {
    final key = '${exam.raw['id']}';
    if (_activeUserId() == null) return;
    setState(() => _forceDoneExamKeys.add(key));

    try {
      final ok = await _repo.markExamComplete(exam.id);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Could not mark this exam as done.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Marked as complete'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Marked locally. Cloud sync pending.'),
        ),
      );
    }
  }

  Future<void> _showDeleteCategoryActionSheet(
    Map<String, dynamic> category,
  ) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('${category['name']}'),
        message: const Text('Choose an action'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteCategory(category);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    if (_activeUserId() == null) return;
    try {
      final localCategoryId = (category['id'] as num).toInt();
      await _repo.deleteCategory(localCategoryId);
      if (!mounted) return;
      if (_selectedCategoryId == localCategoryId) {
        setState(() => _selectedCategoryId = null);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted "${category['name']}"')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Category delete queued for sync.'),
        ),
      );
    }
  }

  Future<void> _showEditExamSheet(
    ExamItem exam,
    List<Map<String, dynamic>> categories,
  ) async {
    debugPrint("ExamTrackerPage: _showEditExamSheet for ${exam.title}");
    final updated = await showModalBottomSheet<ExamDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddExamSheet(
        categories: categories,
        initialExam: exam,
        titleText: 'Edit Exam',
        saveButtonLabel: 'Update',
      ),
    );

    if (updated == null) return;
    final ok = await _repo.updateExam(
      localExamId: exam.id,
      title: updated.title,
      examDateTime: updated.examDateTime,
      categoryLocalId: updated.categoryId,
      difficulty: updated.difficulty,
      reminderOffsetsMinutes: updated.reminderOffsetsMinutes,
    );
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Unable to update exam.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 3),
        content: Text('Exam updated'),
      ),
    );
  }

  Future<void> _showExamActionSheet(
    ExamItem exam,
    List<Map<String, dynamic>> categories,
  ) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(exam.title),
        message: const Text('Choose an action'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showEditExamSheet(exam, categories);
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteWithUndo(exam);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _deleteWithUndo(ExamItem exam) async {
    final key = '${exam.raw['id']}';
    if (_activeUserId() == null) return;
    setState(() {
      _hiddenExamKeys.add(key);
      _forceDoneExamKeys.remove(key);
    });

    try {
      await _repo.deleteExam(exam.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Deleted "${exam.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted) setState(() => _hiddenExamKeys.remove(key));
              unawaited(_repo.undoDeleteExam(exam.id));
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _hiddenExamKeys.remove(key));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Delete queued for sync.'),
        ),
      );
    }
  }

  Future<void> _addToHomeWidget(ExamItem exam) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Home-screen widget pinning is on Android only.'),
        ),
      );
      return;
    }

    final existingWidgetIds = (await _getPinnedExamWidgetIds()).toSet();
    final canPin = await HomeWidget.isRequestPinWidgetSupported() ?? false;
    int? targetWidgetId;

    if (canPin) {
      await HomeWidget.requestPinWidget(
        androidName: 'ExamTrackerWidgetProvider',
      );
      targetWidgetId = await _waitForNewPinnedWidgetId(existingWidgetIds);
    }

    // If no pin result was captured and there were no prior widgets, try to
    // pick the first one now available (launcher-dependent timing).
    if (targetWidgetId == null && existingWidgetIds.isEmpty) {
      final after = await _getPinnedExamWidgetIds();
      if (after.isNotEmpty) {
        targetWidgetId = after.last;
      }
    }

    if (targetWidgetId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'No new widget was added. Add/pin a widget first, then try again.',
          ),
        ),
      );
      return;
    }

    await _saveExamDataForWidgetId(
      widgetId: targetWidgetId,
      title: exam.title,
      date:
          '${_formatDate(exam.examDateTime)} at ${_formatTime(exam.examDateTime)}',
      epochMs: exam.examDateTime.millisecondsSinceEpoch,
      durationHours: examDurationHours.value,
      isCompleted: exam.isCompleted,
      dbId: exam.id,
    );
    await HomeWidget.updateWidget(androidName: 'ExamTrackerWidgetProvider');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('Widget linked to "${exam.title}" successfully.'),
      ),
    );
  }

  Future<List<int>> _getPinnedExamWidgetIds() async {
    final widgets = await HomeWidget.getInstalledWidgets();
    final ids =
        widgets
            .where(
              (w) => (w.androidClassName ?? '').contains(
                'ExamTrackerWidgetProvider',
              ),
            )
            .map((w) => w.androidWidgetId)
            .whereType<int>()
            .toList()
          ..sort();
    return ids;
  }

  Future<int?> _waitForNewPinnedWidgetId(Set<int> before) async {
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      final current = await _getPinnedExamWidgetIds();
      final delta = current.where((id) => !before.contains(id)).toList();
      if (delta.isNotEmpty) {
        delta.sort();
        return delta.last;
      }
    }
    return null;
  }

  Future<void> _saveExamDataForWidgetId({
    required int widgetId,
    required String title,
    required String date,
    required int epochMs,
    required int durationHours,
    required bool isCompleted,
    required int dbId,
  }) async {
    await Future.wait([
      HomeWidget.saveWidgetData<String>('widget_exam_title_$widgetId', title),
      HomeWidget.saveWidgetData<String>('widget_exam_date_$widgetId', date),
      HomeWidget.saveWidgetData<int>('widget_exam_epoch_ms_$widgetId', epochMs),
      HomeWidget.saveWidgetData<int>(
        'widget_exam_duration_hrs_$widgetId',
        durationHours,
      ),
      HomeWidget.saveWidgetData<bool>(
        'widget_exam_completed_$widgetId',
        isCompleted,
      ),
      HomeWidget.saveWidgetData<int>('widget_exam_db_id_$widgetId', dbId),
    ]);
  }

  Future<void> _syncAllWidgets(List<ExamItem> allExams) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final widgetIds = await _getPinnedExamWidgetIds();
      if (widgetIds.isEmpty) return;

      bool madeChanges = false;
      for (final id in widgetIds) {
        final dbId = await HomeWidget.getWidgetData<int>(
          'widget_exam_db_id_$id',
        );
        if (dbId != null) {
          final matchingExam = allExams.where((e) => e.id == dbId).firstOrNull;
          if (matchingExam != null) {
            await _saveExamDataForWidgetId(
              widgetId: id,
              title: matchingExam.title,
              date:
                  '${_formatDate(matchingExam.examDateTime)} at ${_formatTime(matchingExam.examDateTime)}',
              epochMs: matchingExam.examDateTime.millisecondsSinceEpoch,
              durationHours: examDurationHours.value,
              isCompleted: matchingExam.isCompleted,
              dbId: dbId,
            );
            madeChanges = true;
          }
        }
      }

      if (madeChanges) {
        await HomeWidget.updateWidget(androidName: 'ExamTrackerWidgetProvider');
      }
    } catch (_) {
      // Ignore background sync errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarTitleColor = isDark
        ? const Color(0xFFBFDBFE)
        : const Color(0xFF2A4A78);
    final appBarIconColor = isDark
        ? const Color(0xFFDCE7FF)
        : const Color(0xFF2A4A78);

    return ValueListenableBuilder<int>(
      valueListenable: examDurationHours,
      builder: (context, durationHours, _) {
        if (_activeUserId() == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('ExamTracker')),
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
                    (_) => false,
                  );
                },
                child: const Text('Login Required'),
              ),
            ),
          );
        }
        if (!_repoReady) {
          _initializeRepository();
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Loading your exams...',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (_repoInitError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _repoInitError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _categoriesStream(),
          builder: (context, categorySnapshot) {
            if (categorySnapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('ExamTracker')),
                body: _SupabaseErrorView(
                  title: 'Categories not available',
                  detail: '${categorySnapshot.error}',
                ),
              );
            }

            final categories = categorySnapshot.data ?? const [];
            final categoryNameById = <int, String>{
              for (final c in categories)
                (c['id'] as num).toInt(): (c['name'] as String? ?? 'Unknown'),
            };
            final studentName =
                (supabase.auth.currentUser?.userMetadata?['name'] as String?) ??
                'Student Name';
            final studentEmail =
                supabase.auth.currentUser?.email ?? 'no-email@exammate.app';

            return StreamBuilder<RepoSyncStatus>(
              stream: _repo.syncStatusStream,
              initialData: _repo.latestSyncStatus,
              builder: (context, syncSnapshot) {
                final syncStatus =
                    syncSnapshot.data ?? const RepoSyncStatus.initial();
                final syncMeta = _syncMeta(syncStatus, isDark: isDark);

                return Scaffold(
                  appBar: AppBar(
                    toolbarHeight: 78,
                    title: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ExamTracker',
                          style: TextStyle(
                            color: appBarTitleColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: syncMeta.bgColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                syncMeta.icon,
                                size: 13,
                                color: syncMeta.textColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                syncMeta.label,
                                style: TextStyle(
                                  color: syncMeta.textColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    iconTheme: IconThemeData(color: appBarIconColor),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    flexibleSpace: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
                              : const [Color(0xFFEFF4FF), Color(0xFFF9FBFF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.24 : 0.07,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      ValueListenableBuilder<bool>(
                        valueListenable: showTestNotificationButton,
                        builder: (context, showButton, _) {
                          if (!showButton) return const SizedBox.shrink();
                          return IconButton(
                            tooltip: 'Test Notification',
                            onPressed: _sendTestNotification,
                            icon: Icon(
                              Icons.notifications_active_outlined,
                              color: appBarIconColor,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Profile & Settings',
                        onPressed: () async {
                          final result = await Navigator.of(context)
                              .push<String>(
                                MaterialPageRoute(
                                  builder: (_) => ProfilePage(
                                    studentName: studentName,
                                    studentEmail: studentEmail,
                                  ),
                                ),
                              );
                          if (!mounted) return;
                          if (result == 'name-updated') {
                            setState(() {});
                          } else if (result == 'logout') {
                            Navigator.of(this.context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const OnboardingScreen(),
                              ),
                              (_) => false,
                            );
                          }
                        },
                        icon: Icon(
                          Icons.account_circle_outlined,
                          color: appBarIconColor,
                        ),
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 54,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected: _selectedCategoryId == null,
                                onTap: () =>
                                    setState(() => _selectedCategoryId = null),
                              ),
                              ...categories.map((category) {
                                final id = (category['id'] as num).toInt();
                                return _FilterChip(
                                  label: '${category['name']}',
                                  selected: _selectedCategoryId == id,
                                  onTap: () =>
                                      setState(() => _selectedCategoryId = id),
                                  onLongPress: () =>
                                      _showDeleteCategoryActionSheet(category),
                                );
                              }),
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: OutlinedButton(
                                  onPressed: _showAddCategoryDialog,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(42, 38),
                                    maximumSize: const Size(42, 38),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Icon(Icons.add),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<int>(
                          stream: Stream<int>.periodic(
                            const Duration(seconds: 1),
                            (x) => x,
                          ),
                          initialData: 0,
                          builder: (context, tickSnapshot) {
                            final now = DateTime.now();
                            return StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _examsStream(),
                              builder: (context, examSnapshot) {
                                if (examSnapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    !examSnapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (examSnapshot.hasError) {
                                  return _SupabaseErrorView(
                                    title: 'Exams not available',
                                    detail: '${examSnapshot.error}',
                                  );
                                }

                                final rows = examSnapshot.data ?? const [];
                                final exams = rows
                                    .map(ExamItem.fromMap)
                                    .toList();

                                final filtered = exams.where((exam) {
                                  if (_hiddenExamKeys.contains(
                                    '${exam.raw['id']}',
                                  )) {
                                    return false;
                                  }
                                  if (_selectedCategoryId == null) return true;
                                  return exam.categoryId == _selectedCategoryId;
                                }).toList();

                                filtered.sort((a, b) {
                                  final aPhase = _phaseForExam(
                                    exam: a,
                                    now: now,
                                    durationHours: durationHours,
                                    forceDone: _forceDoneExamKeys.contains(
                                      '${a.raw['id']}',
                                    ),
                                  );
                                  final bPhase = _phaseForExam(
                                    exam: b,
                                    now: now,
                                    durationHours: durationHours,
                                    forceDone: _forceDoneExamKeys.contains(
                                      '${b.raw['id']}',
                                    ),
                                  );
                                  final pA = _phasePriority(aPhase);
                                  final pB = _phasePriority(bPhase);
                                  if (pA != pB) return pA.compareTo(pB);
                                  return a.examDateTime.compareTo(
                                    b.examDateTime,
                                  );
                                });

                                if (filtered.isEmpty) {
                                  return RefreshIndicator(
                                    onRefresh: _refreshData,
                                    child: ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        const SizedBox(height: 160),
                                        Center(
                                          child: Text(
                                            'No exams found.\nPull to refresh or tap + to add your first exam.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.blueGrey.shade500,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final live = <ExamItem>[];
                                final upcoming = <ExamItem>[];
                                final pastAndDone = <ExamItem>[];

                                for (final exam in filtered) {
                                  final phase = _phaseForExam(
                                    exam: exam,
                                    now: now,
                                    durationHours: durationHours,
                                    forceDone: _forceDoneExamKeys.contains(
                                      '${exam.raw['id']}',
                                    ),
                                  );
                                  switch (phase) {
                                    case _ExamPhase.live:
                                      live.add(exam);
                                      break;
                                    case _ExamPhase.future:
                                      upcoming.add(exam);
                                      break;
                                    case _ExamPhase.past:
                                    case _ExamPhase.done:
                                      pastAndDone.add(exam);
                                      break;
                                  }
                                }

                                final widgets = <Widget>[];

                                void addSection(
                                  String title,
                                  List<ExamItem> list,
                                ) {
                                  if (list.isEmpty) return;
                                  if (widgets.isNotEmpty) {
                                    widgets.add(const SizedBox(height: 16));
                                  }
                                  widgets.add(_SectionHeader(title: title));
                                  widgets.add(const SizedBox(height: 10));
                                  for (final exam in list) {
                                    final phase = _phaseForExam(
                                      exam: exam,
                                      now: now,
                                      durationHours: durationHours,
                                      forceDone: _forceDoneExamKeys.contains(
                                        '${exam.raw['id']}',
                                      ),
                                    );
                                    final categoryName = exam.categoryId == null
                                        ? 'Uncategorized'
                                        : (categoryNameById[exam.categoryId!] ??
                                              'Uncategorized');
                                    widgets.add(
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _ExamCard(
                                          exam: exam,
                                          now: now,
                                          phase: phase,
                                          categoryName: categoryName,
                                          onTap: () {
                                            if (phase == _ExamPhase.done ||
                                                phase == _ExamPhase.past) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        "Exam is over. Milestones are no longer editable.",
                                                      ),
                                                      duration: Duration(
                                                        seconds: 2,
                                                      ),
                                                    ),
                                                  );
                                              return;
                                            }
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ExamDetailScreen(
                                                      examId: exam.id,
                                                      examTitle: exam.title,
                                                      repo: _repo,
                                                    ),
                                              ),
                                            );
                                          },
                                          onMarkComplete:
                                              (phase == _ExamPhase.live ||
                                                  phase == _ExamPhase.past)
                                              ? () => _markComplete(exam)
                                              : null,
                                          onLongPress: () =>
                                              _showExamActionSheet(
                                                exam,
                                                categories,
                                              ),
                                          onAddToHomeWidget: () =>
                                              _addToHomeWidget(exam),
                                        ),
                                      ),
                                    );
                                  }
                                }

                                addSection('Live Now', live);
                                addSection('Upcoming', upcoming);
                                addSection('Past / Done', pastAndDone);

                                return ListView.builder(
                                  padding: const EdgeInsets.only(
                                    bottom: 160,
                                    left: 20,
                                    right: 20,
                                    top: 8,
                                  ),
                                  itemCount: widgets.length,
                                  itemBuilder: (context, index) =>
                                      widgets[index],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({
    required this.exam,
    required this.now,
    required this.phase,
    required this.categoryName,
    required this.onTap,
    required this.onLongPress,
    required this.onMarkComplete,
    required this.onAddToHomeWidget,
  });

  final ExamItem exam;
  final DateTime now;
  final _ExamPhase phase;
  final String categoryName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMarkComplete;
  final VoidCallback onAddToHomeWidget;

  @override
  Widget build(BuildContext context) {
    final isDone = phase == _ExamPhase.done;
    final stripColor = _difficultyMeta(exam.difficulty).color;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = scheme.onSurface;
    final metaColor = scheme.onSurfaceVariant;
    final day = exam.examDateTime.day.toString().padLeft(2, '0');

    Widget trailingContent;
    if (phase == _ExamPhase.live) {
      trailingContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 450),
            opacity: now.second.isEven ? 1 : 0.35,
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onMarkComplete,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(40, 36),
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Mark'),
          ),
        ],
      );
    } else if (phase == _ExamPhase.done || phase == _ExamPhase.past) {
      trailingContent = const Text(
        'Done',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      );
    } else {
      trailingContent = Text(
        _futureCountdownText(exam.examDateTime, now),
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 15.5,
          height: 1.15,
        ),
      );
    }

    final trailing = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Add to Home Screen',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed: onAddToHomeWidget,
          icon: Icon(
            Icons.add_home_work_outlined,
            size: 19,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        trailingContent,
      ],
    );

    final isFaded = phase == _ExamPhase.done || phase == _ExamPhase.past;

    return Opacity(
      opacity: isFaded ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(
              color: isDone ? scheme.surfaceContainerHighest : scheme.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  Container(width: 10, color: stripColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final rightPanelWidth = (constraints.maxWidth * 0.46)
                              .clamp(132.0, 190.0)
                              .toDouble();
                          final datePillWidth =
                              (constraints.maxWidth - rightPanelWidth - 26)
                                  .clamp(112.0, 156.0)
                                  .toDouble();

                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: datePillWidth,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stripColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            day,
                                            style: TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w900,
                                              color: textColor,
                                              height: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _monthLabel(
                                                  exam.examDateTime,
                                                ).toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: metaColor,
                                                  height: 1.1,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${exam.examDateTime.year}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: metaColor,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      exam.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatTime(exam.examDateTime),
                                      style: TextStyle(
                                        color: metaColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      categoryName,
                                      style: TextStyle(
                                        color: metaColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 1,
                                height: 112,
                                color: scheme.outlineVariant,
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: rightPanelWidth, child: trailing),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? kPrimaryBlue : scheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? kPrimaryBlue : scheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: scheme.outlineVariant.withValues(alpha: 0.9),
            thickness: 1.1,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// Note: AddExamSheet, ExamDraft, and related form utilities moved to add_exam_sheet.dart


class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.studentName,
    required this.studentEmail,
  });

  final String studentName;
  final String studentEmail;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late String _studentName = widget.studentName;
  bool _loadingSetupStatus = false;
  bool? _notificationsEnabled;
  bool? _exactAlarmEnabled;
  bool? _batteryOptimizationDisabled;

  bool get _isAndroidDevice =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackgroundNotificationStatus());
  }

  Future<void> _loadBackgroundNotificationStatus() async {
    if (!_isAndroidDevice || _loadingSetupStatus || !mounted) return;
    setState(() => _loadingSetupStatus = true);
    try {
      final setup = await NotificationService.instance.getSetupStatus();
      final batteryDisabled =
          await DeviceSettingsService.isIgnoringBatteryOptimizations();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = setup.notificationsEnabled;
        _exactAlarmEnabled = setup.exactAlarmsEnabled;
        _batteryOptimizationDisabled = batteryDisabled;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled ??= false;
        _exactAlarmEnabled ??= false;
        _batteryOptimizationDisabled ??= false;
      });
    } finally {
      if (mounted) setState(() => _loadingSetupStatus = false);
    }
  }

  Widget _statusDot(bool? enabled) {
    if (enabled == null) {
      return Icon(
        Icons.help_outline_rounded,
        color: Theme.of(context).colorScheme.outline,
      );
    }
    return Icon(
      enabled ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: enabled ? Colors.green : Colors.red,
    );
  }

  String _backgroundSetupSummary() {
    final checks = <bool?>[
      _notificationsEnabled,
      _exactAlarmEnabled,
      _batteryOptimizationDisabled,
    ];
    if (checks.any((v) => v == null)) return 'Checking device settings...';
    if (checks.every((v) => v == true)) {
      return 'Background reminders are configured.';
    }
    return 'Some settings are missing. Open each item below and enable it.';
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(text: _studentName);
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name is required';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newName = controller.text.trim();
              try {
                await supabase.auth.updateUser(
                  UserAttributes(data: {'name': newName}),
                );

                final user = supabase.auth.currentUser;
                if (user != null) {
                  try {
                    await supabase.from('profiles').upsert({
                      'id': user.id,
                      'name': newName,
                    });
                  } on PostgrestException catch (_) {}
                }

                if (!context.mounted) return;
                Navigator.pop(context, true);
              } on AuthException catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      setState(() => _studentName = controller.text.trim());
      Navigator.pop(context, 'name-updated');
    }
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pop(context, 'logout');
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openDeviceSetting(
    Future<bool> Function() action,
    String success,
    String fallback,
  ) async {
    final opened = await action();
    if (opened) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _loadBackgroundNotificationStatus();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(opened ? success : fallback)));
  }

  @override
  Widget build(BuildContext context) {
    final showAndroidPowerSettings = _isAndroidDevice;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: kPrimaryBlue.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.person,
                    color: kPrimaryBlue,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Student Profile',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _studentName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.studentEmail,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeMode,
            builder: (context, mode, child) {
              final enabled = mode == ThemeMode.dark;
              return SwitchListTile(
                value: enabled,
                onChanged: (value) {
                  final next = value ? ThemeMode.dark : ThemeMode.light;
                  appThemeMode.value = next;
                  persistThemeMode(next);
                },
                title: const Text('Dark Mode'),
                subtitle: const Text('Toggle app appearance'),
                secondary: const Icon(Icons.dark_mode_outlined),
              );
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: examDurationHours,
            builder: (context, duration, child) {
              return ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Default Exam Duration'),
                subtitle: const Text(
                  'Used to decide when LIVE becomes Past automatically',
                ),
                trailing: DropdownButton<int>(
                  value: duration,
                  items: const [1, 2, 3, 4]
                      .map(
                        (h) => DropdownMenuItem<int>(
                          value: h,
                          child: Text('$h hr'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      examDurationHours.value = value;
                      persistExamDuration(value);
                    }
                  },
                ),
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: showTestNotificationButton,
            builder: (context, showButton, child) {
              return SwitchListTile(
                value: showButton,
                onChanged: (value) {
                  showTestNotificationButton.value = value;
                  persistShowTestNotificationButton(value);
                },
                title: const Text('Show Test Notification Button'),
                subtitle: const Text(
                  'Display test-notification icon in home app bar',
                ),
                secondary: const Icon(Icons.notifications_active_outlined),
              );
            },
          ),
          if (showAndroidPowerSettings) ...[
            const Divider(height: 20),
            ListTile(
              leading: _loadingSetupStatus
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shield_moon_outlined),
              title: const Text('Background Notification Setup'),
              subtitle: Text(_backgroundSetupSummary()),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh setup status',
                onPressed: _loadBackgroundNotificationStatus,
              ),
            ),
            ListTile(
              leading: _statusDot(_notificationsEnabled),
              title: const Text('Notification Permission'),
              subtitle: const Text('Open app notification settings'),
              onTap: () => _openDeviceSetting(
                DeviceSettingsService.openNotificationSettings,
                'Opened notification settings.',
                'Could not open notification settings on this device.',
              ),
            ),
            ListTile(
              leading: _statusDot(_exactAlarmEnabled),
              title: const Text('Exact Alarm Permission'),
              subtitle: const Text('Allow exact alarm scheduling'),
              onTap: () => _openDeviceSetting(
                DeviceSettingsService.openExactAlarmSettings,
                'Opened exact alarm permission screen.',
                'Could not open exact alarm settings on this device.',
              ),
            ),
            ListTile(
              leading: _statusDot(_batteryOptimizationDisabled),
              title: const Text('Disable Battery Optimization'),
              subtitle: const Text('Prevent background reminder blocking'),
              onTap: () => _openDeviceSetting(
                DeviceSettingsService.openBatteryOptimizationSettings,
                'Opened battery optimization settings.',
                'Could not open battery optimization settings.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('Auto-start Permission'),
              subtitle: const Text(
                'OEM-specific autostart/background settings',
              ),
              onTap: () => _openDeviceSetting(
                DeviceSettingsService.openAutoStartSettings,
                'Opened auto-start/background settings.',
                'Auto-start screen not available; app settings opened instead.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('Important'),
              subtitle: Text(
                'Some phones stop background alarms if the app is swiped away from recents. '
                'Enable auto-start, disable battery optimization, and lock this app in recents.',
              ),
            ),
          ],
          const Divider(height: 20),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Change Name'),
            subtitle: const Text('Update profile name in Supabase'),
            onTap: _changeName,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'App Version $kAppVersion',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupabaseErrorView extends StatelessWidget {
  const _SupabaseErrorView({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_rounded, size: 42),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBadgeMeta {
  const _SyncBadgeMeta({
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.textColor,
  });

  final String label;
  final IconData icon;
  final Color bgColor;
  final Color textColor;
}

enum _ExamPhase { live, future, past, done }

_ExamPhase _phaseForExam({
  required ExamItem exam,
  required DateTime now,
  required int durationHours,
  bool forceDone = false,
}) {
  if (forceDone || exam.isCompleted) return _ExamPhase.done;
  if (now.isBefore(exam.examDateTime)) return _ExamPhase.future;
  final examEnd = exam.examDateTime.add(Duration(hours: durationHours));
  if (now.isBefore(examEnd) || now.isAtSameMomentAs(examEnd)) {
    return _ExamPhase.live;
  }
  return _ExamPhase.past;
}

int _phasePriority(_ExamPhase phase) {
  switch (phase) {
    case _ExamPhase.live:
      return 0;
    case _ExamPhase.future:
      return 1;
    case _ExamPhase.past:
      return 2;
    case _ExamPhase.done:
      return 3;
  }
}

String _futureCountdownText(DateTime examDate, DateTime now) {
  final remaining = examDate.difference(now);
  if (remaining.inSeconds <= 0) {
    return 'Now';
  }
  if (remaining.inHours < 24) {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    final parts = <String>[];
    if (hours > 0) parts.add('$hours Hr');
    if (minutes > 0) parts.add('$minutes Min');
    if (seconds > 0 || parts.isEmpty) parts.add('$seconds Sec');
    return '${parts.join(' ')} left';
  }
  if (remaining.inDays < 30) {
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final parts = <String>[];
    if (days > 0) parts.add('$days ${days == 1 ? 'Day' : 'Days'}');
    if (hours > 0) parts.add('$hours ${hours == 1 ? 'Hr' : 'Hrs'}');
    if (parts.isEmpty) return 'Less than 1 Hr left';
    return '${parts.join(' ')} left';
  }
  if (remaining.inDays < 365) {
    final months = remaining.inDays ~/ 30;
    final days = remaining.inDays % 30;
    final parts = <String>[];
    if (months > 0) parts.add('$months ${months == 1 ? 'Month' : 'Months'}');
    if (days > 0) parts.add('$days ${days == 1 ? 'Day' : 'Days'}');
    return '${parts.join(' ')} left';
  }
  final years = remaining.inDays ~/ 365;
  final months = (remaining.inDays % 365) ~/ 30;
  final parts = <String>[];
  if (years > 0) parts.add('$years ${years == 1 ? 'Year' : 'Years'}');
  if (months > 0) parts.add('$months ${months == 1 ? 'Month' : 'Months'}');
  return '${parts.join(' ')} left';
}


const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthLabel(DateTime dateTime) => _months[dateTime.month - 1];

String _formatDate(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = _months[dateTime.month - 1];
  final year = dateTime.year;
  return '$day $month $year';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $meridiem';
}



({Color color, String label}) _difficultyMeta(String input) {
  final normalized = input.toLowerCase();
  if (normalized == 'easy') return (color: Colors.green, label: 'Easy');
  if (normalized == 'hard') return (color: Colors.red, label: 'Hard');
  return (color: Colors.orange, label: 'Medium');
}
