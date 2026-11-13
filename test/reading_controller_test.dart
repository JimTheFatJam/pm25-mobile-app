import 'package:flutter_test/flutter_test.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_state.dart';
import 'package:pm25_mobile_app/models/prediction_reading.dart';
import 'package:pm25_mobile_app/services/api_client.dart';
import 'package:pm25_mobile_app/services/location_service.dart';

import 'fakes.dart';

void main() {
  group('location states', () {
    for (final (status, matcher) in [
      (LocationStatus.servicesDisabled, isA<LocationServicesDisabled>()),
      (LocationStatus.permissionDenied, isA<PermissionDenied>()),
      (LocationStatus.permissionDeniedForever, isA<PermissionDeniedForever>()),
      (LocationStatus.failed, isA<LocationFailed>()),
    ]) {
      test('$status -> matching state, no API call', () async {
        final api = FakePredictionApi(reading: sampleReading());
        final c = ReadingController(locationService: FakeLocationService(LocationResult(status, error: 'x')), api: api);
        await c.load();
        expect(c.state, matcher);
        expect(api.calls, 0);
      });
    }

    test('settings shortcuts delegate to the location service', () async {
      final loc = FakeLocationService(const LocationResult(LocationStatus.servicesDisabled));
      final c = ReadingController(locationService: loc, api: FakePredictionApi(reading: sampleReading()));
      await c.openLocationSettings();
      await c.openAppSettings();
      expect(loc.settingsOpened, 1);
      expect(loc.appSettingsOpened, 1);
    });
  });

  group('prediction flow', () {
    test('success renders reading and passes the coordinates once (not stored)', () async {
      final api = FakePredictionApi(reading: sampleReading());
      final c = ReadingController(locationService: FakeLocationService(cebu), api: api);
      final states = <ReadingState>[];
      c.addListener(() => states.add(c.state));
      await c.load();
      expect(c.state, isA<Success>());
      final s = c.state as Success;
      expect(s.reading.pm25, 11.7);
      expect(s.reading.classification!.category, 'Moderate');
      expect(s.reading.topFactors.length, 3);
      expect(api.lastLat, 10.3039);
      expect(api.lastLon, 123.9131);
      expect(states.whereType<RequestingPermission>().length, 1);
      expect(states.whereType<LoadingPrediction>().isNotEmpty, true);
    });

    test('device fix is carried in the state; locality is display-only and never alters the request', () async {
      final api = FakePredictionApi(reading: sampleReading());
      final places = FakePlaceNameResolver('Cebu City, Cebu');
      final c = ReadingController(locationService: FakeLocationService(cebu), api: api, placeNameResolver: places);
      await c.load();
      final s = c.state as Success;
      expect(s.location, isNotNull);
      expect(s.location!.latitude, 10.3039);
      expect(s.location!.longitude, 123.9131);
      expect(s.location!.placeName, 'Cebu City, Cebu');
      expect(s.location!.coordinatesLabel, '10.3039° N, 123.9131° E');
      // Same raw coordinates went to the backend and to the resolver.
      expect((api.lastLat, api.lastLon), (10.3039, 123.9131));
      expect((places.lastLat, places.lastLon), (10.3039, 123.9131));
    });

    test('a failing locality resolver does not affect the reading', () async {
      final api = FakePredictionApi(reading: sampleReading());
      final c = ReadingController(
          locationService: FakeLocationService(cebu), api: api, placeNameResolver: FakePlaceNameResolver(null, throws: true));
      await c.load();
      final s = c.state as Success;
      expect(s.reading.pm25, 11.7);
      expect(s.location!.placeName, isNull);
      expect(s.location!.coordinatesLabel, '10.3039° N, 123.9131° E');
      expect(api.lastLat, 10.3039);
    });

    test('coordinate label uses hemisphere letters and 4 decimals', () {
      expect(formatCoordinates(10.3157, 123.8854), '10.3157° N, 123.8854° E');
      expect(formatCoordinates(-33.86882, -151.20929), '33.8688° S, 151.2093° W');
      expect(formatCoordinates(0, 0), '0.0000° N, 0.0000° E');
    });

    test('outside coverage', () async {
      final api = FakePredictionApi(
          error: const ApiException('outside_coverage', 'This location is outside the supported prediction grid.', statusCode: 404));
      final c = ReadingController(locationService: FakeLocationService(cebu), api: api);
      await c.load();
      expect(c.state, isA<OutsideCoverage>());
      expect((c.state as OutsideCoverage).message, contains('outside'));
    });

    test('availability pending / failed / model unavailable -> PredictionUnavailable', () async {
      for (final code in ['availability_pending', 'availability_failed', 'model_unavailable', 'prediction_failed', 'no_supported_timestamp']) {
        final c = ReadingController(
            locationService: FakeLocationService(cebu), api: FakePredictionApi(error: ApiException(code, 'msg $code', statusCode: 503)));
        await c.load();
        expect(c.state, isA<PredictionUnavailable>(), reason: code);
        expect((c.state as PredictionUnavailable).code, code);
      }
    });

    test('network / timeout -> NetworkError', () async {
      for (final code in ['network', 'timeout']) {
        final c = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(error: ApiException(code, 'down')));
        await c.load();
        expect(c.state, isA<NetworkError>(), reason: code);
      }
    });

    test('reading with status unavailable -> PredictionUnavailable', () async {
      final c = ReadingController(
          locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading(pm25: null, status: 'unavailable')));
      await c.load();
      expect(c.state, isA<PredictionUnavailable>());
    });

    test('unexpected exception -> PredictionUnavailable, not a crash', () async {
      final c = ReadingController(locationService: FakeLocationService(cebu), api: _ThrowingApi());
      await c.load();
      expect(c.state, isA<PredictionUnavailable>());
    });
  });

  group('slow requests and refresh', () {
    test('LoadingPrediction flips to slow after the threshold and clears on completion', () async {
      final api = FakePredictionApi(reading: sampleReading(), delay: const Duration(milliseconds: 250));
      final c = ReadingController(
        locationService: FakeLocationService(cebu),
        api: api,
        slowThreshold: const Duration(milliseconds: 100),
        tickInterval: const Duration(milliseconds: 30),
      );
      final sawSlow = <bool>[];
      c.addListener(() {
        final s = c.state;
        if (s is LoadingPrediction) sawSlow.add(s.slow);
      });
      await c.load();
      expect(sawSlow.first, false);
      expect(sawSlow.contains(true), true);
      expect(c.state, isA<Success>());
    });

    test('refresh keeps the previous reading while loading and re-acquires location', () async {
      final loc = FakeLocationService(cebu);
      final api = FakePredictionApi(reading: sampleReading(), delay: const Duration(milliseconds: 60));
      final c = ReadingController(locationService: loc, api: api, tickInterval: const Duration(milliseconds: 20));
      await c.load();
      expect(c.state, isA<Success>());
      LoadingPrediction? loading;
      c.addListener(() {
        if (c.state is LoadingPrediction) loading = c.state as LoadingPrediction;
      });
      await c.refresh();
      expect(loading?.previous, isNotNull);
      expect(loc.calls, 2);
      expect(api.calls, 2);
      expect(c.state, isA<Success>());
    });

    test('a newer load supersedes an older in-flight one', () async {
      final api = FakePredictionApi(reading: sampleReading(), delay: const Duration(milliseconds: 120));
      final c = ReadingController(locationService: FakeLocationService(cebu), api: api, tickInterval: const Duration(milliseconds: 20));
      final first = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      api.reading = sampleReading(pm25: 42.0);
      final second = c.load();
      await Future.wait([first, second]);
      expect((c.state as Success).reading.pm25, 42.0);
    });
  });
}

class _ThrowingApi extends FakePredictionApi {
  @override
  Future<PredictionReading> fetchReading({required double latitude, required double longitude}) async => throw StateError('boom');
}
