import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../controllers/radar_controller.dart';
import '../models/weather_models.dart';

/// Layout and axis tuning for the precipitation chart timeline.
abstract final class _PrecipitationChartLayout {
  _PrecipitationChartLayout._();

  static const Duration emptyStatePastExtent = Duration(hours: 1);
  static const Duration emptyStateFutureExtent = Duration(hours: 2);

  /// Default Y-axis cap when precipitation is low (mm).
  static const double defaultMaxYMm = 5.0;
  static const double maxYHeadroomFactor = 1.2;

  /// Aim for roughly this many bottom-axis labels across the visible span.
  static const int bottomAxisTargetSegmentCount = 5;

  /// Do not label more often than this (avoids overlapping ticks on short ranges).
  static const Duration bottomAxisMinLabelInterval = Duration(minutes: 15);
}

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
    final nowUtc = DateTime.now().toUtc();
    final nowUtcX = localNow
        .subtract(utcOffset)
        .millisecondsSinceEpoch
        .toDouble();

    final List<FlSpot> spots = [];
    double maxPrecip = 0;

    for (int i = 0; i < forecast.times.length; i++) {
      final time = forecast.times[i];
      final val = forecast.precipitation[i];
      if (val > maxPrecip) maxPrecip = val;
      spots.add(FlSpot(time.millisecondsSinceEpoch.toDouble(), val));
    }

    double baseMinX;
    double baseMaxX;
    if (forecast.times.isNotEmpty) {
      baseMinX = forecast.times.first.millisecondsSinceEpoch.toDouble();
      baseMaxX = forecast.times.last.millisecondsSinceEpoch.toDouble();
    } else {
      baseMinX = nowUtc
          .subtract(_PrecipitationChartLayout.emptyStatePastExtent)
          .millisecondsSinceEpoch
          .toDouble();
      baseMaxX = nowUtc
          .add(_PrecipitationChartLayout.emptyStateFutureExtent)
          .millisecondsSinceEpoch
          .toDouble();
    }

    final maxY = maxPrecip < _PrecipitationChartLayout.defaultMaxYMm
        ? _PrecipitationChartLayout.defaultMaxYMm
        : (maxPrecip * _PrecipitationChartLayout.maxYHeadroomFactor)
              .ceilToDouble();

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
                var minX = baseMinX;
                var maxX = baseMaxX;
                void widenTo(double x) {
                  minX = math.min(minX, x);
                  maxX = math.max(maxX, x);
                }

                widenTo(nowUtcX);
                if (controller.currentFrame != null) {
                  widenTo(
                    controller.currentFrame!.time.millisecondsSinceEpoch
                        .toDouble(),
                  );
                }
                for (final s in spots) {
                  widenTo(s.x);
                }

                final chartSpots = spots.isEmpty
                    ? <FlSpot>[FlSpot(minX, 0), FlSpot(maxX, 0)]
                    : spots;

                final xSpanMs = (maxX - minX).clamp(1.0, double.infinity);
                final minLabelMs = _PrecipitationChartLayout
                    .bottomAxisMinLabelInterval
                    .inMilliseconds
                    .toDouble();
                final titleIntervalMs = math.max(
                  minLabelMs,
                  (xSpanMs /
                          _PrecipitationChartLayout
                              .bottomAxisTargetSegmentCount)
                      .roundToDouble(),
                );

                return LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchCallback:
                          (
                            FlTouchEvent event,
                            LineTouchResponse? touchResponse,
                          ) {
                            if (event is FlPanUpdateEvent ||
                                event is FlPanDownEvent ||
                                event is FlTapDownEvent) {
                              if (touchResponse != null &&
                                  touchResponse.lineBarSpots != null) {
                                final xMs = touchResponse.lineBarSpots!.first.x
                                    .toInt();
                                // Snap to the nearest plotted timestamp so the scrubber
                                // tracks chart points instead of arbitrary axis pixels.
                                // Falls back to the raw touch time when the series is
                                // empty.
                                final target =
                                    forecast.nearestTimeUtcToMillis(xMs) ??
                                    DateTime.fromMillisecondsSinceEpoch(
                                      xMs,
                                      isUtc: true,
                                    );
                                controller.seekTo(target);
                              }
                            }
                          },
                    ),
                    extraLinesData: ExtraLinesData(
                      verticalLines: [
                        VerticalLine(
                          x: localNow
                              .subtract(utcOffset)
                              .millisecondsSinceEpoch
                              .toDouble(),
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.7),
                          strokeWidth: 1.5,
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                            labelResolver: (line) => 'NOW',
                          ),
                        ),
                        if (controller.currentFrame != null)
                          VerticalLine(
                            x: controller
                                .currentFrame!
                                .time
                                .millisecondsSinceEpoch
                                .toDouble(),
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
                          interval: titleIntervalMs,
                          getTitlesWidget: (value, meta) {
                            // Convert UTC x-axis value to location local time
                            final time = DateTime.fromMillisecondsSinceEpoch(
                              value.toInt(),
                              isUtc: true,
                            ).add(utcOffset);
                            return Text(
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(fontSize: 10),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: maxY > 10
                              ? (maxY / 4).ceilToDouble()
                              : (maxY <= _PrecipitationChartLayout.defaultMaxYMm
                                    ? 1
                                    : 2),
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const SizedBox.shrink();
                            return Text(
                              '${value.toStringAsFixed(0)} mm',
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(fontSize: 10),
                            );
                          },
                          reservedSize: 32,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: minX,
                    maxX: maxX,
                    minY: 0,
                    maxY: maxY,
                    lineBarsData: [
                      LineChartBarData(
                        spots: chartSpots,
                        isCurved: true,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3),
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.0),
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
