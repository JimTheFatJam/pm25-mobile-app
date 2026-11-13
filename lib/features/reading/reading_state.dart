import '../../models/prediction_reading.dart';

/// The device's own GPS fix for the current reading, kept in memory only
/// for as long as that reading is on screen (never persisted or logged --
/// SRS 5.3 / 6). These are the exact coordinates sent to the backend; the
/// optional [placeName] is display-only and never part of the request.
class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude, this.placeName});
  final double latitude;
  final double longitude;

  /// Approximate human-readable locality (e.g. "Cebu City, Cebu"), when a
  /// resolver is available; null otherwise.
  final String? placeName;

  DeviceLocation withPlaceName(String? name) => DeviceLocation(latitude: latitude, longitude: longitude, placeName: name);

  /// "10.3157° N, 123.8854° E" -- 4 decimals (about 10 m), user-facing.
  String get coordinatesLabel => formatCoordinates(latitude, longitude);
}

String formatCoordinates(double latitude, double longitude) {
  final ns = latitude < 0 ? 'S' : 'N';
  final ew = longitude < 0 ? 'W' : 'E';
  return '${latitude.abs().toStringAsFixed(4)}° $ns, ${longitude.abs().toStringAsFixed(4)}° $ew';
}

/// Every state the single reading screen can be in (SRS 4.3 / REQ-4.3-9:
/// informative messages instead of silent failure).
sealed class ReadingState {
  const ReadingState();
}

/// Asking the OS for location permission / checking services.
class RequestingPermission extends ReadingState {
  const RequestingPermission();
}

class PermissionDenied extends ReadingState {
  const PermissionDenied();
}

class PermissionDeniedForever extends ReadingState {
  const PermissionDeniedForever();
}

class LocationServicesDisabled extends ReadingState {
  const LocationServicesDisabled();
}

class Locating extends ReadingState {
  const Locating();
}

class LocationFailed extends ReadingState {
  const LocationFailed(this.detail);
  final String detail;
}

/// Prediction request in progress. [slow] flips to true after
/// AppConfig.slowThreshold so the UI can explain that a first (cold)
/// request needs live environmental-data retrieval on the server.
class LoadingPrediction extends ReadingState {
  const LoadingPrediction({this.slow = false, this.elapsed = Duration.zero, this.previous, this.location});
  final bool slow;
  final Duration elapsed;

  /// The fix being sent to the backend (shown in the location card).
  final DeviceLocation? location;

  /// The last successful reading, if this is a refresh -- kept so the
  /// screen can show it dimmed instead of a blank page.
  final PredictionReading? previous;
}

class Success extends ReadingState {
  const Success(this.reading, {this.receivedAt, this.location});
  final PredictionReading reading;
  final DateTime? receivedAt;

  /// The device fix this reading was requested for.
  final DeviceLocation? location;
}

/// The point resolved to no 1 km cell (sea / outside the Philippine grid).
class OutsideCoverage extends ReadingState {
  const OutsideCoverage(this.message, {this.location});
  final String message;
  final DeviceLocation? location;
}

/// Backend could not produce a reading (availability pending/failed, model
/// unavailable, prediction failed, or an "unavailable" status reading).
class PredictionUnavailable extends ReadingState {
  const PredictionUnavailable(this.message, {this.code, this.location});
  final String message;
  final String? code;
  final DeviceLocation? location;
}

class NetworkError extends ReadingState {
  const NetworkError(this.message, {this.location});
  final String message;
  final DeviceLocation? location;
}
