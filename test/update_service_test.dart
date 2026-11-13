import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pm25_mobile_app/app/theme.dart';
import 'package:pm25_mobile_app/core/config.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_screen.dart';
import 'package:pm25_mobile_app/features/update/update_banner.dart';
import 'package:pm25_mobile_app/features/update/update_controller.dart';
import 'package:pm25_mobile_app/services/update_service.dart';

import 'fakes.dart';

class Metered implements ConnectivityGate {
  @override
  Future<bool> isUnmetered() async => false;
}

class ThrowingGate implements ConnectivityGate {
  @override
  Future<bool> isUnmetered() async => throw StateError('no connectivity plugin');
}

Map<String, dynamic> release({
  String tag = 'v0.2.0',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, dynamic>>? assets,
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/JimTheFatJam/pm25-mobile-app/releases/tag/$tag',
      'body': 'Fixes things.',
      'assets': assets ??
          [
            {'name': 'pm25-mobile-app-$tag.apk', 'browser_download_url': 'https://example.test/app-$tag.apk'},
          ],
    };

MockClient ok(Object body) => MockClient((req) async => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}));

UpdateService svc(MockClient client, {String current = '0.1.0', ConnectivityGate? gate}) => UpdateService(
      client: client,
      repo: 'JimTheFatJam/pm25-mobile-app',
      currentVersion: current,
      connectivity: gate ?? const AlwaysUnmetered(),
      timeout: const Duration(milliseconds: 200),
    );

