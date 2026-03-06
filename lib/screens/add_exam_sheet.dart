import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_state.dart';
import '../core/models.dart';

enum ReminderUnit { minutes, hours, days }

class AddExamSheet extends StatefulWidget {
  const AddExamSheet({
    super.key,
    required this.categories,
    this.initialExam,
    this.titleText = 'Add Exam',
    this.saveButtonLabel = 'Save',
  });

  final List<Map<String, dynamic>> categories;
  final ExamItem? initialExam;
  final String titleText;
  final String saveButtonLabel;

  @override
  State<AddExamSheet> createState() => _AddExamSheetState();
}

class _AddExamSheetState extends State<AddExamSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _customReminderController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int? _categoryId;
  String _difficulty = 'Medium';
  Set<int> _reminderOffsetsMinutes = <int>{60};
  Set<int> _availableReminderOptions = <int>{};
  ReminderUnit _customReminderUnit = ReminderUnit.hours;

  @override
  void initState() {
    super.initState();
    debugPrint("AddExamSheet: initState called");
    _availableReminderOptions = Set<int>.from(reminderOptionMinutes.value);
    if (_availableReminderOptions.isEmpty) {
      _availableReminderOptions = Set<int>.from(kReminderOptionsMinutes);
    }
    
    final initial = widget.initialExam;
    if (initial != null) {
      debugPrint("AddExamSheet: Initializing with exam: ${initial.title}");
      _titleController.text = initial.title;
      _selectedDate = DateTime(
        initial.examDateTime.year,
        initial.examDateTime.month,
        initial.examDateTime.day,
      );
      _selectedTime = TimeOfDay.fromDateTime(initial.examDateTime);
      _categoryId = initial.categoryId;
      _difficulty = _difficultyMeta(initial.difficulty).label;
      _reminderOffsetsMinutes = Set<int>.from(initial.reminderOffsetsMinutes);
    } else {
      _reminderOffsetsMinutes = Set<int>.from(reminderOffsetsMinutes.value);
    }
    _availableReminderOptions.addAll(_reminderOffsetsMinutes);
    
    final currentId = _categoryId;
    final hasCurrentCategory = widget.categories.any(
      (c) => (c['id'] as num?)?.toInt() == currentId,
    );
    if (!hasCurrentCategory && widget.categories.isNotEmpty) {
      final firstRow = widget.categories.first;
      final firstId = (firstRow['id'] as num?)?.toInt();
      if (firstId != null) {
        _categoryId = firstId;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customReminderController.dispose();
    super.dispose();
  }

  void _addCustomReminder() {
    final minutes = _customMinutesFromInput();
    if (minutes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Enter a valid reminder value'),
        ),
      );
      return;
    }
    if (minutes > 60 * 24 * 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Custom reminder can be up to 30 days'),
        ),
      );
      return;
    }
    setState(() {
      _availableReminderOptions.add(minutes);
      _reminderOffsetsMinutes.add(minutes);
    });
    _customReminderController.clear();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_selectedDate != null && !_selectedDate!.isBefore(today))
        ? _selectedDate!
        : now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  DateTime? _combinedDateTime() {
    if (_selectedDate == null || _selectedTime == null) return null;
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final examDateTime = _combinedDateTime();
    if (examDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Please select date and time'),
        ),
      );
      return;
    }

    if (examDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Exam date and time cannot be in the past.'),
        ),
      );
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Please add/select a category first'),
        ),
      );
      return;
    }

    final rawCustom = _customReminderController.text.trim();
    if (rawCustom.isNotEmpty) {
      final customMinutes = _customMinutesFromInput();
      if (customMinutes == null || customMinutes > 60 * 24 * 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Invalid custom reminder value'),
          ),
        );
        return;
      }
      _availableReminderOptions.add(customMinutes);
      _reminderOffsetsMinutes.add(customMinutes);
      _customReminderController.clear();
    }

    if (_reminderOffsetsMinutes.isEmpty) {
      _reminderOffsetsMinutes = <int>{60};
    }
    reminderOffsetsMinutes.value = Set<int>.from(_reminderOffsetsMinutes);
    reminderOptionMinutes.value = Set<int>.from(_availableReminderOptions);
    unawaited(persistReminderOffsets(_reminderOffsetsMinutes));
    unawaited(persistReminderOptions(_availableReminderOptions));

    Navigator.pop(
      context,
      ExamDraft(
        title: _titleController.text.trim(),
        examDateTime: examDateTime,
        categoryId: _categoryId!,
        difficulty: _difficulty,
        reminderOffsetsMinutes: Set<int>.from(_reminderOffsetsMinutes),
      ),
    );
  }

  int? _customMinutesFromInput() {
    final value = int.tryParse(_customReminderController.text.trim());
    if (value == null || value <= 0) return null;
    return switch (_customReminderUnit) {
      ReminderUnit.minutes => value,
      ReminderUnit.hours => value * 60,
      ReminderUnit.days => value * 1440,
    };
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final combined = _combinedDateTime();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, insets + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
               const SizedBox(height: 8),
               Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.titleText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Exam Name',
                  hintText: 'e.g. Physics Midterm',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Exam name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(
                        _selectedDate == null
                            ? 'Pick Date'
                            : _formatDate(_selectedDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time_rounded),
                      label: Text(
                        _selectedTime == null
                            ? 'Pick Time'
                            : _selectedTime!.format(context),
                      ),
                    ),
                  ),
                ],
              ),
              if (combined != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kPrimaryBlue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: kPrimaryBlue),
                        const SizedBox(width: 8),
                        Text(
                          'Selected: ${_formatDate(combined)} at ${_formatTime(combined)}',
                          style: const TextStyle(
                            color: kPrimaryBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                items: widget.categories.map((c) {
                  final id = (c['id'] as num).toInt();
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('${c['name']}'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 20),
              const Text(
                'Difficulty',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Easy', 'Medium', 'Hard'].map((value) {
                  final selected = _difficulty == value;
                  final meta = _difficultyMeta(value);
                  return ChoiceChip(
                    label: Text(value),
                    selected: selected,
                    selectedColor: meta.color.withValues(alpha: 0.15),
                    side: BorderSide(
                      color: selected ? meta.color : Theme.of(context).dividerColor,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? meta.color : Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setState(() => _difficulty = value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Reminder Notifications',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (_availableReminderOptions.toList()..sort()).map((
                  minutes,
                ) {
                  final selected = _reminderOffsetsMinutes.contains(minutes);
                  return FilterChip(
                    label: Text(_reminderLabel(minutes)),
                    selected: selected,
                    showCheckmark: true,
                    checkmarkColor: kPrimaryBlue,
                    selectedColor: kPrimaryBlue.withValues(alpha: 0.1),
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _reminderOffsetsMinutes.add(minutes);
                        } else {
                          _reminderOffsetsMinutes.remove(minutes);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customReminderController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Custom Reminder',
                        hintText: 'Value',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReminderUnit>(
                        value: _customReminderUnit,
                        items: const [
                          DropdownMenuItem(value: ReminderUnit.minutes, child: Text('Min')),
                          DropdownMenuItem(value: ReminderUnit.hours, child: Text('Hrs')),
                          DropdownMenuItem(value: ReminderUnit.days, child: Text('Days')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _customReminderUnit = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _addCustomReminder,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: kPrimaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _save,
                  child: Text(
                    widget.saveButtonLabel,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = months[dateTime.month - 1];
    final year = dateTime.year;
    return '$day $month $year';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  String _reminderLabel(int minutes) {
    if (minutes >= 1440) {
      final days = minutes ~/ 1440;
      return '$days ${days == 1 ? 'Day' : 'Days'} before';
    }
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '$hours Hr before';
    }
    return '$minutes Min before';
  }

  ({Color color, String label}) _difficultyMeta(String input) {
    final normalized = input.toLowerCase();
    if (normalized == 'easy') return (color: Colors.green, label: 'Easy');
    if (normalized == 'hard') return (color: Colors.red, label: 'Hard');
    return (color: Colors.orange, label: 'Medium');
  }
}
