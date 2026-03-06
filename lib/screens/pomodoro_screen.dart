import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/manual_sync_repository.dart';
import '../core/pomodoro_service.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  final PomodoroService _pomodoroService = PomodoroService.instance;
  final ManualSyncRepository _repo = ManualSyncRepository.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Timer', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            _buildExamSelector(),
            const SizedBox(height: 40),
            _buildTimerCircle(colorScheme),
            const SizedBox(height: 24),
            _buildDurationSelector(colorScheme),
            const SizedBox(height: 32),
            _buildControls(),
            const SizedBox(height: 64),
            _buildSessionHistorySection(colorScheme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExamSelector() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _repo.examsStream,
      builder: (context, snapshot) {
        final exams = snapshot.data ?? [];
        final activeExams = exams.where((e) => (e['is_completed'] as num?)?.toInt() == 0).toList();

        return ValueListenableBuilder<int?>(
          valueListenable: _pomodoroService.selectedExamId,
          builder: (context, selectedId, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: activeExams.any((e) => e['id'] == selectedId) ? selectedId : null,
                  hint: const Text("Select exam to focus on"),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  items: activeExams.map((exam) {
                    return DropdownMenuItem<int>(
                      value: exam['id'] as int,
                      child: Text(exam['title'] as String),
                    );
                  }).toList(),
                  onChanged: _pomodoroService.isRunning.value ? null : (id) {
                    _pomodoroService.selectExam(id);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimerCircle(ColorScheme colorScheme) {
    return ValueListenableBuilder<int>(
      valueListenable: _pomodoroService.secondsRemaining,
      builder: (context, seconds, child) {
        final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
        final remainingSecs = (seconds % 60).toString().padLeft(2, '0');
        final progress = 1.0 - (seconds / _pomodoroService.totalSeconds.value);

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 250,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 12,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: kPrimaryBlue,
                strokeCap: StrokeCap.round,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _pomodoroService.isRunning,
              builder: (context, isRunning, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$minutes:$remainingSecs',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRunning ? 'Focusing...' : 'Ready to focus?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return ValueListenableBuilder<bool>(
      valueListenable: _pomodoroService.isRunning,
      builder: (context, isRunning, child) {
        return ValueListenableBuilder<int>(
          valueListenable: _pomodoroService.secondsRemaining,
          builder: (context, seconds, child) {
            final hasStarted = seconds < _pomodoroService.totalSeconds.value;

            if (!hasStarted && !isRunning) {
              // Idle state - show big Start button
              return FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: kPrimaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  if (_pomodoroService.selectedExamId.value == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please select an exam first")),
                    );
                    return;
                  }
                  _pomodoroService.toggleTimer();
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
                label: const Text("Start Focus", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              );
            }

            // Active state (Running or Paused) - show side-by-side controls
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pause/Resume Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    backgroundColor: isRunning ? Colors.amber.shade700 : kPrimaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pomodoroService.toggleTimer(),
                  icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(isRunning ? "Pause" : "Resume"),
                ),
                const SizedBox(width: 8),
                // Reset Button
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    // Confirm reset if timer is running or has significant progress
                    _pomodoroService.resetTimer();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("Reset"),
                ),
                const SizedBox(width: 8),
                // Save & Stop Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    backgroundColor: Colors.green.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pomodoroService.saveSessionAndReset(),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDurationSelector(ColorScheme colorScheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _pomodoroService.isRunning,
      builder: (context, isRunning, child) {
        return ValueListenableBuilder<int>(
          valueListenable: _pomodoroService.totalSeconds,
          builder: (context, totalSeconds, child) {
            final currentMinutes = totalSeconds ~/ 60;
            final durations = [15, 25, 45, 60];

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: durations.map((mins) {
                final isSelected = currentMinutes == mins;
                return ChoiceChip(
                  label: Text('${mins}m'),
                  selected: isSelected,
                  onSelected: isRunning ? null : (selected) {
                    if (selected) _pomodoroService.setDuration(mins);
                  },
                  selectedColor: kPrimaryBlue.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? kPrimaryBlue : colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }


  Widget _buildSessionHistorySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Session History",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _repo.studySessionsStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allSessions = snapshot.data ?? [];
            return ValueListenableBuilder<int?>(
              valueListenable: _pomodoroService.selectedExamId,
              builder: (context, examId, child) {
                // Filter sessions: if an exam is selected, only show those.
                // Otherwise, show all (most recent first).
                final sessions = allSessions
                    .where((s) => examId == null || s['exam_id'] == examId)
                    .toList();

                // Sort by start time descending
                sessions.sort((a, b) {
                  final at = DateTime.tryParse(a['start_time'] ?? '') ?? DateTime(0);
                  final bt = DateTime.tryParse(b['start_time'] ?? '') ?? DateTime(0);
                  return bt.compareTo(at);
                });

                if (sessions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "No study sessions yet",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  );
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _repo.examsStream,
                  builder: (context, examsSnapshot) {
                    final exams = examsSnapshot.data ?? [];
                    final examNameMap = {
                      for (var e in exams) e['id'] as int: e['title'] as String
                    };

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sessions.length > 5 ? 5 : sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final sessionId = (session['id'] as num).toInt();
                        final sExamId = (session['exam_id'] as num).toInt();
                        final duration = (session['duration_minutes'] as num?)?.toInt() ?? 0;
                        final startTime = DateTime.tryParse(session['start_time'] ?? '')?.toLocal();
                        final examName = examNameMap[sExamId] ?? "Unknown Exam";

                        return Dismissible(
                          key: ValueKey('session_$sessionId'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.red.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => _repo.deleteStudySession(sessionId),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                examName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                startTime != null
                                    ? "${_formatDate(startTime)} at ${_formatTime(startTime)}"
                                    : "Unknown time",
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${duration}m",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kPrimaryBlue,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    color: Colors.red.shade300,
                                    onPressed: () => _repo.deleteStudySession(sessionId),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$hour:$minute $period";
  }
}
