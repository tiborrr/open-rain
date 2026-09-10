import 'dart:async';
import 'package:flutter/material.dart';
import '../models/radar_frame.dart';

/// Cohesive controller for radar animation playhead, playback timer, and frame synchronization.
///
/// Hides timer management, play/pause state transitions, and smooth playhead
/// latching across background frame updates.
class RadarController extends ChangeNotifier {
  RadarController({
    Duration frameDuration = const Duration(seconds: 1),
  }) : _frameDuration = frameDuration;

  final Duration _frameDuration;

  List<RadarFrame> _frames = const [];
  int _currentIndex = 0;
  Timer? _timer;

  List<RadarFrame> get frames => _frames;
  int get currentIndex => _currentIndex;
  RadarFrame? get currentFrame => _frames.isEmpty ? null : _frames[_currentIndex];
  bool get isPlaying => _timer != null;

  /// Updates the active frame timeline.
  ///
  /// Preserves the user's relative temporal position and playback status across
  /// background frame refreshes:
  /// * If already displaying frames and playing, seeks to the timestamp of the
  ///   currently active frame in [newFrames] and continues playing smoothly.
  /// * If receiving frames for the first time, anchors at [initialTime] (or the
  ///   first frame) and begins playback automatically.
  /// * If [newFrames] is empty, pauses and resets.
  void updateFrames(List<RadarFrame> newFrames, {DateTime? initialTime}) {
    if (newFrames.isEmpty) {
      pause();
      _frames = const [];
      _currentIndex = 0;
      notifyListeners();
      return;
    }

    final wasPlaying = isPlaying;
    final previousTime = currentFrame?.time;

    _frames = List.unmodifiable(newFrames);

    final targetTime = previousTime ?? initialTime;
    if (targetTime != null) {
      _currentIndex = _findClosestFrameIndex(_frames, targetTime);
    } else {
      _currentIndex = 0;
    }

    if (wasPlaying || (previousTime == null && !isPlaying)) {
      play();
    } else {
      notifyListeners();
    }
  }

  /// Sets frames explicitly, pausing before repositioning.
  void setFrames(List<RadarFrame> newFrames, {DateTime? initialTime}) {
    _frames = List.unmodifiable(newFrames);
    if (_frames.isEmpty) {
      pause();
      _currentIndex = 0;
      notifyListeners();
      return;
    }

    if (initialTime != null) {
      _currentIndex = _findClosestFrameIndex(_frames, initialTime);
    } else {
      _currentIndex = 0;
    }
    notifyListeners();
  }

  /// Starts or resumes periodic playback.
  void play() {
    if (_frames.isEmpty) return;
    _timer?.cancel();
    _timer = Timer.periodic(_frameDuration, (timer) {
      if (_frames.isEmpty) {
        pause();
        return;
      }
      _currentIndex = (_currentIndex + 1) % _frames.length;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Pauses playback and cancels any active timer.
  void pause() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Toggles between playing and paused states.
  void togglePlay() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Jumps the playhead to the frame closest in time to [target] and pauses.
  void seekTo(DateTime target) {
    if (_frames.isEmpty) return;

    final closestIndex = _findClosestFrameIndex(_frames, target);
    if (_currentIndex != closestIndex || isPlaying) {
      _currentIndex = closestIndex;
      pause();
    }
  }

  static int _findClosestFrameIndex(List<RadarFrame> frames, DateTime target) {
    var closestIndex = 0;
    var minDiff = 86400000; // 24 hours in ms

    for (var i = 0; i < frames.length; i++) {
      final diff = frames[i].time.difference(target).inMilliseconds.abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
