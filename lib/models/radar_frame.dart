class RadarFrame {
  final String path;
  final DateTime time;

  RadarFrame({required this.path, required this.time});

  Map<String, dynamic> toJson() => {
        'path': path,
        'time': time.toIso8601String(),
      };

  factory RadarFrame.fromJson(Map<String, dynamic> json) => RadarFrame(
        path: json['path'],
        time: DateTime.parse(json['time']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadarFrame && runtimeType == other.runtimeType && path == other.path && time == other.time;

  @override
  int get hashCode => path.hashCode ^ time.hashCode;
}
