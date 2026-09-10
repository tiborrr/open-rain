import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/controllers/radar_controller.dart';
import 'package:flutter_weather/models/radar_frame.dart';

void main() {
  RadarFrame makeFrame(int minutesOffset) {
    final t = DateTime.utc(2024, 6, 1, 12).add(Duration(minutes: minutesOffset));
    return RadarFrame(frameId: t.toIso8601String(), time: t);
  }

  group('RadarController', () {
    test('initial state is empty, index 0, not playing', () {
      final controller = RadarController();
      expect(controller.frames, isEmpty);
      expect(controller.currentIndex, 0);
      expect(controller.currentFrame, isNull);
      expect(controller.isPlaying, isFalse);
    });

    test('updateFrames with empty list resets and pauses', () {
      final controller = RadarController();
      controller.setFrames([makeFrame(0), makeFrame(5)]);
      controller.play();
      expect(controller.isPlaying, isTrue);

      controller.updateFrames([]);
      expect(controller.frames, isEmpty);
      expect(controller.currentIndex, 0);
      expect(controller.isPlaying, isFalse);
    });

    test('updateFrames starts playing on first non-empty set', () {
      final controller = RadarController();
      final frames = [makeFrame(0), makeFrame(5), makeFrame(10)];

      controller.updateFrames(frames, initialTime: frames[1].time);
      expect(controller.frames.length, 3);
      expect(controller.currentIndex, 1);
      expect(controller.isPlaying, isTrue);

      controller.dispose();
    });

    test('updateFrames preserves temporal position and playing state across refresh', () {
      final controller = RadarController();
      final oldFrames = [makeFrame(0), makeFrame(5), makeFrame(10), makeFrame(15)];
      controller.updateFrames(oldFrames, initialTime: oldFrames[2].time); // t=10
      expect(controller.currentIndex, 2);
      expect(controller.isPlaying, isTrue);

      // Now upstream timeline shifts forward by 5 min: [5, 10, 15, 20]
      final newFrames = [makeFrame(5), makeFrame(10), makeFrame(15), makeFrame(20)];
      controller.updateFrames(newFrames);

      // Should still point to frame with t=10, which is now at index 1
      expect(controller.currentIndex, 1);
      expect(controller.currentFrame!.time, oldFrames[2].time);
      expect(controller.isPlaying, isTrue);

      controller.dispose();
    });

    test('seekTo jumps to closest frame and pauses', () {
      final controller = RadarController();
      final frames = [makeFrame(0), makeFrame(10), makeFrame(20)];
      controller.updateFrames(frames);
      expect(controller.isPlaying, isTrue);

      // Seek to t=12 should snap to index 1 (t=10)
      controller.seekTo(DateTime.utc(2024, 6, 1, 12, 12));
      expect(controller.currentIndex, 1);
      expect(controller.isPlaying, isFalse);

      // Seek to t=18 should snap to index 2 (t=20)
      controller.seekTo(DateTime.utc(2024, 6, 1, 12, 18));
      expect(controller.currentIndex, 2);
      expect(controller.isPlaying, isFalse);

      controller.dispose();
    });

    test('togglePlay toggles between playing and paused', () {
      final controller = RadarController();
      controller.setFrames([makeFrame(0), makeFrame(5)]);
      expect(controller.isPlaying, isFalse);

      controller.togglePlay();
      expect(controller.isPlaying, isTrue);

      controller.togglePlay();
      expect(controller.isPlaying, isFalse);

      controller.dispose();
    });
  });
}
