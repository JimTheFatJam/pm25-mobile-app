import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'app/theme_controller.dart';
import 'features/reading/reading_controller.dart';
import 'features/reading/reading_screen.dart';
import 'features/update/update_controller.dart';
import 'core/config.dart';
import 'services/api_client.dart';
import 'services/location_service.dart';
import 'services/web_place_name_resolver.dart';

/// PM2.5 Air Quality -- the public-facing mobile client of the thesis's
/// PM2.5 prediction backend (SRS section 4.3). One screen: the latest
/// available PM2.5 estimate for the user's current 1 km grid cell, its
/// EPA category, what it means, protective guidance, a data-latency note
/// and the top-3 model factors. No map, no history, no stored location.
void main() {
  runApp(const PM25MobileApp());
}

class PM25MobileApp extends StatefulWidget {
  const PM25MobileApp({super.key});

  @override
  State<PM25MobileApp> createState() => _PM25MobileAppState();
}

class _PM25MobileAppState extends State<PM25MobileApp> {
  late final ReadingController _controller = ReadingController(
    locationService: GeolocatorLocationService(),
    api: HttpPredictionApi(),
    // Display-only locality label; the prediction never depends on it.
    placeNameResolver: AppConfig.geocoderEnabled ? WebPlaceNameResolver() : const NoPlaceNameResolver(),
  );

  /// Starts by following the OS setting; the header toggle then pins light
  /// or dark for the rest of the session (see ThemeController).
  final ThemeController _theme = ThemeController();

  /// One GitHub release check per launch, WiFi only, entirely optional --
  /// see services/update_service.dart. Null when disabled at build time.
  final UpdateController? _updates = AppConfig.updateCheckEnabled ? UpdateController() : null;

  @override
  void initState() {
    super.initState();
    // Fire and forget: the reading never waits on this.
    _updates?.checkOnce();
  }

  @override
  void dispose() {
    _controller.dispose();
    _theme.dispose();
    _updates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp(
        title: 'PM2.5 Air Quality',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _theme.mode,
        home: ReadingScreen(controller: _controller, themeController: _theme, updateController: _updates),
      ),
    );
  }
}