void main() {
  group('version comparison', () {
    test('orders numerically, not lexically', () {
      expect(isNewer('0.10.0', '0.9.0'), isTrue, reason: '10 > 9');
      expect(isNewer('1.0.0', '0.99.99'), isTrue);
      expect(isNewer('0.1.0', '0.1.0'), isFalse);
      expect(isNewer('0.1.0', '0.2.0'), isFalse, reason: 'never offer a downgrade');
      expect(isNewer('1.2.10', '1.2.9'), isTrue);
    });

    test('tolerates v prefixes, build metadata and short versions', () {
      expect(isNewer('v0.2.0', '0.1.0'), isTrue);
      expect(isNewer('0.2.0+7', '0.2.0+3'), isFalse, reason: 'build metadata is not a version bump');
      expect(isNewer('0.2', '0.1.9'), isTrue);
      expect(normaliseVersion('v1.4.2+11'), '1.4.2');
      expect(normaliseVersion('not-a-version'), isEmpty);
    });

    test('a release outranks its own prerelease', () {
      expect(isNewer('1.0.0', '1.0.0-beta'), isTrue);
      expect(isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });

    test('unparseable versions never trigger an update', () {
      expect(isNewer('garbage', '0.1.0'), isFalse);
      expect(isNewer('0.2.0', 'garbage'), isFalse);
    });
  });

  group('release parsing', () {
    test('picks the .apk asset and keeps the release page', () {
      final info = parseRelease(release())!;
      expect(info.version, '0.2.0');
      expect(info.apkUrl, 'https://example.test/app-v0.2.0.apk');
      expect(info.downloadUrl, endsWith('.apk'));
    });

    test('falls back to the release page when there is no APK', () {
      final info = parseRelease(release(assets: [
        {'name': 'pm25-windows.zip', 'browser_download_url': 'https://example.test/win.zip'},
      ]))!;
      expect(info.apkUrl, isNull);
      expect(info.downloadUrl, contains('/releases/tag/'));
    });

    test('ignores drafts, prereleases and malformed payloads', () {
      expect(parseRelease(release(draft: true)), isNull);
      expect(parseRelease(release(prerelease: true)), isNull);
      expect(parseRelease({}), isNull);
      expect(parseRelease({'tag_name': ''}), isNull);
      expect(parseRelease({'tag_name': 'nightly'}), isNull);
      expect(parseRelease({'tag_name': 'v1.0.0', 'assets': 'not a list'})?.apkUrl, isNull);
    });
  });

  group('UpdateService.check', () {
    test('offers a newer release', () async {
      final info = await svc(ok(release())).check();
      expect(info, isNotNull);
      expect(info!.version, '0.2.0');
    });

    test('says nothing when already current or older', () async {
      expect(await svc(ok(release()), current: '0.2.0').check(), isNull);
      expect(await svc(ok(release(tag: 'v0.0.9'))).check(), isNull);
    });

    test('never checks on metered data', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonEncode(release()), 200);
      });
      expect(await svc(client, gate: Metered()).check(), isNull);
      expect(calls, 0, reason: 'a mobile data plan must not be spent on an update check');
    });

    test('is silent on HTTP errors, malformed bodies, timeouts and plugin failures', () async {
      for (final client in [
        MockClient((req) async => http.Response('nope', 404)),
        MockClient((req) async => http.Response('rate limited', 403)),
        MockClient((req) async => http.Response('not json {', 200)),
        MockClient((req) async => http.Response('[1,2,3]', 200)),
        MockClient((req) async => throw http.ClientException('offline')),
        MockClient((req) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response(jsonEncode(release()), 200);
        }),
      ]) {
        expect(await svc(client).check(), isNull);
      }
      expect(await svc(ok(release()), gate: ThrowingGate()).check(), isNull);
    });

    test('sends no credentials and hits the public releases endpoint', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode(release()), 200);
      });
      await svc(client).check();
      expect(seen.url.toString(), 'https://api.github.com/repos/JimTheFatJam/pm25-mobile-app/releases/latest');
      expect(seen.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('disabled repo performs no request', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonEncode(release()), 200);
      });
      final s = UpdateService(client: client, repo: '', currentVersion: '0.1.0', connectivity: const AlwaysUnmetered());
      expect(await s.check(), isNull);
      expect(calls, 0);
    });
  });

  group('UpdateController', () {
    test('checks once per launch and supports dismissal', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonEncode(release()), 200);
      });
      final c = UpdateController(service: svc(client));
      await c.checkOnce();
      await c.checkOnce();
      expect(calls, 1, reason: 'no repeated polling');
      expect(c.available, isNotNull);
      c.dismiss();
      expect(c.available, isNull, reason: 'dismissal hides it for the session');
    });
  });

  group('config', () {
    test('release builds target the public HTTPS deployment, debug stays local', () {
      expect(AppConfig.defaultBaseUrlFor(isAndroid: false, isRelease: true), 'https://pm25.dcism.org');
      expect(AppConfig.defaultBaseUrlFor(isAndroid: true, isRelease: true), 'https://pm25.dcism.org');
      expect(AppConfig.productionUrl, startsWith('https://'));
      expect(AppConfig.defaultBaseUrlFor(isAndroid: false), 'http://127.0.0.1:5050');
      expect(AppConfig.defaultBaseUrlFor(isAndroid: true), 'http://10.0.2.2:5050');
    });
  });

  group('banner in the screen', () {
    testWidgets('shows above the reading, downloads, and dismisses without touching the prediction', (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakePredictionApi(reading: sampleReading());
      final reading = ReadingController(locationService: FakeLocationService(cebu), api: api);
      final updates = UpdateController(service: svc(ok(release())));
      await updates.checkOnce();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ReadingScreen(controller: reading, updateController: updates),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      expect(find.text('Version 0.2.0 is ready to download.'), findsOneWidget);
      // The reading is still fully rendered beneath it.
      expect(find.text('11.7'), findsOneWidget);
      expect(find.text('MODERATE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
      expect(find.text('11.7'), findsOneWidget, reason: 'dismissing must not disturb the reading');
      expect(api.calls, 1, reason: 'the update flow never triggers a prediction request');
    });

    testWidgets('no banner when there is no update, and none without a controller', (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final reading = ReadingController(
          locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading()));
      final updates = UpdateController(service: svc(ok(release()), current: '9.9.9'));
      await updates.checkOnce();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: reading, updateController: updates)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);

      final r2 = ReadingController(locationService: FakeLocationService(cebu), api: FakePredictionApi(reading: sampleReading()));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReadingScreen(controller: r2)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('download opens the APK url', (tester) async {
      UpdateInfo? opened;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: UpdateBanner(
            info: parseRelease(release())!,
            onDismiss: () {},
            onDownload: (i) async => opened = i,
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('update-download')));
      await tester.pumpAndSettle();
      expect(opened?.downloadUrl, 'https://example.test/app-v0.2.0.apk');
    });
  });
}
