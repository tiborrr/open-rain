import 'package:flutter/material.dart';
import '../models/weather_models.dart';

class SevereAlertCard extends StatelessWidget {
  final WeatherAlert alert;

  const SevereAlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (alert.type) {
      case 'danger':
        icon = Icons.warning_amber_rounded;
        break;
      case 'warning':
        icon = Icons.info_outline;
        break;
      default:
        icon = Icons.notifications_none;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alert.type == 'danger' 
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: alert.type == 'danger'
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).colorScheme.onSecondaryContainer,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: alert.type == 'danger'
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: alert.type == 'danger'
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onSecondaryContainer,
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
