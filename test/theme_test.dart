import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm25_mobile_app/app/theme.dart';
import 'package:pm25_mobile_app/app/theme_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_screen.dart';
import 'package:pm25_mobile_app/features/reading/reading_state.dart';
import 'package:pm25_mobile_app/models/prediction_reading.dart';

import 'fakes.dart';

Widget themedApp(ReadingController c, ThemeController t) => ListenableBuilder(
      listenable: t,
      builder: (_, _) => MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: t.mode,
        home: ReadingScreen(controller: c, themeController: t),
      ),
    );

Brightness brightnessOf(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold))).brightness;

void main() {
  test('ThemeController toggles between light and dark', () {
    final t = ThemeController(initial: ThemeMode.light);
    expect(t.mode, ThemeMode.light);
    t.setMode(ThemeMode.dark);
    expect(t.mode, ThemeMode.dark);
    var notified = 0;
    t.addListener(() => notified++);
    t.setMode(ThemeMode.dark); // no-op
    expect(notified, 0);
    t.setMode(ThemeMode.light);
    expect(notified, 1);
  });

  test('both themes carry the AppColors extension and readable contrast', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      final theme = buildTheme(b);
      expect(theme.extension<AppColors>(), isNotNull);
      expect(contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThan(7));
      expect(contrastRatio(theme.app.muted, theme.colorScheme.surface), greaterThan(4.0));
      // EPA yellow becomes readable on either surface
      expect(contrastRatio(readableOn(const Color(0xFFFFFF00), theme.colorScheme.surface), theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5));
      // EPA "Hazardous" maroon becomes readable on the dark surface too
      expect(contrastRatio(readableOn(const Color(0xFF7E0023), theme.colorScheme.surface), theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('header toggle switches the whole app between light and dark without touching the reading', (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = FakePredictionApi(reading: sampleReading());
    final c = ReadingController(locationService: FakeLocationService(cebu), api: api);
    final t = ThemeController(initial: ThemeMode.light);
    await tester.pumpWidget(themedApp(c, t));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.text('11.7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();
    expect(t.mode, ThemeMode.dark);
    expect(brightnessOf(tester), Brightness.dark);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    // prediction untouched: same reading, no new request
    expect(api.calls, 1);
    expect(c.state, isA<Success>());
    expect(find.text('11.7'), findsOneWidget);
    expect(find.text('MODERATE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
    expect(api.calls, 1);
  });

  testWidgets('no toggle is shown when no ThemeController is supplied', (tester) async {
    final c = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading()));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-toggle')), findsNothing);
  });

  testWidgets('long labels, a huge value and a narrow width do not overflow (both themes, large text)', (tester) async {
    tester.view.physicalSize = const Size(320, 3600); // very narrow phone
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final json = sampleJson();
    (json['explanation'] as Map<String, dynamic>)['top_factors'] = [
      {
        'feature': 'x',
        'label': 'A very very long human readable feature label that certainly wraps across several lines on a phone',
        'direction': 'higher',
        'shap_log': 0.9,
      },
      {'feature': 'y', 'label': 'Another long label pushing lower', 'direction': 'lower', 'shap_log': -0.2},
    ];
    (json['classification'] as Map<String, dynamic>)['guidance'] = 'Guidance text that goes on and on. ' * 12;
    (json['classification'] as Map<String, dynamic>)['category'] = 'Unhealthy for Sensitive Groups';
    json['pm25_ugm3'] = 1234.5;
    final reading = PredictionReading.fromJson(json);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final c = ReadingController(
          locationService: FakeLocationService(cebu),
          api: FakePredictionApi(reading: reading),
          placeNameResolver: FakePlaceNameResolver('Municipality of a Very Long Name, Province of an Even Longer Name'));
      await tester.pumpWidget(themedApp(c, ThemeController(initial: mode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow in $mode'); // no RenderFlex overflow
      expect(find.text('1234.5'), findsOneWidget);
      expect(find.text('UNHEALTHY FOR SENSITIVE GROUPS'), findsOneWidget);
      expect(find.text('10.3039° N, 123.9131° E'), findsOneWidget);
    }
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'overflow at 1.6x text scale');
  });
}
