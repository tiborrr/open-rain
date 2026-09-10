import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/utils/env.dart';

void main() {
  group('Env Utility Tests', () {
    test('getOptional returns null for unset keys', () {
      expect(Env.getOptional('NON_EXISTENT_KEY_XYZ_123'), isNull);
    });

    test('knmiWmsApiKey does not return empty string when unset', () {
      final key = Env.knmiWmsApiKey;
      if (key != null) {
        expect(key.trim(), isNotEmpty);
      }
    });

    test('Architecture: String.fromEnvironment is only used within lib/utils/env.dart', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final violations = <String>[];
      for (final file in dartFiles) {
        // Normalize path separators for platform consistency
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized == 'lib/utils/env.dart') continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('fromEnvironment') && !line.trim().startsWith('//')) {
            violations.add('${file.path}:${i + 1} -> $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Direct use of String.fromEnvironment bypasses empty-string guards. Use Env.optional/Env getters instead.',
      );
    });
  });
}
