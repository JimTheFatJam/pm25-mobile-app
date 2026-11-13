import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../models/prediction_reading.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import 'reading_state.dart';

/// Drives the one screen: permission -> location -> single backend request
/// -> state. Plain ChangeNotifier; no state-management framework.
///
/// Privacy: the coordinates live in a local variable for the duration of
/// [load] and in the resulting state (so the screen can show the user
/// which fix was used). They are never stored on the controller beyond
/// the current state, logged, or persisted anywhere (SRS 5.3 / 6).
class ReadingController extends ChangeNotifier {
  ReadingController({
    required LocationService locationService,
    required PredictionApi api,
    PlaceNameResolver placeNameResolver = const NoPlaceNameResolver(),
    Duration? slowThreshold,
    Duration? tickInterval,
  })  : _location = locationService,
        _api = api,
        _places = placeNameResolver,
        _slowThreshold = slowThreshold ?? AppConfig.slowThreshold,
        _tickInterval = tickInterval ?? const Duration(seconds: 1);

  final LocationService _location;
  final PredictionApi _api;
  final PlaceNameResolver _places;
  final Duration _slowThreshold;
  final Duration _tickInterval;

  ReadingState _state = const RequestingPermission();
  ReadingState get state => _state;

  /// Attribution for displayed place names (e.g. OpenStreetMap), if any.
  String? get placeAttribution => _places.attribution;

  PredictionReading? _lastReading;
  int _generation = 0;
  Timer? _ticker;
  bool _disposed = false;

  void _set(ReadingState s) {
    if (_disposed) return;
    _state = s;
    notifyListeners();
  }

  /// Full flow. `refresh` keeps the previous reading visible while the new
  /// request runs; the location is re-acquired every time (never reused
  /// from a stored copy).
  Future<void> load({bool refresh = false}) async {
    final gen = ++_generation;
    final previous = refresh ? _lastReading : null;

    _set(const RequestingPermission());
    final loc = await _location.getCurrentLocation();
    if (gen != _generation) return;
    switch (loc.status) {
      case LocationStatus.servicesDisabled:
        _set(const LocationServicesDisabled());
        return;
      case LocationStatus.permissionDenied:
        _set(const PermissionDenied());
        return;
      case LocationStatus.permissionDeniedForever:
        _set(const PermissionDeniedForever());
        return;
      case LocationStatus.failed:
        _set(LocationFailed(loc.error ?? 'Unknown location error.'));
        return;
      case LocationStatus.ok:
        break;
    }

    // The exact device fix: this is what the backend receives. The locality
    // label is resolved concurrently, display-only, and never delays or
    // alters the request (a resolver failure just means no label).
    var device = DeviceLocation(latitude: loc.latitude!, longitude: loc.longitude!);
    final placeFuture = _places
        .resolve(device.latitude, device.longitude)
        .timeout(const Duration(seconds: 5), onTimeout: () => null)
        .catchError((Object _) => null);

    _set(LoadingPrediction(previous: previous, location: device));
    // Elapsed time is accumulated from ticks (not wall-clock reads), so the
    // "slow" transition is deterministic and testable with a fake clock.
    var elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (gen != _generation) return;
      elapsed += _tickInterval;
      _set(LoadingPrediction(slow: elapsed >= _slowThreshold, elapsed: elapsed, previous: previous, location: device));
    });

    try {
      final reading = await _api.fetchReading(latitude: device.latitude, longitude: device.longitude);
      if (gen != _generation) return;
      device = device.withPlaceName(await placeFuture);
      if (gen != _generation) return;
      if (!reading.hasValue) {
        _set(PredictionUnavailable(reading.message ?? 'No estimate is available for this location right now.',
            code: 'unavailable', location: device));
        return;
      }
      _lastReading = reading;
      _set(Success(reading, receivedAt: DateTime.now(), location: device));
    } on ApiException catch (e) {
      if (gen != _generation) return;
      device = device.withPlaceName(await placeFuture);
      if (gen != _generation) return;
      if (e.isOutsideCoverage) {
        _set(OutsideCoverage(e.message, location: device));
      } else if (e.isNetwork) {
        _set(NetworkError(e.message, location: device));
      } else {
        _set(PredictionUnavailable(e.message, code: e.code, location: device));
      }
    } catch (e) {
      if (gen != _generation) return;
      _set(PredictionUnavailable('Unexpected error: $e', code: 'unexpected', location: device));
    } finally {
      if (gen == _generation) {
        _ticker?.cancel();
        _ticker = null;
      }
    }
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> openLocationSettings() => _location.openLocationSettings();
  Future<void> openAppSettings() => _location.openAppSettings();

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
