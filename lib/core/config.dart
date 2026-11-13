import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Build-time configuration.
///
/// Backend base URL, in priority order:
///   1. `--dart-define=PM25_API_BASE_URL=https://host` (SRS 3.4: production
///      must be HTTPS/TLS), which overrides everything;
///   2. otherwise a platform-aware development default for the LOCAL Flask
///      backend (`python run_app.py`, 127.0.0.1:5050):
///        - Android emulator: `http://10.0.2.2:5050` -- the emulator's alias
///          for its host machine (cleartext permitted for that one host only,
///          see android/.../network_security_config.xml);
///        - everything else (Windows/macOS/Linux desktop, iOS simulator):
///          `http://127.0.0.1:5050`, i.e. the same machine.
///      10.0.2.2 is NOT routable outside the Android emulator: using it on
///      Windows makes every request hang until Winsock's connect timeout
///      ("The semaphore timeout period has expired").
class AppConfig {
  AppConfig._();

  static const String _overrideBaseUrl = String.fromEnvironment('PM25_API_BASE_URL', defaultValue: '');

  /// The public deployment. Release builds talk to this unless overridden.
  static const String productionUrl = 'https://pm25.dcism.org';
  static const String androidEmulatorHostUrl = 'http://10.0.2.2:5050';
  static const String localHostUrl = 'http://127.0.0.1:5050';

  static String get apiBaseUrl {
    if (_overrideBaseUrl.isNotEmpty) return _overrideBaseUrl;
    return defaultBaseUrlFor(isAndroid: !kIsWeb && Platform.isAndroid, isRelease: kReleaseMode);
  }

  /// Pure selection rule (unit-tested).
  ///
  /// A RELEASE build is something a user installs, so it must reach the real
  /// service over HTTPS -- never a loopback address that only exists on a
  /// developer's machine. Debug and profile builds keep the local defaults so
  /// `flutter run` against `python run_app.py` works exactly as before.
  static String defaultBaseUrlFor({required bool isAndroid, bool isRelease = false}) {
    if (isRelease) return productionUrl;
    return isAndroid ? androidEmulatorHostUrl : localHostUrl;
  }

  /// This build's version, for the update check. CI injects the release tag;
  /// a hand-built binary reports the fallback, which simply means the update
  /// check never considers itself out of date.
  static const String appVersion = String.fromEnvironment('PM25_APP_VERSION', defaultValue: '0.1.0');

  // ---------------------------------------------------------------------
  // Auto-update (see services/update_service.dart)
  // ---------------------------------------------------------------------
  // The app is distributed as an APK from GitHub Releases rather than a
  // store, so it checks for a newer release itself. Public repository, so
  // the GitHub API is reachable without a token -- nothing secret ships in
  // the binary.
  //
  //   --dart-define=PM25_UPDATE_REPO=owner/name   (the literal value `off`
  //   disables the check entirely)
  static const String _updateRepoOverride = String.fromEnvironment('PM25_UPDATE_REPO', defaultValue: '');
  static const String defaultUpdateRepo = 'JimTheFatJam/pm25-mobile-app';

  /// Empty when update checking is disabled.
  static String get updateRepo {
    if (_updateRepoOverride.toLowerCase() == 'off') return '';
    return _updateRepoOverride.isNotEmpty ? _updateRepoOverride : defaultUpdateRepo;
  }

  static bool get updateCheckEnabled => updateRepo.isNotEmpty;

  /// Short: an update check must never delay the reading.
  static const Duration updateCheckTimeout = Duration(seconds: 6);

  /// A cold request needs live Earth Engine retrieval on the backend
  /// (measured 15-25 s); warm (cached) requests return in well under a
  /// second. The request itself is allowed to take much longer than the
  /// SRS's 10 s target; the UI explains the wait past [slowThreshold].
  static const Duration requestTimeout = Duration(seconds: 180);
  static const Duration slowThreshold = Duration(seconds: 10);

  // ---------------------------------------------------------------------
  // Reverse geocoding (display-only locality label, see
  // services/web_place_name_resolver.dart). Provider configuration lives
  // here, not in the UI, so it can be pointed elsewhere without touching
  // the screen or the prediction flow.
  //
  //   --dart-define=PM25_GEOCODER_BASE_URL=https://your-nominatim.example
  //       any Nominatim-compatible /reverse endpoint (own instance, proxy);
  //       the literal value `off` disables reverse geocoding entirely.
  //   --dart-define=PM25_GEOCODER_CONTACT=you@example.org
  //       appended to the User-Agent, as the public Nominatim usage policy
  //       asks (an identifying agent with a way to reach the operator).
  //
  // Default: the public OpenStreetMap Nominatim service. Its policy
  // (https://operations.osmfoundation.org/policies/nominatim/) requires a
  // descriptive User-Agent, <= 1 request/second, client-side caching and
  // "(c) OpenStreetMap contributors" attribution -- all handled by
  // WebPlaceNameResolver / the About card.
  // ---------------------------------------------------------------------
  static const String _geocoderOverride = String.fromEnvironment('PM25_GEOCODER_BASE_URL', defaultValue: '');
  static const String publicNominatimUrl = 'https://nominatim.openstreetmap.org';
  static const String geocoderContact = String.fromEnvironment('PM25_GEOCODER_CONTACT', defaultValue: '');

  /// Empty when reverse geocoding is disabled (`PM25_GEOCODER_BASE_URL=off`).
  static String get geocoderBaseUrl {
    if (_geocoderOverride.toLowerCase() == 'off') return '';
    return _geocoderOverride.isNotEmpty ? _geocoderOverride : publicNominatimUrl;
  }

  static bool get geocoderEnabled => geocoderBaseUrl.isNotEmpty;

  /// Identifies this app to the provider (policy requirement; a bare
  /// library default such as "Dart/3.x" is explicitly not acceptable).
  static String get geocoderUserAgent =>
      'pm25-air-quality-mobile/0.1 (thesis PM2.5 prediction app; reverse geocoding for a locality label'
      '${geocoderContact.isEmpty ? '' : '; contact: $geocoderContact'})';

  /// Short: the label is optional and must never hold up the reading.
  static const Duration geocoderTimeout = Duration(seconds: 4);
}
