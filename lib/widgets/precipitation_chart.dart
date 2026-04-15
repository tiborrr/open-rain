import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../controllers/radar_controller.dart';
import '../models/weather_models.dart';

class PrecipitationChart extends StatelessWidget {
  final MinutelyForecast forecast;
  final RadarController controller;
  final DateTime localNow;
  final Duration utcOffset;

  const PrecipitationChart({
    super.key,
    required this.forecast,
    required this.controller,
    required this.localNow,
    this.utcOffset = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final windowStart = now.subtract(const Duration(hours: 1));
    final windowEnd = now.add(const Duration(hours: 2));

    List<FlSpot> spots = [];
    double maxPrecip = 0;

    for (int i = 0; i < forecast.times.length; i++) {
      final time = forecast.times[i];
      if (!time.isBefore(windowStart) && !time.isAfter(windowEnd)) {
        final val = forecast.precipitation[i];
        if (val > maxPrecip) maxPrecip = val;
        spots.add(FlSpot(time.millisecondsSinceEpoch.toDouble(), val));
      }
    }

    if (spots.isEmpty) {
      spots.add(FlSpot(windowStart.millisecondsSinceEpoch.toDouble(), 0));
      spots.add(FlSpot(windowEnd.millisecondsSinceEpoch.toDouble(), 0));
    }

    final minX = windowStart.millisecondsSinceEpoch.toDouble();
    final maxX = windowEnd.millisecondsSinceEpoch.toDouble();
    final maxY = maxPrecip < 5.0 ? 5.0 : (maxPrecip * 1.2).ceilToDouble();

    return Container(
      height: 200,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PRECIPITATION',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) => IconButton(
                  icon: Icon(
                    controller.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => controller.togglePlay(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                        if (event is FlPanUpdateEvent || event is FlPanDownEvent || event is FlTapDownEvent) {
                          if (touchResponse != null && touchResponse.lineBarSpots != null) {
                            final x = touchResponse.lineBarSpots!.first.x;
                            controller.seekTo(DateTime.fromMillisecondsSinceEpoch(x.toInt(), isUtc: true));
                          }
                        }
                      },
                    ),
                    extraLinesData: ExtraLinesData(
                      verticalLines: [
                        VerticalLine(
                          x: localNow.subtract(utcOffset).millisecondsSinceEpoch.toDouble(),
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                          strokeWidth: 1.5,
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                            labelResolver: (line) => 'NOW',
                          ),
                        ),
                        if (controller.currentFrame != null)
                          VerticalLine(
                            x: controller.currentFrame!.time.millisecondsSinceEpoch.toDouble(),
                            color: Theme.of(context).colorScheme.onSurface,
                            strokeWidth: 2,
                            dashArray: [5, 5],
                          ),
                      ],
                    ),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1800000,
                          getTitlesWidget: (value, meta) {
                            // Convert UTC x-axis value to location local time
                            final time = DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).add(utcOffset);
                            return Text(
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: maxY > 10 ? (maxY / 4).ceilToDouble() : (maxY <= 5 ? 1 : 2),
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const SizedBox.shrink();
                            return Text(
                              '${value.toStringAsFixed(0)} mm',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
                            );
                          },
                          reservedSize: 32,
                        ),
                      ),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: minX,
                    maxX: maxX,
                    minY: 0,
                    maxY: maxY,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
