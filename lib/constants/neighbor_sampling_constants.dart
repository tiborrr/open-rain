/// Spatial grid for background neighbor precipitation sampling (degrees latitude/longitude).
abstract final class NeighborSamplingConstants {
  NeighborSamplingConstants._();

  /// Offset from center for each axis in the 3×3 grid (approx. tens of km at mid-latitudes).
  static const double gridStepDegrees = 0.15;
}
