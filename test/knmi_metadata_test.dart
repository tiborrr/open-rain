import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  group('KNMI Metadata Parsing & Windowing', () {
    test('Should parse time dimension and apply 1h/2h window correctly', () {
      final xmlString = '''
<?xml version="1.0" encoding="UTF-8"?>
<WMS_Capabilities>
  <Capability>
    <Layer>
      <Layer>
        <Name>precipitation_nowcast</Name>
        <Dimension name="time" units="ISO8601" default="2024-04-02T15:00:00Z">2024-03-26T00:00:00Z/2024-04-02T18:00:00Z/PT5M</Dimension>
      </Layer>
    </Layer>
  </Capability>
</WMS_Capabilities>
''';

      final document = XmlDocument.parse(xmlString);
      final layers = document.findAllElements('Layer');
      final nowcastLayer = layers.firstWhere(
        (l) => l.findElements('Name').any((n) => n.innerText == 'precipitation_nowcast'),
      );

      final timeDim = nowcastLayer.findElements('Dimension').firstWhere(
        (d) => d.getAttribute('name') == 'time',
      );

      final timeText = timeDim.innerText.trim();
      final defaultTimeStr = timeDim.getAttribute('default');
      final referenceTime = DateTime.parse(defaultTimeStr!);
      
      final parts = timeText.split('/');
      final fullStart = DateTime.parse(parts[0]);
      final fullEnd = DateTime.parse(parts[1]);
      final periodStr = parts[2];
      
      int intervalMinutes = 5;
      if (periodStr.contains('PT')) {
         final m = RegExp(r'(\d+)M').firstMatch(periodStr);
         if (m != null) {
            intervalMinutes = int.parse(m.group(1)!);
         }
      }

      // Apply Window Logic (1h history, 2h forecast)
      DateTime windowStart = referenceTime.subtract(const Duration(hours: 1));
      DateTime windowEnd = referenceTime.add(const Duration(hours: 2));

      if (windowStart.isBefore(fullStart)) windowStart = fullStart;
      if (windowEnd.isAfter(fullEnd)) windowEnd = fullEnd;

      final List<DateTime> times = [];
      DateTime current = windowStart;
      while (current.isBefore(windowEnd) || current.isAtSameMomentAs(windowEnd)) {
        times.add(current);
        current = current.add(Duration(minutes: intervalMinutes));
      }

      // 3 hours total = 180 mins / 5 = 36 intervals + 1 start point = 37 frames
      expect(times.length, 37); 
      expect(times.first, DateTime.parse('2024-04-02T14:00:00Z')); // default - 1h
      expect(times.last, DateTime.parse('2024-04-02T17:00:00Z'));  // default + 2h
    });

    test('Should clamp window to API bounds', () {
       // START/END range is very narrow, window should be clamped
      final xmlString = '''
<?xml version="1.0" encoding="UTF-8"?>
<WMS_Capabilities>
  <Capability>
    <Layer>
      <Layer>
        <Name>precipitation_nowcast</Name>
        <Dimension name="time" units="ISO8601" default="2024-04-02T15:00:00Z">2024-04-02T14:50:00Z/2024-04-02T15:10:00Z/PT5M</Dimension>
      </Layer>
    </Layer>
  </Capability>
</WMS_Capabilities>
''';

      final document = XmlDocument.parse(xmlString);
      final timeDim = document.findAllElements('Dimension').first;
      final timeText = timeDim.innerText.trim();
      final defaultTimeStr = timeDim.getAttribute('default');
      final referenceTime = DateTime.parse(defaultTimeStr!);
      final parts = timeText.split('/');
      final fullStart = DateTime.parse(parts[0]);
      final fullEnd = DateTime.parse(parts[1]);
      
      DateTime windowStart = referenceTime.subtract(const Duration(hours: 1));
      DateTime windowEnd = referenceTime.add(const Duration(hours: 2));

      if (windowStart.isBefore(fullStart)) windowStart = fullStart;
      if (windowEnd.isAfter(fullEnd)) windowEnd = fullEnd;

      expect(windowStart, fullStart); // Clamped to 14:50 instead of 14:00
      expect(windowEnd, fullEnd);     // Clamped to 15:10 instead of 17:00
    });
  });
}
