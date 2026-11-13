import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pm25_mobile_app/core/config.dart';
import 'package:pm25_mobile_app/features/reading/reading_controller.dart';
import 'package:pm25_mobile_app/features/reading/reading_state.dart';
import 'package:pm25_mobile_app/services/web_place_name_resolver.dart';

import 'fakes.dart';

/// Nominatim jsonv2 reverse bodies as observed live for Philippine points.
Map<String, dynamic> nominatim(Map<String, String> address, {String name = 'x'}) => {
      'place_id': 1,
      'osm_type': 'relation',
      'name': name,
      'display_name': address.values.join(', '),
      'address': address,
    };

const danao = {'city': 'Danao', 'state': 'Cebu', 'region': 'Central Visayas', 'postcode': '6004', 'country': 'Philippines', 'country_code': 'ph'};
const cebuCity = {'city': 'Cebu City', 'region': 'Central Visayas', 'country': 'Philippines', 'country_code': 'ph'};
const manila = {'suburb': 'Quiapo', 'city_district': 'Third District', 'city': 'Manila', 'state_district': 'Capital District', 'region': 'Metro Manila', 'postcode': '1001', 'country': 'Philippines'};
const davao = {'city_district': 'Calinan District', 'city': 'Davao City', 'region': 'Davao Region', 'postcode': '8000', 'country': 'Philippines'};

WebPlaceNameResolver resolver(MockClient client, {Duration? timeout, DateTime Function()? now, Future<void> Function(Duration)? delay, int maxCacheEntries = 32}) =>
    WebPlaceNameResolver(
      client: client,
      baseUrl: 'https://geocoder.test/',
      userAgent: 'pm25-test-agent/1.0',
      timeout: timeout,
      now: now ?? () => DateTime(2026, 9, 21, 12),
      delay: delay ?? (_) async {},
      maxCacheEntries: maxCacheEntries,
    );

