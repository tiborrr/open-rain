# Open Rain — Flutter Weather App

**Version:** 1.5.0 (see `pubspec.yaml` for the full `version` + build number).

> [!NOTE]
> This project began as an experiment with **Google Stitch** and **Antigravity**. It is now developed in **[Cursor](https://cursor.com/)**, primarily through pair-programming with **Opus 4.7**, to keep exploring agentic coding and automated UI design.

A Flutter weather app focused on precipitation, featuring an animated radar map and minute-by-minute nowcasting. The web build uses the **Open Rain** document title; iOS, Android, macOS, and web are supported targets.

## Features

- **Live radar map** with animated WMS tiles from KNMI (Netherlands Royal Meteorological Institute)
- **Minute-by-minute precipitation chart** synced to the radar playhead
- **Rain alerts** — uses Open-Meteo minutely precipitation to warn when rain is expected soon (about 20 minutes ahead) and for how long. **iOS & Android:** local notifications plus periodic background checks (subject to OS scheduling). **Web:** checks while the tab is active (browsers cannot run reliable background work like mobile).
- **Current conditions** — temperature, wind, UV index, humidity, feels-like
- **Hourly & 14-day forecast**
- **Air quality index** (PM2.5, PM10, ozone, NO₂)
- **Severe weather alerts** (via Open-Meteo)
- **GPS-based location** with city search fallback
- Works without an API key via anonymous KNMI access

## Getting Started

### 1. Clone & install

```bash
git clone https://github.com/your-username/weather_app.git
cd weather_app
flutter pub get
```

### 2. Configure API keys (optional)

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Fill in your [KNMI Data Platform](https://developer.dataplatform.knmi.nl/) WMS API key if you have one. The app works without it via the anonymous endpoint, but you will be subject to lower rate limits.

```env
KNMI_WMS_API_KEY=your_key_here
```

### 3. Run

```bash
flutter run
```

## Attribution

This app uses data from the following providers, in compliance with their respective licences:

### Open-Meteo
Weather forecast, air quality, and **minutely precipitation** (used for rain-ahead alerts) are provided by **[Open-Meteo.com](https://open-meteo.com/)** under the [Creative Commons Attribution 4.0 International Licence (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

> You are free to share and adapt the data, provided you give appropriate credit and link to the licence.

Open-Meteo is open-source. Source code is available on [GitHub](https://github.com/open-meteo/open-meteo) under the GNU AGPL v3 licence.

### KNMI Data Platform
Precipitation radar data (nowcasting) is provided by the **[Royal Netherlands Meteorological Institute (KNMI)](https://dataplatform.knmi.nl/)** via their open WMS API.

- [KNMI Data Policy](https://www.knmi.nl/kennis-en-datacentrum/uitleg/knmi-open-data)
- [API Documentation](https://developer.dataplatform.knmi.nl/)

### CartoCDN
Base map tiles are provided by **[Carto](https://carto.com/)** ([Attribution requirements](https://carto.com/attributions)).

## Licence

This project's source code is released under the [MIT Licence](LICENSE).
