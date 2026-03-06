

class ExamItem {
  ExamItem({
    required this.id,
    required this.title,
    required this.examDateTime,
    required this.categoryId,
    required this.difficulty,
    required this.reminderOffsetsMinutes,
    required this.isCompleted,
    required this.raw,
  });

  factory ExamItem.fromMap(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    final title = (row['title'] as String?) ?? 'Untitled Exam';
    final dateRaw = row['exam_datetime']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateRaw)?.toLocal() ?? DateTime.now();
    final categoryId = (row['category_id'] as num?)?.toInt();
    final difficulty = ((row['difficulty'] as String?) ?? 'Medium').trim();
    final reminderOffsets = parseReminderOffsets(
      row['reminder_offsets']?.toString(),
    );
    final isCompletedRaw = row['is_completed'];
    final isCompleted =
        isCompletedRaw == true ||
        isCompletedRaw == 1 ||
        '$isCompletedRaw'.toLowerCase() == 'true';

    return ExamItem(
      id: id,
      title: title,
      examDateTime: parsedDate,
      categoryId: categoryId,
      difficulty: difficulty,
      reminderOffsetsMinutes: reminderOffsets,
      isCompleted: isCompleted,
      raw: Map<String, dynamic>.from(row),
    );
  }

  final int id;
  final String title;
  final DateTime examDateTime;
  final int? categoryId;
  final String difficulty;
  final Set<int> reminderOffsetsMinutes;
  final bool isCompleted;
  final Map<String, dynamic> raw;
}

class ExamDraft {
  const ExamDraft({
    required this.title,
    required this.examDateTime,
    required this.categoryId,
    required this.difficulty,
    required this.reminderOffsetsMinutes,
  });

  final String title;
  final DateTime examDateTime;
  final int categoryId;
  final String difficulty;
  final Set<int> reminderOffsetsMinutes;
}

Set<int> parseReminderOffsets(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <int>{60};
  final cleaned = raw.replaceAll('{', '').replaceAll('}', '');
  if (cleaned.trim().isEmpty) return <int>{60};
  return cleaned
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
}
