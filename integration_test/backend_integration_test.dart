// Integration test against the REAL Flask backend (run it first:
// `python backend/app.py` in pm25_web_app). The app's real HTTP client and
// real screen are exercised; the device location is injected (Cebu City /
// Davao) so the run is deterministic regardless of the host's location
// permission. Measures a cold and a warm request for the same cell.
//
//   flutter test integration_test/backend_integration_test.dart -d windows \
//       --dart-define=PM25_API_BASE_URL=http://127.0.0.1:5050
//   (the --dart-define is optional: on Windows the default is already 127.0.0.1:5050;
//    on the Android emulator the default is 10.0.2.2:5050)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pm25_mobile_app/app/theme.dart';
import 'package:pm25_mobile_app/core/config.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_screen.dart';
import 'package:pm25_mobile_app/features/reading/reading_state.dart';
import 'package:pm25_mobile_app/services/api_client.dart';
import 'package:pm25_mobile_app/services/location_service.dart';

class InjectedLocation implements LocationService {
  InjectedLocation(this.lat, this.lon);
  final double lat;
  final double lon;
  @override
  Future<LocationResult> getCurrentLocation() async => LocationResult(LocationStatus.ok, latitude: lat, longitude: lon);
  @override
  Future<bool> openLocationSettings() async => true;
  @override
  Future<bool> openAppSettings() async => true;
}

Future<Duration> waitForTerminal(WidgetTester tester, ReadingController c, {Duration timeout = const Duration(minutes: 4)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 250));
    final s = c.state;
    if (s is Success || s is OutsideCoverage || s is PredictionUnavailable || s is NetworkError || s is LocationFailed) {
      sw.stop();
      return sw.elapsed;
    }
  }
  throw TimeoutException('no terminal state within $timeout (last: ${c.state.runtimeType})');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real backend: cold then warm request for a Davao cell, full UI rendered', (tester) async {
    // A cell no earlier request in this backend session has touched: Davao City.
    final api = HttpPredictionApi();
    final controller = ReadingController(locationService: InjectedLocation(7.1907, 125.4553), api: api);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: controller)));

    final cold = await waitForTerminal(tester, controller);
    debugPrint('[integration] base URL: ${AppConfig.apiBaseUrl}');
    debugPrint('[integration] COLD request wall time: ${cold.inMilliseconds} ms -> state ${controller.state.runtimeType}');
    expect(controller.state, isA<Success>(), reason: 'cold request should succeed against the live backend');
    final reading = (controller.state as Success).reading;
    debugPrint('[integration] reading: ${reading.pm25} ${reading.units} as of ${reading.asOfLocalLabel}; '
        'category=${reading.classification?.category}; from_cache=${reading.fromCache}; '
        'missing=${reading.nMissingFeatures}/${reading.nFeatures}; factors=${reading.topFactors.map((f) => f.label).toList()}');
    expect(reading.fromCache, isFalse);
    expect(reading.classification, isNotNull);
    expect(reading.classification!.guidance, isNotEmpty);
    expect(reading.topFactors.length, 3);

    await tester.pumpAndSettle();
    expect(find.text('ESTIMATED PM2.5'), findsOneWidget);
    expect(find.text('Current PM2.5'), findsNothing);
    expect(find.textContaining('not a live measurement'), findsOneWidget);
    expect(find.text(reading.classification!.category.toUpperCase()), findsOneWidget);
    // The injected device fix is what is displayed (not the cell centroid / id).
    expect(find.text('7.1907° N, 125.4553° E'), findsOneWidget);
    expect(find.textContaining(reading.cellId), findsNothing);
    expect(find.byKey(const Key('guidance-text')), findsOneWidget);

    // Warm: refresh the same cell.
    await tester.tap(find.byKey(const Key('refresh-button')));
    final warm = await waitForTerminal(tester, controller);
    debugPrint('[integration] WARM request wall time: ${warm.inMilliseconds} ms -> state ${controller.state.runtimeType}');
    expect(controller.state, isA<Success>());
    final warmReading = (controller.state as Success).reading;
    expect(warmReading.fromCache, isTrue);
    expect(warmReading.pm25, reading.pm25);
    expect(warmReading.asOfUtc, reading.asOfUtc);
    expect(warm.inSeconds, lessThan(10), reason: 'warm (cached) requests must meet the 10 s target');
  });

  testWidgets('real backend: a point at sea is reported as outside coverage', (tester) async {
    final controller = ReadingController(locationService: InjectedLocation(12.0, 128.5), api: HttpPredictionApi());
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: controller)));
    final t = await waitForTerminal(tester, controller);
    debugPrint('[integration] outside-coverage response in ${t.inMilliseconds} ms');
    expect(controller.state, isA<OutsideCoverage>());
    await tester.pumpAndSettle();
    expect(find.text('Outside the supported area'), findsOneWidget);
  });

  testWidgets('real device location service reports a state (whatever this host allows)', (tester) async {
    final controller = ReadingController(locationService: GeolocatorLocationService(), api: HttpPredictionApi());
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: controller)));
    final sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 45)) {
      await tester.pump(const Duration(milliseconds: 250));
      final s = controller.state;
      if (s is! RequestingPermission && s is! Locating && s is! LoadingPrediction) break;
    }
    debugPrint('[integration] real location service -> ${controller.state.runtimeType}');
    expect(controller.state, isNot(isA<RequestingPermission>()));
  });
}

class TimeoutException implements Exception {
  TimeoutException(this.message);
  final String message;
  @override
  String toString() => 'TimeoutException: $message';
}
