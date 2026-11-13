import 'package:geolocator/geolocator.dart';

/// Outcome of a location request. The coordinates are held only in memory
/// for the duration of one prediction request and are never persisted or
/// logged (SRS 5.3 / 6).
enum LocationStatus { ok, servicesDisabled, permissionDenied, permissionDeniedForever, failed }

class LocationResult {
  const LocationResult(this.status, {this.latitude, this.longitude, this.error});

  final LocationStatus status;
  final double? latitude;
  final double? longitude;
  final String? error;

  bool get isOk => status == LocationStatus.ok;
}

/// Abstract so the controller and screen can be tested with a fake.
abstract class LocationService {
  Future<LocationResult> getCurrentLocation();

  /// Opens the OS location settings (used from the "services disabled"
  /// and "permanently denied" states).
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

/// Best-effort reverse geocoding of the device fix into a locality label
/// such as "Cebu City, Cebu" -- DISPLAY ONLY. The prediction request always
/// carries the raw coordinates; nothing here feeds back into it.
///
/// Implementations: [WebPlaceNameResolver] (web reverse geocoding, the
/// default -- see core/config.dart) and [NoPlaceNameResolver] (label
/// disabled). The UI depends only on this interface.
abstract class PlaceNameResolver {
  /// Returns null when no locality can be determined; must not throw.
  Future<String?> resolve(double latitude, double longitude);

  /// Data-licence attribution to show wherever a resolved name is shown
  /// (null when none is required).
  String? get attribution;
}

class NoPlaceNameResolver implements PlaceNameResolver {
  const NoPlaceNameResolver();
  @override
  Future<String?> resolve(double latitude, double longitude) async => null;
  @override
  String? get attribution => null;
}

/// geolocator-backed implementation (Android now, iOS-portable).
class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.servicesDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission(); // SRS REQ-4.3-1: ask on launch
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.permissionDeniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationResult(LocationStatus.permissionDenied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // 1 km grid cells: block-level accuracy is plenty
          timeLimit: Duration(seconds: 30),
        ),
      );
      return LocationResult(LocationStatus.ok, latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      return LocationResult(LocationStatus.failed, error: e.toString());
    }
  }

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
