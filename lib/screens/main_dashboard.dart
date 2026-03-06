import 'dart:ui';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/manual_sync_repository.dart';
import '../core/models.dart';
import 'calendar_screen.dart';
import 'exam_tracker_page.dart';
import 'pomodoro_screen.dart';
import '../core/pomodoro_service.dart';
import 'add_exam_sheet.dart'; // Add this import

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    debugPrint("MainDashboard: initState");
    // Initialize repository first as PomodoroService depends on it
    final user = Supabase.instance.client.auth.currentUser;
    final repo = ManualSyncRepository(supabase: Supabase.instance.client);
    if (user != null) {
      debugPrint("MainDashboard: Initializing repo for user ${user.id}");
      repo.initialize(user.id);
    }
    // Initialize PomodoroService
    PomodoroService();
  }

  final List<Widget> _pages = [
    const ExamTrackerPage(),
    const CalendarScreen(),
    const PomodoroScreen(),
  ];

  void _showAddExamSheet() async {
    debugPrint("MainDashboard: _showAddExamSheet called");
    final repo = ManualSyncRepository.instance;
    debugPrint("MainDashboard: Fetching categories...");
    final categories = await repo.getCategories();
    debugPrint("MainDashboard: Categories fetched: ${categories.length}");

    if (!mounted) return;

    final result = await showModalBottomSheet<ExamDraft>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => AddExamSheet(categories: categories),
    );

    if (result != null) {
      await repo.addExam(
        title: result.title,
        examDateTime: result.examDateTime,
        categoryLocalId: result.categoryId,
        difficulty: result.difficulty,
        reminderOffsetsMinutes: result.reminderOffsetsMinutes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Exam added successfully!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildGlassyNavBar(isDark),
    );
  }

  Widget _buildGlassyNavBar(bool isDark) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.48)
                    : Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildNavIcon(0, Icons.home_rounded, Icons.home_outlined),
                  _buildNavIcon(1, Icons.calendar_month_rounded, Icons.calendar_month_outlined),
                  _buildNavIcon(2, Icons.timer_rounded, Icons.timer_outlined),
                  
                  // Right: Integrated Add Button
                  GestureDetector(
                    onTap: _showAddExamSheet,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kPrimaryBlue, kPrimaryBlue.withValues(alpha: 0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryBlue.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
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

  Widget _buildNavIcon(int index, IconData selectedIcon, IconData unselectedIcon) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : unselectedIcon,
              color: isSelected ? kPrimaryBlue : Colors.grey.withValues(alpha: 0.7),
              size: 28,
            ),
            const SizedBox(height: 4),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: isSelected ? kPrimaryBlue : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
