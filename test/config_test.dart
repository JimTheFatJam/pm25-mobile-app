import 'package:flutter_test/flutter_test.dart';
import 'package:pm25_mobile_app/core/config.dart';

void main() {
  test('default backend URL is the Android emulator host alias only on Android', () {
    expect(AppConfig.defaultBaseUrlFor(isAndroid: true), 'http://10.0.2.2:5050');
    expect(AppConfig.defaultBaseUrlFor(isAndroid: false), 'http://127.0.0.1:5050');
  });

  test('on this (desktop) test host the effective default is localhost, never 10.0.2.2', () {
    // Tests run on the host VM, not Android, and no --dart-define override is set.
    expect(AppConfig.apiBaseUrl, 'http://127.0.0.1:5050');
  });
}
