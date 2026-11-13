import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// A newer release than the one running.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.tagName, required this.releaseUrl, this.apkUrl, this.notes = ''});

  /// Normalised version, no leading "v" (e.g. "0.2.0").
  final String version;
  final String tagName;

  /// The release page -- always present, used when there is no APK asset.
  final String releaseUrl;

  /// Direct download for the Android package, when the release has one.
  final String? apkUrl;
  final String notes;

  /// Where "Download" should send the user.
  String get downloadUrl => apkUrl ?? releaseUrl;
}

/// Is this device on an unmetered connection? Abstracted so the update
/// policy can be tested without a device.
abstract class ConnectivityGate {
  Future<bool> isUnmetered();
}

/// connectivity_plus-backed. WiFi or ethernet counts as unmetered; mobile
/// data does not, so a release download is never started on a data plan.
class PlatformConnectivityGate implements ConnectivityGate {
  const PlatformConnectivityGate();

  @override
  Future<bool> isUnmetered() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) || result.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false; // unknown connection: assume metered and skip the check
    }
  }
}

/// Always-on gate, for desktop builds and tests.
class AlwaysUnmetered implements ConnectivityGate {
  const AlwaysUnmetered();
  @override
  Future<bool> isUnmetered() async => true;
}

/// Checks GitHub Releases for a newer build of this app.
///
/// The app is installed as an APK rather than through a store, so nothing
/// else would ever tell a user that a new version exists. Deliberately
/// modest in scope:
///
///   * it only ever READS the public releases API -- the repository is
///     public, so no token ships in the binary and nothing is authenticated;
///   * it runs once per launch, never in the background, and only on WiFi or
///     ethernet, so it cannot consume a data plan;
///   * it never installs anything. Tapping "Download" opens the APK URL in
///     the browser and Android's own installer takes over, so the app needs
///     no install permission;
///   * every failure is silent -- a failed check must never affect the
///     PM2.5 reading, which is the point of the app.
class UpdateService {
  UpdateService({
    http.Client? client,
    String? repo,
    String? currentVersion,
    ConnectivityGate connectivity = const PlatformConnectivityGate(),
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _repo = repo ?? AppConfig.updateRepo,
        _current = currentVersion ?? AppConfig.appVersion,
        _connectivity = connectivity,
        _timeout = timeout ?? AppConfig.updateCheckTimeout;

  final http.Client _client;
  final String _repo;
  final String _current;
  final ConnectivityGate _connectivity;
  final Duration _timeout;

  /// Returns the newer release, or null when there is nothing to offer:
  /// checking is disabled, the device is on metered data, the latest
  /// release is not newer, or anything at all went wrong.
  Future<UpdateInfo?> check() async {
    if (_repo.isEmpty) return null;
    try {
      // Inside the try: a connectivity plugin that is missing or throws (as
      // on an unsupported platform) must leave the reading untouched, not
      // surface an error out of a check nobody asked for.
      if (!await _connectivity.isUnmetered()) return null;
      final uri = Uri.parse('https://api.github.com/repos/$_repo/releases/latest');
      final response = await _client.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      }).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final info = parseRelease(body);
      if (info == null) return null;
      return isNewer(info.version, _current) ? info : null;
    } catch (_) {
      return null;
    }
  }
}

/// Builds an [UpdateInfo] from a GitHub release object, or null if the
/// payload is a draft, a prerelease, or not shaped as expected.
UpdateInfo? parseRelease(Map<String, dynamic> json) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  if (tag is! String || tag.trim().isEmpty) return null;
  final version = normaliseVersion(tag);
  if (version.isEmpty) return null;

  String? apk;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is Map && a['name'] is String && (a['name'] as String).toLowerCase().endsWith('.apk')) {
        final url = a['browser_download_url'];
        if (url is String && url.isNotEmpty) {
          apk = url;
          break;
        }
      }
    }
  }
  final page = json['html_url'];
  return UpdateInfo(
    version: version,
    tagName: tag,
    releaseUrl: page is String && page.isNotEmpty ? page : 'https://github.com/${AppConfig.updateRepo}/releases',
    apkUrl: apk,
    notes: json['body'] is String ? (json['body'] as String).trim() : '',
  );
}

/// "v1.2.3" / "1.2.3+4" -> "1.2.3". Empty when there are no digits at all.
String normaliseVersion(String raw) {
  var v = raw.trim();
  if (v.toLowerCase().startsWith('v')) v = v.substring(1);
  v = v.split('+').first.trim();
  return RegExp(r'^\d').hasMatch(v) ? v : '';
}

/// True when [candidate] is a strictly higher version than [current].
/// Numeric components compare numerically (so 0.10.0 > 0.9.0); a release
/// outranks a prerelease of the same numbers (1.0.0 > 1.0.0-beta).
bool isNewer(String candidate, String current) => compareVersions(candidate, current) > 0;

int compareVersions(String a, String b) {
  final an = normaliseVersion(a), bn = normaliseVersion(b);
  if (an.isEmpty || bn.isEmpty) return 0;
  final aMain = an.split('-').first, bMain = bn.split('-').first;
  final aPre = an.contains('-') ? an.substring(an.indexOf('-') + 1) : '';
  final bPre = bn.contains('-') ? bn.substring(bn.indexOf('-') + 1) : '';

  final ap = aMain.split('.'), bp = bMain.split('.');
  for (var i = 0; i < (ap.length > bp.length ? ap.length : bp.length); i++) {
    final x = i < ap.length ? int.tryParse(ap[i]) ?? 0 : 0;
    final y = i < bp.length ? int.tryParse(bp[i]) ?? 0 : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  if (aPre == bPre) return 0;
  if (aPre.isEmpty) return 1; // 1.0.0 > 1.0.0-beta
  if (bPre.isEmpty) return -1;
  return aPre.compareTo(bPre);
}
