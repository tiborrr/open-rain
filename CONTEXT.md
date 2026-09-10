# Open Rain

Open Rain provides high-resolution precipitation nowcasting, live radar visualization, and local weather conditions.

## Language

**Precipitation Nowcast**:
The short-term (0–2 hour) precipitation projection derived from radar extrapolation, synchronized with radar frames and enriched with spatial neighbor samples.
_Avoid_: Weather forecast, rain prediction, chart forecast

**Radar Frame**:
A single timestamped raster or WMS precipitation layer representing an observed or extrapolated nowcast step.
_Avoid_: Map tile, radar slice, animation frame

**Neighbor Sample**:
A precipitation time series sampled from an adjacent coordinate point in a spatial grid surrounding the primary location to visualize precipitation uncertainty.
_Avoid_: Grid point, surrounding forecast, spatial probe

**Minutely Forecast**:
The minute-by-minute (or 15-minute bucket) precipitation time series for a single coordinate.
_Avoid_: Point forecast, rain timeline

**Weather Provider**:
An adapter supplying local weather conditions, high-resolution minutely precipitation series, multi-day forecasts, air quality, and severe weather alerts for a geographic point across foreground and background isolates.
_Avoid_: Weather repository, weather client

**Radar Provider**:
An adapter supplying radar imagery layers, raster tile configurations, and tile cache invalidation for map rendering.
_Avoid_: Radar repository, tile service

**Location Provider**:
An adapter supplying resolved device coordinates, fallback handling, significant movement streams, and location search across platform GPS states.
_Avoid_: Location service, geolocator wrapper, GPS manager
