# Agent Guidelines for Open Rain

## Verification & Pre-Flight Gate
Before marking any task complete or notifying the user:
- Run `flutter analyze --fatal-infos` (must report `No issues found!`).
- Run `flutter test` (all test suites must pass).

## Tool Execution Protocol
- **Chunk Replacement**: Always inspect tool responses from `multi_replace_file_content`. If any chunk reports `target content not found in file`, re-read the target file with `view_file` and resolve line mismatches before proceeding.
- **Task Boundaries**: Avoid calling `task_boundary` on single-step or trivial 1–2 line fixes.

## Architecture & Layout Invariants
- **Single Page View**: Keep weather, radar, precipitation chart, and forecast controls on the primary dashboard. Do not introduce multi-screen routing or bottom navigation bars.
- **Web Constraints**: Preserve the centered `maxWidth: 1000` layout constraint on web targets (`main.dart`).
- **Map Base Layer**: Use CartoDB Positron raster tiles for the base map. Do not configure public OpenStreetMap tile endpoints (`tile.openstreetmap.org`).
- **Radar Animation**: Toggle layer `Opacity` across preloaded frames. Do not unmount or recreate `TileLayer` widgets during playback ticks.
- **Timezone Normalization**: Store and compare timestamps in UTC milliseconds. Parse Open-Meteo local strings through `WeatherData.parseTime(t, offsetSeconds)` rather than appending `'Z'`.
- **Environment Variables**: Access build-time `--dart-define` variables via `Env.getOptional` or dedicated getters in `lib/utils/env.dart`.
