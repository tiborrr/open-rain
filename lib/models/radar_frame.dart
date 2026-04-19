class RadarFrame {
  final String frameId;
  final DateTime time;

  RadarFrame({required this.frameId, required this.time});

  Map<String, dynamic> toJson() => {
        'frameId': frameId,
        'time': time.toIso8601String(),
      };

  factory RadarFrame.fromJson(Map<String, dynamic> json) => RadarFrame(
        frameId: json['frameId'],
        time: DateTime.parse(json['time']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadarFrame && runtimeType == other.runtimeType && frameId == other.frameId && time == other.time;

  @override
  int get hashCode => frameId.hashCode ^ time.hashCode;
}