http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('localityFromNominatim', () {
    test('component city / municipality: locality + province', () {
      expect(localityFromNominatim(nominatim(danao)), 'Danao, Cebu');
      expect(localityFromNominatim(nominatim({'town': 'Tagum', 'state': 'Davao del Norte', 'region': 'Davao Region'})), 'Tagum, Davao del Norte');
      expect(localityFromNominatim(nominatim({'municipality': 'Consolacion', 'state': 'Cebu'})), 'Consolacion, Cebu');
      expect(localityFromNominatim(nominatim({'village': 'Barangay X', 'county': 'Some County'})), 'Barangay X, Some County');
    });

    test('independent city without a province falls back to the region', () {
      expect(localityFromNominatim(nominatim(cebuCity)), 'Cebu City, Central Visayas');
      expect(localityFromNominatim(nominatim(manila)), 'Manila, Metro Manila');
      expect(localityFromNominatim(nominatim(davao)), 'Davao City, Davao Region');
    });

    test('never includes streets, districts, postcodes or the country', () {
      final s = localityFromNominatim(nominatim({...manila, 'road': 'Quezon Boulevard', 'house_number': '123'}))!;
      for (final bad in ['Quezon', '123', 'Quiapo', 'Third District', '1001', 'Philippines']) {
        expect(s.contains(bad), isFalse, reason: bad);
      }
    });

    test('missing or empty locality -> null; region only -> null; locality == region -> single', () {
      expect(localityFromNominatim(nominatim({'state': 'Cebu', 'country': 'Philippines'})), isNull);
      expect(localityFromNominatim(nominatim({'city': '   ', 'state': 'Cebu'})), isNull);
      expect(localityFromNominatim(nominatim({'city': 'Manila', 'region': 'manila'})), 'Manila');
      expect(localityFromNominatim(nominatim({'city': 'Cebu City'})), 'Cebu City');
    });

    test('error body and unexpected shapes -> null', () {
      expect(localityFromNominatim({'error': 'Unable to geocode'}), isNull);
      expect(localityFromNominatim({}), isNull);
      expect(localityFromNominatim({'address': 'not a map'}), isNull);
      expect(localityFromNominatim({'address': {'city': 42, 'state': ['x']}}), isNull);
      expect(localityFromNominatim({'address': {'city': 'Danao', 'state': 7}}), 'Danao');
    });
  });

  group('WebPlaceNameResolver', () {
    test('successful lookup: correct endpoint, params, rounded coordinates, identifying User-Agent', () async {
      late http.Request seen;
      final r = resolver(MockClient((req) async {
        seen = req;
        return ok(nominatim(danao));
      }));
      expect(await r.resolve(10.376049, 123.957012), 'Danao, Cebu');
      expect(seen.method, 'GET');
      expect(seen.url.origin, 'https://geocoder.test');
      expect(seen.url.path, '/reverse');
      expect(seen.url.queryParameters, {
        'lat': '10.38', // 2 decimals (~1 km): the locality-level key, not the raw fix
        'lon': '123.96',
        'format': 'jsonv2',
        'zoom': '10',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      expect(seen.headers['User-Agent'], 'pm25-test-agent/1.0');
      expect(seen.body, isEmpty);
    });

    test('caches results: nearby fixes reuse the answer, distinct places query again, negatives cached too', () async {
      var calls = 0;
      final r = resolver(MockClient((req) async {
        calls++;
        return req.url.queryParameters['lat'] == '12.00' ? ok({'error': 'Unable to geocode'}) : ok(nominatim(danao));
      }));
      expect(await r.resolve(10.3761, 123.9570), 'Danao, Cebu');
      expect(await r.resolve(10.3768, 123.9566), 'Danao, Cebu'); // ~80 m away: same rounded key
      expect(calls, 1);
      expect(await r.resolve(10.3157, 123.8854), 'Danao, Cebu'); // different key -> new request
      expect(calls, 2);
      expect(await r.resolve(12.0, 128.5), isNull); // sea: error body
      expect(await r.resolve(12.0, 128.5), isNull);
      expect(calls, 3, reason: 'a no-result answer is cached as well');
      expect(r.cacheSize, 3);
    });

    test('concurrent lookups of the same place share one request', () async {
      var calls = 0;
      final r = resolver(MockClient((req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return ok(nominatim(cebuCity));
      }));
      final results = await Future.wait([r.resolve(10.3157, 123.8854), r.resolve(10.3160, 123.8850), r.resolve(10.3157, 123.8854)]);
      expect(results, ['Cebu City, Central Visayas', 'Cebu City, Central Visayas', 'Cebu City, Central Visayas']);
      expect(calls, 1);
    });

    test('cache is bounded (oldest entry evicted)', () async {
      var calls = 0;
      final r = resolver(MockClient((req) async {
        calls++;
        return ok(nominatim(danao));
      }), maxCacheEntries: 2);
      await r.resolve(10.0, 120.0);
      await r.resolve(10.1, 120.0);
      await r.resolve(10.2, 120.0); // evicts (10.0, 120.0)
      expect(r.cacheSize, 2);
      await r.resolve(10.0, 120.0);
      expect(calls, 4);
    });

    test('throttles to at most one request per second (policy)', () async {
      var t = DateTime(2026, 9, 21, 12);
      final waits = <Duration>[];
      final r = resolver(
        MockClient((req) async => ok(nominatim(danao))),
        now: () => t,
        delay: (d) async {
          waits.add(d);
          t = t.add(d);
        },
      );
      await r.resolve(10.0, 120.0); // first: no wait
      t = t.add(const Duration(milliseconds: 300));
      await r.resolve(10.1, 120.0); // 300 ms later: must wait the remaining 700 ms
      t = t.add(const Duration(seconds: 5));
      await r.resolve(10.2, 120.0); // long after: no wait
      expect(waits, [const Duration(milliseconds: 700)]);
    });

    test('HTTP error, transport failure, malformed and non-object JSON -> null, never throws', () async {
      for (final client in [
        MockClient((req) async => http.Response('rate limited', 429)),
        MockClient((req) async => http.Response('<html>502</html>', 502)),
        MockClient((req) async => throw http.ClientException('connection refused')),
        MockClient((req) async => http.Response('not json {', 200)),
        MockClient((req) async => http.Response('[1,2,3]', 200)),
        MockClient((req) async => http.Response('"just a string"', 200)),
        MockClient((req) async => ok({'address': null})),
      ]) {
        expect(await resolver(client).resolve(10.0, 120.0), isNull);
      }
    });

    test('a slow provider times out -> null (short timeout)', () async {
      final r = resolver(
        MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return ok(nominatim(danao));
        }),
        timeout: const Duration(milliseconds: 50),
      );
      expect(await r.resolve(10.0, 120.0), isNull);
    });

    test('empty base URL (geocoder off) -> null without any request', () async {
      var calls = 0;
      final r = WebPlaceNameResolver(client: MockClient((req) async { calls++; return ok(nominatim(danao)); }), baseUrl: '');
      expect(await r.resolve(10.0, 120.0), isNull);
      expect(calls, 0);
    });

    test('carries the OpenStreetMap attribution', () {
      expect(resolver(MockClient((req) async => ok({}))).attribution, contains('OpenStreetMap'));
    });
  });

  group('integration with the reading flow', () {
    test('prediction still succeeds (raw coordinates sent) when the geocoder fails or times out', () async {
      for (final client in [
        MockClient((req) async => throw http.ClientException('dns failure')),
        MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return ok(nominatim(danao));
        }),
      ]) {
        final api = FakePredictionApi(reading: sampleReading());
        final c = ReadingController(
          locationService: FakeLocationService(cebu),
          api: api,
          placeNameResolver: resolver(client, timeout: const Duration(milliseconds: 30)),
        );
        await c.load();
        final s = c.state as Success;
        expect(s.reading.pm25, 11.7);
        expect(s.location!.placeName, isNull);
        expect(s.location!.coordinatesLabel, '10.3039° N, 123.9131° E');
        expect((api.lastLat, api.lastLon), (10.3039, 123.9131));
      }
    });

    test('successful geocode labels the fix; the backend still receives the exact coordinates', () async {
      late http.Request seen;
      final api = FakePredictionApi(reading: sampleReading());
      final c = ReadingController(
        locationService: FakeLocationService(cebu),
        api: api,
        placeNameResolver: resolver(MockClient((req) async {
          seen = req;
          return ok(nominatim(cebuCity));
        })),
      );
      await c.load();
      final s = c.state as Success;
      expect(s.location!.placeName, 'Cebu City, Central Visayas');
      expect((api.lastLat, api.lastLon), (10.3039, 123.9131));
      expect(seen.url.queryParameters['lat'], '10.30'); // the provider only ever sees the rounded pair
      expect(seen.url.queryParameters['lon'], '123.91');
      expect(c.placeAttribution, contains('OpenStreetMap'));
    });
  });

  group('configuration', () {
    test('defaults to the public Nominatim service with an identifying User-Agent', () {
      expect(AppConfig.geocoderEnabled, isTrue);
      expect(AppConfig.geocoderBaseUrl, 'https://nominatim.openstreetmap.org');
      expect(AppConfig.geocoderUserAgent, startsWith('pm25-air-quality-mobile/'));
      expect(AppConfig.geocoderUserAgent.toLowerCase(), isNot(contains('dart/')));
      expect(AppConfig.geocoderTimeout, lessThanOrEqualTo(const Duration(seconds: 5)));
    });
  });
}
