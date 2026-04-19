import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_weather/services/knmi_capabilities.dart';

void main() {
  group('KnmiCapabilities.computeFrameTimes', () {
    test('30m history through fullEnd on 5m grid', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<WMS_Capabilities>
  <Capability>
    <Layer>
      <Layer>
        <Name>precipitation_nowcast</Name>
        <Dimension name="time" units="ISO8601" default="2024-04-02T15:00:00Z">2024-04-02T14:00:00Z/2024-04-02T18:00:00Z/PT5M</Dimension>
      </Layer>
    </Layer>
  </Capability>
</WMS_Capabilities>
''';

      final times = KnmiCapabilities.computeFrameTimes(
        xml,
        nowUtc: DateTime.parse('2024-04-02T15:00:00Z'),
      );

      expect(times.first, DateTime.parse('2024-04-02T14:30:00Z'));
      expect(times.last, DateTime.parse('2024-04-02T18:00:00Z'));
      expect(times.length, 43);
    });

    test('clamps window start to API bounds', () {
      const xml = '''
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

      final times = KnmiCapabilities.computeFrameTimes(
        xml,
        nowUtc: DateTime.parse('2024-04-02T15:00:00Z'),
      );

      expect(times.first, DateTime.parse('2024-04-02T14:50:00Z'));
      expect(times.last, DateTime.parse('2024-04-02T15:10:00Z'));
      expect(times.length, 5);
    });
  });
}
