import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/manual_sync_repository.dart';

class ExamDetailScreen extends StatefulWidget {
  const ExamDetailScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.repo,
  });

  final int examId;
  final String examTitle;
  final ManualSyncRepository repo;

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  final TextEditingController _milestoneController = TextEditingController();

  @override
  void dispose() {
    _milestoneController.dispose();
    super.dispose();
  }

  void _addMilestone() {
    final text = _milestoneController.text.trim();
    if (text.isEmpty) return;
    widget.repo.addMilestone(widget.examId, text);
    _milestoneController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.examTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _buildMilestonesTab(),
      ),
    );
  }

  Widget _buildMilestonesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _milestoneController,
                  decoration: InputDecoration(
                    hintText: 'Add a new topic, chapter, or task...',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onSubmitted: (_) => _addMilestone(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                onPressed: _addMilestone,
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.repo.milestonesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final allMilestones = snapshot.data ?? [];
              final myMilestones = allMilestones
                  .where((m) => m['exam_id'] == widget.examId)
                  .toList();

              if (myMilestones.isEmpty) {
                return _buildEmptyMilestonesState();
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
                itemCount: myMilestones.length,
                itemBuilder: (context, index) {
                  final m = myMilestones[index];
                  final isCompleted = (m['is_completed'] as num?)?.toInt() == 1;
                  final milestoneId = (m['id'] as num).toInt();
                  final title = m['name'] as String;

                  return _MilestoneTile(
                    title: title,
                    isCompleted: isCompleted,
                    onToggle: (val) {
                      if (val != null) {
                        widget.repo.toggleMilestone(milestoneId, val);
                      }
                    },
                    onDelete: () => widget.repo.deleteMilestone(milestoneId),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyMilestonesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.checklist_rtl_rounded,
              size: 84,
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              "Break it down",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Add chapters, topics, or assignments as milestones to stay organized.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.title,
    required this.isCompleted,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final bool isCompleted;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(title),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onToggle(!isCompleted),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  Checkbox(
                    value: isCompleted,
                    onChanged: onToggle,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    activeColor: kPrimaryBlue,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isCompleted
                            ? FontWeight.w500
                            : FontWeight.w600,
                        color: isCompleted
                            ? Colors.grey
                            : colorScheme.onSurface,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
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

