import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'location_service.dart';

/// Web-based reverse geocoding for the "Current location" locality label
/// (e.g. "Danao, Cebu", "Manila, Metro Manila"), implementing the app's
/// [PlaceNameResolver] seam. Display-only: the prediction request keeps
/// using the raw device coordinates and never waits on this.
///
/// Provider: any Nominatim-compatible `/reverse` endpoint (default: the
/// public OpenStreetMap service, see AppConfig). Works on every Flutter
/// platform because it is plain HTTPS -- no native geocoding plugin.
///
/// Public-Nominatim usage policy, and how it is met here:
///   * identifying User-Agent      -> AppConfig.geocoderUserAgent
///   * at most 1 request / second  -> [minInterval] gap between requests
///   * cache results client-side   -> [_cache] (bounded, per session)
///   * attribution                 -> [attribution], shown in the About card
///   * no bulk / periodic queries  -> called only when the app loads a
///                                    reading; never in the background
///
/// Privacy: the only data sent is the coordinate pair, rounded to
/// [precision] decimals (2 = about 1 km, the app's own grid resolution),
/// which is also the cache key, so small GPS movements neither re-query
/// nor reveal a finer position to the provider. Nothing is persisted.
class WebPlaceNameResolver implements PlaceNameResolver {
  WebPlaceNameResolver({
    http.Client? client,
    String? baseUrl,
    String? userAgent,
    Duration? timeout,
    this.minInterval = const Duration(seconds: 1),
    this.precision = 2,
    this.maxCacheEntries = 32,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.geocoderBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _userAgent = userAgent ?? AppConfig.geocoderUserAgent,
        _timeout = timeout ?? AppConfig.geocoderTimeout,
        _now = now ?? DateTime.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  final http.Client _client;
  final String _baseUrl;
  final String _userAgent;
  final Duration _timeout;
  final Duration minInterval;
  final int precision;
  final int maxCacheEntries;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// Rounded-coordinate key -> locality (null = looked up, nothing usable;
  /// cached too so a sea/no-data point is not re-queried).
  final Map<String, String?> _cache = <String, String?>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  DateTime? _lastRequestAt;

  /// Required by the OpenStreetMap data licence (ODbL).
  @override
  String? get attribution => 'Place names © OpenStreetMap contributors';

  int get cacheSize => _cache.length;

  String _key(double lat, double lon) => '${lat.toStringAsFixed(precision)},${lon.toStringAsFixed(precision)}';

  @override
  Future<String?> resolve(double latitude, double longitude) {
    if (_baseUrl.isEmpty) return Future.value(null);
    final key = _key(latitude, longitude);
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final pending = _inFlight[key];
    if (pending != null) return pending; // same place already being looked up
    final f = _lookup(key).then((name) {
      _remember(key, name);
      return name;
    }).whenComplete(() {
      _inFlight.remove(key); // block body: returning the removed Future here would make whenComplete wait on itself
    });
    _inFlight[key] = f;
    return f;
  }

  void _remember(String key, String? name) {
    if (_cache.length >= maxCacheEntries) _cache.remove(_cache.keys.first); // oldest first
    _cache[key] = name;
  }

  Future<String?> _lookup(String key) async {
    try {
      await _throttle();
      final parts = key.split(',');
      final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
        'lat': parts[0],
        'lon': parts[1],
        'format': 'jsonv2',
        'zoom': '10', // city / municipality level -- no streets or houses
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final response = await _client.get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'}).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map<String, dynamic> ? localityFromNominatim(body) : null;
    } catch (_) {
      return null; // timeout, transport, malformed JSON: label simply absent
    }
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = minInterval - _now().difference(last);
      if (wait > Duration.zero) await _delay(wait);
    }
    _lastRequestAt = _now();
  }
}

const _localityKeys = ['city', 'town', 'municipality', 'village'];
const _regionKeys = ['state', 'province', 'region', 'county'];

/// Extracts "locality, province-or-region" from a Nominatim reverse
/// response (`address` block). Verified against the live service for
/// Philippine points: component cities and municipalities carry the
/// province in `state` ("Danao, Cebu", "Tagum, Davao del Norte");
/// highly urbanised / independent cities have no province in OSM and fall
/// back to `region` ("Cebu City, Central Visayas", "Manila, Metro
/// Manila"). Streets, districts, postcodes and the country are ignored.
/// Returns null for an error body, a missing/unnamed locality, or any
/// unexpected shape.
String? localityFromNominatim(Map<String, dynamic> json) {
  if (json['error'] != null) return null;
  final address = json['address'];
  if (address is! Map) return null;
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = address[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final locality = pick(_localityKeys);
  if (locality == null) return null;
  final region = pick(_regionKeys);
  if (region == null || region.toLowerCase() == locality.toLowerCase()) return locality;
  return '$locality, $region';
}
