import 'package:flutter/material.dart';
import '../models/weather_models.dart';
import '../theme.dart';

class AirQualityCard extends StatelessWidget {
  final AirQuality airQuality;

  const AirQualityCard({super.key, required this.airQuality});

  Color _getAqiColor(int aqi) {
    if (aqi <= 20) return const Color(0xFF00C853); // Deep Green
    if (aqi <= 40) return const Color(0xFF64DD17); // Light Green
    if (aqi <= 60) return const Color(0xFFFFD600); // Yellow
    if (aqi <= 80) return const Color(0xFFFF9100); // Orange
    return const Color(0xFFFF1744); // Red
  }

  @override
  Widget build(BuildContext context) {
    final aqiColor = _getAqiColor(airQuality.aqi);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AIR QUALITY & HEALTH',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: aqiColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LIVE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: aqiColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Circular Gauge
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: airQuality.aqi / 100,
                      strokeWidth: 10,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      color: aqiColor,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${airQuality.aqi}',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'AQI',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 32),
              // Pollutants Column
              Expanded(
                child: Column(
                  children: [
                    _PollutantProgressRow(
                      label: 'PM2.5',
                      value: airQuality.pm2_5,
                      unit: 'µg/m³',
                      maxValue: 50,
                      color: aqiColor,
                    ),
                    const SizedBox(height: 16),
                    _PollutantProgressRow(
                      label: 'OZONE',
                      value: airQuality.ozone,
                      unit: 'µg/m³',
                      maxValue: 180,
                      color: aqiColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Recommendation Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: aqiColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: aqiColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    airQuality.recommendation,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PollutantProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double maxValue;
  final Color color;

  const _PollutantProgressRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(0),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / maxValue).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            color: color,
          ),
        ),
      ],
    );
  }
}
