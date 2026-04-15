// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
void main() async {
  final url = 'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server?service=WMS&request=GetFeatureInfo&layers=precipitation_nowcast&query_layers=precipitation_nowcast&format=image%2Fpng&info_format=application%2Fjson&crs=EPSG%3A4326&width=1&height=1&x=0&y=0&bbox=4.7572399999999995,52.2592,4.777239999999999,52.279199999999996&DATASET=radar_forecast_2.0&TIME=2026-04-03T12:55:00Z/2026-04-03T15:55:00Z';
  print('Requesting: $url');
  final res = await http.get(Uri.parse(url));
  print('Status: ${res.statusCode}');
  if (res.statusCode != 200) print('Body: ${res.body}');
  
  // Try with step
  final url2 = '$url/PT5M';
  print('\nRequesting with step: $url2');
  final res2 = await http.get(Uri.parse(url2));
  print('Status2: ${res2.statusCode}');
  if (res2.statusCode != 200) print('Body2: ${res2.body}');

  // Try with comma separated times
  final url3 = 'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server?service=WMS&request=GetFeatureInfo&layers=precipitation_nowcast&query_layers=precipitation_nowcast&format=image%2Fpng&info_format=application%2Fjson&crs=EPSG%3A4326&width=1&height=1&x=0&y=0&bbox=4.7572399999999995,52.2592,4.777239999999999,52.279199999999996&DATASET=radar_forecast_2.0&TIME=2026-04-03T14:55:00Z';
  print('\nRequesting single time: $url3');
  final res3 = await http.get(Uri.parse(url3));
  print('Status3: ${res3.statusCode}');
  if (res3.statusCode != 200) print('Body3: ${res3.body}');
}
