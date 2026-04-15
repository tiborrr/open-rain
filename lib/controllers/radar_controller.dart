import 'dart:async';
import 'package:flutter/material.dart';
import '../models/radar_frame.dart';

class RadarController extends ChangeNotifier {
  List<RadarFrame> _frames = [];
  int _currentIndex = 0;
  Timer? _timer;

  List<RadarFrame> get frames => _frames;
  int get currentIndex => _currentIndex;
  RadarFrame? get currentFrame => _frames.isEmpty ? null : _frames[_currentIndex];
  bool get isPlaying => _timer != null;

  void setFrames(List<RadarFrame> newFrames, {DateTime? initialTime}) {
    _frames = newFrames;
    if (initialTime != null) {
      seekTo(initialTime);
    } else {
      _currentIndex = 0;
    }
    notifyListeners();
  }

  void play() {
    if (_frames.isEmpty) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentIndex = (_currentIndex + 1) % _frames.length;
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void togglePlay() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seekTo(DateTime target) {
    if (_frames.isEmpty) return;
    
    int closestIndex = 0;
    int minDiff = 86400000; // 24 hours in ms
    
    for (int i = 0; i < _frames.length; i++) {
        final diff = _frames[i].time.difference(target).inMilliseconds.abs();
        if (diff < minDiff) {
           minDiff = diff;
           closestIndex = i;
        }
    }
    
    if (_currentIndex != closestIndex) {
      _currentIndex = closestIndex;
      pause();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
