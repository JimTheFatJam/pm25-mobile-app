import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pm25_mobile_app/models/prediction_reading.dart';
import 'package:pm25_mobile_app/services/api_client.dart';

import 'fakes.dart';

void main() {
  group('PredictionReading.fromJson', () {
    test('parses the backend payload', () {
      final r = PredictionReading.fromJson(sampleJson());
      expect(r.hasValue, true);
      expect(r.pm25, 11.7);
      expect(r.asOfLocalLabel, 'Sep 10, 2026, 11:00 PM PHT');
      expect(r.asOfUtc, DateTime.parse('2026-09-10T15:00:00+00:00'));
      expect(r.stalenessDays, 10);
      expect(r.classification!.guidance, isNotEmpty);
      expect(r.topFactors.map((f) => f.pushedHigher).toList(), [true, false, true]);
      expect(r.nMissingFeatures, 33);
    });

    test('tolerates missing optional fields', () {
      final r = PredictionReading.fromJson({'status': 'ok', 'pm25_ugm3': 3});
      expect(r.hasValue, true);
      expect(r.classification, isNull);
      expect(r.topFactors, isEmpty);
      expect(r.stalenessDays, isNull);
    });

    test('unavailable reading has no value', () {
      expect(PredictionReading.fromJson(sampleJson(pm25: null, status: 'unavailable')).hasValue, false);
    });
  });

  group('HttpPredictionApi', () {
    HttpPredictionApi api(http.Client client) => HttpPredictionApi(client: client, baseUrl: 'http://backend');

    test('posts lat/lon as JSON body (never in the URL) and parses success', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode(sampleJson()), 200, headers: {'content-type': 'application/json'});
      });
      final r = await api(client).fetchReading(latitude: 10.3039, longitude: 123.9131);
      expect(seen.url.toString(), 'http://backend/api/mobile/prediction');
      expect(seen.url.query, isEmpty);
      expect(jsonDecode(seen.body), {'lat': 10.3039, 'lon': 123.9131});
      expect(r.pm25, 11.7);
    });

    test('maps backend error codes', () async {
      final client = MockClient((req) async =>
          http.Response(jsonEncode({'status': 'error', 'error_code': 'outside_coverage', 'message': 'nope'}), 404));
      expect(
          () => api(client).fetchReading(latitude: 0, longitude: 0),
          throwsA(isA<ApiException>()
              .having((e) => e.isOutsideCoverage, 'outside', true)
              .having((e) => e.statusCode, 'status', 404)));
    });

    test('non-JSON response is a bad_response error', () async {
      final client = MockClient((req) async => http.Response('<html>502</html>', 502));
      expect(() => api(client).fetchReading(latitude: 0, longitude: 0),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_response')));
    });

    test('transport failure is a network error', () async {
      final client = MockClient((req) async => throw http.ClientException('connection refused'));
      expect(() => api(client).fetchReading(latitude: 0, longitude: 0),
          throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
    });
  });
}
