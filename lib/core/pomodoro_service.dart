import 'dart:async';
import 'package:flutter/material.dart';
import 'manual_sync_repository.dart';

class PomodoroService {
  factory PomodoroService({ManualSyncRepository? repo}) {
    _instance ??= PomodoroService._internal(repo: repo ?? ManualSyncRepository.instance);
    return _instance!;
  }

  PomodoroService._internal({required this.repo});

  static PomodoroService? _instance;
  static PomodoroService get instance {
    if (_instance == null) {
      throw StateError('PomodoroService not initialized.');
    }
    return _instance!;
  }

  final ManualSyncRepository repo;

  static const int defaultTime = 25 * 60;
  
  final ValueNotifier<int> totalSeconds = ValueNotifier<int>(defaultTime);
  final ValueNotifier<int> secondsRemaining = ValueNotifier<int>(defaultTime);
  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<int?> selectedExamId = ValueNotifier<int?>(null);
  
  Timer? _timer;
  DateTime? _sessionStartTime;
  int _focusedSecondsSoFar = 0;

  void setDuration(int minutes) {
    if (isRunning.value) return;
    totalSeconds.value = minutes * 60;
    secondsRemaining.value = totalSeconds.value;
  }

  void toggleTimer() {
    debugPrint("PomodoroService: toggleTimer (isRunning=${isRunning.value})");
    if (isRunning.value) {
      _stopTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    debugPrint("PomodoroService: _startTimer");
    _sessionStartTime ??= DateTime.now();
    isRunning.value = true;
    _timer?.cancel(); // Safety check
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (secondsRemaining.value > 0) {
        secondsRemaining.value--;
        _focusedSecondsSoFar++;
      } else {
        debugPrint("PomodoroService: Timer reached zero");
        _onTimerComplete();
      }
    });
  }

  void _stopTimer() {
    debugPrint("PomodoroService: _stopTimer");
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
  }

  void _onTimerComplete() {
    _stopTimer();
    saveSessionAndReset();
  }

  void saveSessionAndReset() {
    debugPrint("PomodoroService: saveSessionAndReset");
    final examId = selectedExamId.value;
    // Every second of focus counts; no threshold for better responsiveness
    if (examId != null && _sessionStartTime != null && _focusedSecondsSoFar > 0) {
      final durationMins = (_focusedSecondsSoFar / 60).ceil(); // Round up to nearest minute
      debugPrint("PomodoroService: Saving session ($durationMins mins)");
      repo.addStudySession(examId, _sessionStartTime!, durationMins);
    }
    
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
    secondsRemaining.value = totalSeconds.value;
    _sessionStartTime = null;
    _focusedSecondsSoFar = 0;
  }

  void resetTimer() {
    debugPrint("PomodoroService: resetTimer (Manual)");
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
    secondsRemaining.value = totalSeconds.value;
    _sessionStartTime = null;
    _focusedSecondsSoFar = 0;
  }

  void resetEarly() {
    saveSessionAndReset();
  }

  void selectExam(int? examId) {
    if (isRunning.value) return; // Prevent changing exam while timer is active
    selectedExamId.value = examId;
  }
}
