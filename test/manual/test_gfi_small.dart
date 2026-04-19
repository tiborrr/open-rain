// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
void main() async {
  final url = 'https://anonymous.api.dataplatform.knmi.nl/wms/adaguc-server?service=WMS&request=GetFeatureInfo&layers=precipitation_nowcast&query_layers=precipitation_nowcast&format=image%2Fpng&info_format=application%2Fjson&crs=EPSG%3A4326&width=1&height=1&x=0&y=0&bbox=4.757239,52.2592,4.758,52.260&DATASET=radar_forecast_2.0&TIME=2026-04-03T12:55:00Z/2026-04-03T15:55:00Z';
  print('Requesting: $url');
  final res = await http.get(Uri.parse(url));
  print('Status: ${res.statusCode}');
  if (res.statusCode != 200) print('Body: ${res.body}');
}
