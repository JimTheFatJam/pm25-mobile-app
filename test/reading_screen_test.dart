import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm25_mobile_app/app/theme.dart';
import 'package:pm25_mobile_app/app/theme_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_screen.dart';
import 'package:pm25_mobile_app/services/api_client.dart';
import 'package:pm25_mobile_app/services/location_service.dart';

import 'fakes.dart';

Widget app(ReadingController c) => MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: c));

/// A tall phone-like viewport so every card of the (lazy) ListView is built.
Future<void> pumpTall(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
}

void main() {
  testWidgets('successful reading renders headline, category, guidance, note, top-3 and refresh', (tester) async {
    final api = FakePredictionApi(reading: sampleReading());
    final c = ReadingController(locationService: FakeLocationService(cebu), api: api);
    await pumpTall(tester, app(c));
    await tester.pumpAndSettle();

    expect(find.text('PM2.5 Air Quality'), findsOneWidget);
    expect(find.text('ESTIMATED PM2.5'), findsOneWidget);
    expect(find.text('as of'), findsOneWidget);
    expect(find.byKey(const Key('as-of-label')), findsOneWidget);
    expect(find.text('Sep 10, 2026, 11:00 PM PHT'), findsOneWidget); // hero card
    expect(find.textContaining('Estimate for: Sep 10, 2026, 11:00 PM PHT', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('pm25-value')), findsOneWidget);
    expect(find.text('11.7'), findsOneWidget);
    expect(find.text('µg/m³'), findsOneWidget);
    expect(find.text('MODERATE'), findsOneWidget); // category badge, capitals
    expect(find.byKey(const Key('guidance-text')), findsOneWidget);
    expect(find.textContaining('not a live measurement'), findsOneWidget);
    expect(find.textContaining('10 days behind real time'), findsOneWidget);
    expect(find.textContaining('33 of 157 model inputs missing'), findsOneWidget);
    expect(find.text('Why this prediction?'), findsOneWidget);
    expect(find.text('Pushed the estimate higher'), findsNWidgets(2));
    expect(find.text('Pushed the estimate lower'), findsOneWidget);
    expect(find.text('Population count (5 km neighborhood mean)'), findsOneWidget);
    expect(find.text('Recommended guidance'), findsOneWidget);
    expect(find.textContaining('Last updated', findRichText: true), findsOneWidget);
    expect(find.textContaining('not what caused air pollution'), findsOneWidget);
    expect(find.text('Current PM2.5'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('CURRENT LOCATION'), findsOneWidget);
    // The device's own fix, 4 decimals -- never the grid cell id / centroid.
    expect(find.text('10.3039° N, 123.9131° E'), findsOneWidget);
    expect(find.byKey(const Key('location-place')), findsNothing); // no resolver -> coordinates only
    expect(find.textContaining('Grid cell'), findsNothing);
    expect(find.textContaining('PHFULL'), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('slow loading state explains the cold request', (tester) async {
    final api = FakePredictionApi(reading: sampleReading(), delay: const Duration(seconds: 3));
    final c = ReadingController(
        locationService: FakeLocationService(cebu),
        api: api,
        slowThreshold: const Duration(seconds: 1),
        tickInterval: const Duration(milliseconds: 200));
    await pumpTall(tester, app(c));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('loading-card')), findsOneWidget);
    expect(find.textContaining('Estimating PM2.5'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(); // rebuild after the ticker's notifyListeners
    expect(find.textContaining('Still working'), findsOneWidget);
    expect(find.textContaining('retrieve satellite and weather data'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('11.7'), findsOneWidget);
  });

  testWidgets('permission denied / services disabled / outside coverage / network / unavailable states', (tester) async {
    for (final (loc, err, expectText) in [
      (const LocationResult(LocationStatus.permissionDenied), null, 'Location permission needed'),
      (const LocationResult(LocationStatus.permissionDeniedForever), null, 'Location permission is blocked'),
      (const LocationResult(LocationStatus.servicesDisabled), null, 'Location services are off'),
      (cebu, const ApiException('outside_coverage', 'This location is outside the supported prediction grid.'), 'Outside the supported area'),
      (cebu, const ApiException('network', 'Could not reach the prediction service.'), 'Cannot reach the prediction service'),
      (cebu, const ApiException('availability_pending', 'still determining'), 'Estimate unavailable'),
    ]) {
      final c = ReadingController(locationService: FakeLocationService(loc), api: FakePredictionApi(reading: sampleReading(), error: err));
      await pumpTall(tester, app(c));
      await tester.pumpAndSettle();
      expect(find.text(expectText), findsOneWidget, reason: expectText);
      expect(find.text('Try again'), findsOneWidget, reason: expectText);
    }
  });

  testWidgets('location card shows locality above the coordinates when a resolver provides one', (tester) async {
    final api = FakePredictionApi(reading: sampleReading());
    final c = ReadingController(
        locationService: FakeLocationService(cebu), api: api, placeNameResolver: FakePlaceNameResolver('Cebu City, Cebu'));
    await pumpTall(tester, app(c));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-place')), findsOneWidget);
    expect(find.text('Cebu City, Cebu'), findsOneWidget);
    expect(find.text('10.3039° N, 123.9131° E'), findsOneWidget);
    // The request still carried the raw device coordinates, not the locality.
    expect(api.lastLat, 10.3039);
    expect(api.lastLon, 123.9131);
    // Provider attribution appears (unobtrusively, in the About card) only when a name is shown.
    expect(find.byKey(const Key('place-attribution')), findsOneWidget);
    expect(find.text('Place names © Test Provider'), findsOneWidget);
  });

  testWidgets('no attribution line when no place name is displayed', (tester) async {
    final c = ReadingController(
        locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading()), placeNameResolver: FakePlaceNameResolver(null));
    await pumpTall(tester, app(c));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-attribution')), findsNothing);
  });

  testWidgets('coordinates stay visible in the outside-coverage and network-error states', (tester) async {
    for (final err in [
      const ApiException('outside_coverage', 'This location is outside the supported prediction grid.'),
      const ApiException('network', 'Could not reach the prediction service.'),
    ]) {
      final c = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(error: err));
      await pumpTall(tester, app(c));
      await tester.pumpAndSettle();
      expect(find.text('10.3039° N, 123.9131° E'), findsOneWidget, reason: err.code);
    }
  });

  testWidgets('header title is centred on the screen and clear of the actions', (tester) async {
    for (final width in [1080.0, 420.0, 320.0]) {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final c = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading()));
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: ReadingScreen(controller: c, themeController: ThemeController(initial: ThemeMode.light))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $width');
      final title = tester.getRect(find.text('PM2.5 Air Quality'));
      final toggle = tester.getRect(find.byKey(const Key('theme-toggle')));
      expect(title.right, lessThanOrEqualTo(toggle.left), reason: 'title collides with the toggle at $width');
      if (width >= 400) {
        expect((title.center.dx - width / 2).abs(), lessThan(1.0), reason: 'title not centred at $width');
      }
    }
  });

  testWidgets('explanation unavailable shows a plain note instead of factors', (tester) async {
    final c = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading(explanation: false)));
    await pumpTall(tester, app(c));
    await tester.pumpAndSettle();
    expect(find.textContaining('An explanation is not available'), findsOneWidget);
  });
}
