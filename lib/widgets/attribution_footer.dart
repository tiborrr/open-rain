import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A small footer shown at the bottom of the dashboard that satisfies the
/// attribution requirements of the data providers used by this app.
class AttributionFooter extends StatelessWidget {
  const AttributionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          _AttributionLink(
            label: 'Weather data by Open-Meteo.com',
            url: 'https://open-meteo.com/',
          ),
          Text('·', style: _style(context)),
          _AttributionLink(
            label: 'Radar by KNMI',
            url: 'https://dataplatform.knmi.nl/',
          ),
          Text('·', style: _style(context)),
          _AttributionLink(
            label: 'Map tiles by CartoCDN',
            url: 'https://carto.com/attributions',
          ),
        ],
      ),
    );
  }

  TextStyle _style(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
}

class _AttributionLink extends StatelessWidget {
  final String label;
  final String url;

  const _AttributionLink({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final linkStyle = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return RichText(
      text: TextSpan(
        text: label,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
      ),
    );
  }
}
