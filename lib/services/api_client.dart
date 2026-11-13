import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../models/prediction_reading.dart';

/// A structured failure from the backend (its `error_code` values:
/// invalid_coordinates, outside_coverage, availability_pending,
/// availability_failed, no_supported_timestamp, prediction_failed,
/// model_unavailable) or from the transport (network / timeout).
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  bool get isOutsideCoverage => code == 'outside_coverage';
  bool get isNetwork => code == 'network' || code == 'timeout';
  bool get isUnavailable => code == 'availability_pending' ||
      code == 'availability_failed' ||
      code == 'no_supported_timestamp' ||
      code == 'model_unavailable' ||
      code == 'prediction_failed';

  @override
  String toString() => 'ApiException($code): $message';
}

/// Abstract so the controller can be tested with a fake.
abstract class PredictionApi {
  /// The single backend call the app needs (POST /api/mobile/prediction).
  Future<PredictionReading> fetchReading({required double latitude, required double longitude});
}

class HttpPredictionApi implements PredictionApi {
  HttpPredictionApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<PredictionReading> fetchReading({required double latitude, required double longitude}) async {
    final uri = Uri.parse('$_baseUrl/api/mobile/prediction');
    http.Response response;
    try {
      response = await _client
          .post(uri,
              headers: const {'Content-Type': 'application/json'},
              // Coordinates travel only in this request body (never in a
              // URL / query string) and are not retained by the app.
              body: jsonEncode({'lat': latitude, 'lon': longitude}))
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('timeout', 'The request took too long. Please try again.');
    } on SocketException catch (e) {
      throw ApiException('network', 'Could not reach the prediction service (${e.message}).');
    } on http.ClientException catch (e) {
      throw ApiException('network', 'Could not reach the prediction service (${e.message}).');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('bad_response', 'The prediction service returned an unreadable response (HTTP ${response.statusCode}).',
          statusCode: response.statusCode);
    }
    if (response.statusCode != 200 || json['status'] == 'error') {
      throw ApiException(
        json['error_code'] as String? ?? 'http_${response.statusCode}',
        json['message'] as String? ?? 'The prediction service returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    return PredictionReading.fromJson(json);
  }
}
