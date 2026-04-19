// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
void main() async {
  final baseUrl = 'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server?service=WMS&request=GetFeatureInfo&layers=precipitation_nowcast&query_layers=precipitation_nowcast&format=image%2Fpng&info_format=application%2Fjson&crs=EPSG%3A4326&width=1&height=1&x=0&y=0&bbox=4.757239,52.2592,4.777,52.279&DATASET=radar_forecast_2.0';
  
  final times = {
    '1 hour': '2026-04-03T14:55:00Z/2026-04-03T15:55:00Z',
    '3 hours': '2026-04-03T12:55:00Z/2026-04-03T15:55:00Z',
    'comma-separated 1 hour': '2026-04-03T12:55:00Z,2026-04-03T13:00:00Z,2026-04-03T13:05:00Z,2026-04-03T13:10:00Z,2026-04-03T13:15:00Z,2026-04-03T13:20:00Z,2026-04-03T13:25:00Z,2026-04-03T13:30:00Z,2026-04-03T13:35:00Z,2026-04-03T13:40:00Z',
  };

  for (var entry in times.entries) {
    print('\nTesting ${entry.key}...');
    final url = '$baseUrl&TIME=${entry.value}';
    final res = await http.get(Uri.parse(url));
    print('Status: ${res.statusCode}');
    if (res.statusCode != 200) {
      print('Body: ${res.body}');
    } else {
      print('Success');
    }
  }
}
