import 'package:flutter/material.dart';
import '../models/weather_models.dart';
import '../utils/weather_utils.dart';
import '../theme.dart';

class CurrentConditionsCard extends StatelessWidget {
  final CurrentWeather current;
  final DateTime localNow;
  final String timezone;

  const CurrentConditionsCard({
    super.key,
    required this.current,
    required this.localNow,
    required this.timezone,
  });

  @override
  Widget build(BuildContext context) {
    final conditionColor = WeatherUtils.getWeatherColor(current.weatherCode);

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
                'CURRENTLY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              Text(
                '${localNow.hour.toString().padLeft(2, '0')}:${localNow.minute.toString().padLeft(2, '0')} ($timezone)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${current.temperature.toStringAsFixed(1)}°',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                    child: Text(
                      'C',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Icon(
                WeatherUtils.getWeatherIcon(current.weatherCode),
                size: 80,
                color: conditionColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _ConditionChip(
                icon: Icons.water_drop_rounded,
                label: '${current.humidity}% Humidity',
                color: const Color(0xFF007AFF),
              ),
              const SizedBox(width: 12),
              _ConditionChip(
                icon: Icons.umbrella_rounded,
                label: '${current.precipitation} mm Rain',
                color: const Color(0xFF5E5CE6),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ConditionChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
