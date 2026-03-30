import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/weather_models.dart';
import '../utils/weather_utils.dart';
import '../theme.dart';

class HourlyForecastList extends StatelessWidget {
  final HourlyForecast forecast;
  final Duration utcOffset;
  final DateTime localNow;

  const HourlyForecastList({
    super.key,
    required this.forecast,
    required this.utcOffset,
    required this.localNow,
  });

  @override
  Widget build(BuildContext context) {
    // Find the first index that is not in the past (current hour or later)
    final nowHour = DateTime(localNow.year, localNow.month, localNow.day, localNow.hour);
    final startIndex = forecast.times.indexWhere((t) {
      final localT = t.add(utcOffset);
      return localT.isAtSameMomentAs(nowHour) || localT.isAfter(nowHour);
    });

    final actualStartIndex = startIndex < 0 ? 0 : startIndex;
    final remainingItems = forecast.times.length - actualStartIndex;
    final length = remainingItems > 24 ? 24 : remainingItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NEXT 24 HOURS',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final forecastIndex = actualStartIndex + index;
              final time = forecast.times[forecastIndex].add(utcOffset);
              final hour = '${time.hour.toString().padLeft(2, '0')}:00';

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(hour, style: Theme.of(context).textTheme.bodyMedium),
                    Icon(
                      WeatherUtils.getWeatherIcon(forecast.weatherCodes[forecastIndex]),
                      color: WeatherUtils.getWeatherColor(forecast.weatherCodes[forecastIndex]),
                    ),
                    Text(
                      '${forecast.temperatures[forecastIndex].toStringAsFixed(0)}°',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DailyForecastList extends StatefulWidget {
  final DailyForecast forecast;
  final Duration utcOffset;

  const DailyForecastList({
    super.key,
    required this.forecast,
    required this.utcOffset,
  });

  @override
  State<DailyForecastList> createState() => _DailyForecastListState();
}

class _DailyForecastListState extends State<DailyForecastList> {
  bool _isExpanded = false;

  String _formatDate(DateTime date, DateTime localNow) {
    final diff = DateTime(date.year, date.month, date.day)
        .difference(DateTime(localNow.year, localNow.month, localNow.day))
        .inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final localNow = DateTime.now().add(widget.utcOffset);
    final displayedCount = _isExpanded ? widget.forecast.times.length : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '14-DAY OUTLOOK',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayedCount,
            separatorBuilder: (context, index) => const Divider(height: 32, thickness: 0.5, color: Colors.black12),
            itemBuilder: (context, index) {
              final date = widget.forecast.times[index].add(widget.utcOffset);
              final dateStr = _formatDate(date, localNow);
              
              return Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      dateStr, 
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    WeatherUtils.getWeatherIcon(widget.forecast.weatherCodes[index]),
                    color: WeatherUtils.getWeatherColor(widget.forecast.weatherCodes[index]),
                    size: 28,
                  ),
                  const Spacer(),
                  Text(
                    '${widget.forecast.maxTemps[index].toStringAsFixed(0)}°',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${widget.forecast.minTemps[index].toStringAsFixed(0)}°',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            icon: Icon(
              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
              size: 20,
            ),
            label: Text(_isExpanded ? 'Show less' : 'Show remaining 9 days'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
