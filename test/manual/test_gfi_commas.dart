// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
void main() async {
  final baseUrl = 'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server?service=WMS&request=GetFeatureInfo&layers=precipitation_nowcast&query_layers=precipitation_nowcast&format=image%2Fpng&info_format=application%2Fjson&crs=EPSG%3A4326&width=1&height=1&x=0&y=0&bbox=4.757239,52.2592,4.777,52.279&DATASET=radar_forecast_2.0';
  
  List<String> times = [];
  DateTime start = DateTime.parse('2026-04-03T12:55:00Z');
  for (int i=0; i<36; i++) {
    times.add('${start.toIso8601String().substring(0,19)}Z');
    start = start.add(Duration(minutes: 5));
  }
  
  final timeStr = times.join(',');
  print('Testing 36 comma-separated frames...');
  final res = await http.get(Uri.parse('$baseUrl&TIME=$timeStr'));
  print('Status: ${res.statusCode}');
  if (res.statusCode != 200) {
    print('Body: ${res.body}');
  } else {
    print('Success');
  }
}
