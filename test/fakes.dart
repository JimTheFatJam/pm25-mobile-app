import 'dart:async';

import 'package:pm25_mobile_app/models/prediction_reading.dart';
import 'package:pm25_mobile_app/services/api_client.dart';
import 'package:pm25_mobile_app/services/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService(this.result);
  LocationResult result;
  int calls = 0;
  int settingsOpened = 0;
  int appSettingsOpened = 0;

  @override
  Future<LocationResult> getCurrentLocation() async {
    calls++;
    return result;
  }

  @override
  Future<bool> openLocationSettings() async { settingsOpened++; return true; }

  @override
  Future<bool> openAppSettings() async { appSettingsOpened++; return true; }
}

class FakePredictionApi implements PredictionApi {
  FakePredictionApi({this.reading, this.error, this.delay = Duration.zero});
  PredictionReading? reading;
  ApiException? error;
  Duration delay;
  int calls = 0;
  double? lastLat;
  double? lastLon;

  @override
  Future<PredictionReading> fetchReading({required double latitude, required double longitude}) async {
    calls++;
    lastLat = latitude;
    lastLon = longitude;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return reading!;
  }
}

class FakePlaceNameResolver implements PlaceNameResolver {
  FakePlaceNameResolver(this.name, {this.throws = false});
  String? name;
  bool throws;
  double? lastLat;
  double? lastLon;

  @override
  Future<String?> resolve(double latitude, double longitude) async {
    lastLat = latitude;
    lastLon = longitude;
    if (throws) throw StateError('geocoder down');
    return name;
  }

  @override
  String? get attribution => 'Place names © Test Provider';
}

const cebu = LocationResult(LocationStatus.ok, latitude: 10.3039, longitude: 123.9131);

Map<String, dynamic> sampleJson({double? pm25 = 11.7, String status = 'ok', bool explanation = true}) => {
      'status': status,
      'cell_id': 'PHFULL_-122_2895',
      'as_of_utc': '2026-09-10T15:00:00+00:00',
      'as_of_local': '2026-09-10T23:00:00+08:00',
      'as_of_local_label': 'Sep 10, 2026, 11:00 PM PHT',
      'timestamp_strategy': 'strict_same_timestamp',
      'pm25_ugm3': pm25,
      'units': 'µg/m³',
      'classification': pm25 == null
          ? null
          : {
              'scheme_id': 'us_epa_aqi_pm25_24h',
              'scheme_name': 'US EPA PM2.5 AQI (24-hour)',
              'category': 'Moderate',
              'color': '#ffff00',
              'interpretation': 'Air quality is acceptable. However, there may be a risk for some people.',
              'guidance': 'Unusually sensitive people: consider reducing prolonged or heavy outdoor exertion.',
              'basis_note': 'Applied to a single modelled hourly prediction ... not an official 24-hour determination.',
            },
      'data_note': 'Modelled from satellite and weather data that may lag real time by several days. This is an estimate, not a live measurement.',
      'n_missing_features': 33,
      'n_features': 157,
      'explanation': {
        'available': explanation,
        'top_factors': explanation
            ? [
                {'feature': 'population_neighborhood_mean', 'label': 'Population count (5 km neighborhood mean)', 'direction': 'higher', 'shap_log': 0.07},
                {'feature': 'hour_sin', 'label': 'Hour of day (sine encoding)', 'direction': 'lower', 'shap_log': -0.05},
                {'feature': 'population_local', 'label': 'Population count (at cell)', 'direction': 'higher', 'shap_log': 0.04},
              ]
            : [],
        'note': 'These factors describe what pushed the model\'s estimate higher or lower (model attribution), not what caused air pollution.',
        'error': null,
      },
      'computed_at_utc': '2026-09-21T02:00:00+00:00',
      'compute_seconds': 16.6,
      'from_cache': false,
      'request_seconds': 16.7,
      'staleness_hours': 250.0,
      'message': pm25 == null ? 'The model could not produce a value for this location and time.' : null,
    };

PredictionReading sampleReading({double? pm25 = 11.7, String status = 'ok', bool explanation = true}) =>
    PredictionReading.fromJson(sampleJson(pm25: pm25, status: status, explanation: explanation));
