import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/app_state.dart';
import '../core/manual_sync_repository.dart';
import 'exam_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final ManualSyncRepository _repo = ManualSyncRepository.instance;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<Map<String, dynamic>> _getExamsForDay(DateTime day, List<Map<String, dynamic>> allExams) {
    return allExams.where((exam) {
      final examDateStr = exam['exam_datetime'] as String?;
      if (examDateStr == null) return false;
      final examDate = DateTime.tryParse(examDateStr)?.toLocal();
      if (examDate == null) return false;
      
      return examDate.year == day.year && 
             examDate.month == day.month && 
             examDate.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.examsStream,
        builder: (context, snapshot) {
          final allExams = snapshot.data ?? [];
          
          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                eventLoader: (day) => _getExamsForDay(day, allExams),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: kPrimaryBlue.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: kPrimaryBlue,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                  markersMaxCount: 1,
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
                child: _buildExamList(_getExamsForDay(_selectedDay ?? _focusedDay, allExams)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExamList(List<Map<String, dynamic>> dayExams) {
    if (dayExams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              "No exams scheduled for this day",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: dayExams.length,
      itemBuilder: (context, index) {
        final exam = dayExams[index];
        final date = DateTime.tryParse(exam['exam_datetime'] ?? '')?.toLocal();
        final isCompleted = (exam['is_completed'] as num?)?.toInt() == 1;

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green.withValues(alpha: 0.1) : kPrimaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCompleted ? Icons.check_circle_outline : Icons.alarm,
                color: isCompleted ? Colors.green : kPrimaryBlue,
              ),
            ),
            title: Text(
              exam['title'],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(date != null ? '${date.hour}:${date.minute.toString().padLeft(2, '0')}' : ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExamDetailScreen(
                    examId: exam['id'],
                    examTitle: exam['title'],
                    repo: _repo,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
