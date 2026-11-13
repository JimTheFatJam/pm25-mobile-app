import 'package:flutter/material.dart';

import '../../app/theme.dart' show kGap;
import '../../app/theme_controller.dart';
import '../update/update_banner.dart';
import '../update/update_controller.dart';
import 'reading_controller.dart';
import 'reading_state.dart';
import 'widgets/reading_widgets.dart';

/// The single screen (SRS 3.1 / 4.3), laid out in the wireframe's order:
/// header -> current location -> large PM2.5 value + category ->
/// interpretation + guidance -> "Why this prediction?" (top factors,
/// direction, non-causation note) -> about this estimate (data lag,
/// as-of, last updated) -> refresh.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.controller, this.themeController, this.updateController});
  final ReadingController controller;

  /// Optional: when provided, a light/dark toggle is shown in the header.
  final ThemeController? themeController;

  /// Optional: when provided, a dismissible banner offers a newer release.
  /// Null in tests and wherever update checking is disabled.
  final UpdateController? updateController;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  /// Content column width cap so the layout stays phone-like on a wide
  /// desktop window; phones use the full width minus gutters.
  static const double _maxContentWidth = 560;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.updateController?.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.controller.load()); // REQ-4.3-1: automatic on launch
  }

  @override
  void didUpdateWidget(covariant ReadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.controller.load());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.updateController?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final state = c.state;
    final busy = state is RequestingPermission || state is Locating || state is LoadingPrediction;
    final update = widget.updateController?.available;
    final themeController = widget.themeController;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Centred header (wireframe): the title sits in the middle of the
    // screen, not of the space left of the two action buttons. A blank
    // leading slot as wide as the actions keeps it truly centred; on very
    // narrow screens that slot is dropped so the title never collides with
    // the toggle (the AppBar then centres it in the remaining space) and
    // FittedBox shrinks it rather than clipping.
    final actionsWidth = (themeController != null ? 2 : 1) * 48.0 + 4;
    final symmetric = MediaQuery.sizeOf(context).width >= 400;
    return Scaffold(
      appBar: AppBar(
        leading: symmetric ? const SizedBox.shrink() : null,
        leadingWidth: symmetric ? actionsWidth : null,
        automaticallyImplyLeading: false,
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('PM2.5 Air Quality')),
        actions: [
          if (themeController != null)
            IconButton(
              key: const Key('theme-toggle'),
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              onPressed: () => themeController.toggle(context),
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
          IconButton(
            key: const Key('refresh-button'),
            tooltip: 'Refresh',
            onPressed: busy ? null : c.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth < 380 ? 14.0 : 18.0;
              return ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 2, horizontal, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // An available update is informational: it sits above
                          // the reading, is dismissible, and never blocks it.
                          if (update != null) ...[
                            UpdateBanner(info: update, onDismiss: widget.updateController!.dismiss),
                            const SizedBox(height: kGap),
                          ],
                          _locationCard(state),
                          const SizedBox(height: 14),
                          ..._body(context, state),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Once a fix exists the card shows the device's own coordinates (and a
  /// locality when available); before that, a short status. Grid-cell ids
  /// stay internal to the request.
  Widget _locationCard(ReadingState state) {
    final (icon, location, status) = switch (state) {
      RequestingPermission() => (Icons.location_searching, null, 'Checking location access…'),
      Locating() => (Icons.my_location, null, 'Locating…'),
      LoadingPrediction(:final location) => (Icons.my_location, location, null),
      Success(:final location) => (Icons.my_location, location, null),
      PermissionDenied() || PermissionDeniedForever() => (Icons.location_off, null, 'Location not available'),
      LocationServicesDisabled() => (Icons.gps_off, null, 'Location services off'),
      LocationFailed() => (Icons.location_off, null, 'Location not available'),
      OutsideCoverage(:final location) => (Icons.public_off, location, 'Location outside the supported grid'),
      PredictionUnavailable(:final location) => (Icons.my_location, location, null),
      NetworkError(:final location) => (Icons.my_location, location, null),
    };
    return LocationCard(icon: icon, location: location, status: status);
  }

  List<Widget> _body(BuildContext context, ReadingState state) {
    final c = widget.controller;
    switch (state) {
      case RequestingPermission():
        return const [
          StatusCard(
            icon: Icons.location_searching,
            progress: true,
            title: 'Checking location access',
            message: 'The app needs your location once to estimate air quality where you are. It is not stored.',
          ),
        ];
      case Locating():
        return const [
          StatusCard(icon: Icons.my_location, progress: true, title: 'Finding your location', message: 'Getting a coarse fix (about 1 km is enough).'),
        ];
      case PermissionDenied():
        return [
          StatusCard(
            icon: Icons.location_off,
            title: 'Location permission needed',
            message: 'Without location access the app cannot tell which 1 km area to estimate. Your location is used only for this request and is never stored.',
            actionLabel: 'Try again',
            onAction: c.load,
          ),
        ];
      case PermissionDeniedForever():
        return [
          StatusCard(
            icon: Icons.location_off,
            title: 'Location permission is blocked',
            message: 'Location access was permanently denied. Enable it for this app in the system settings, then try again.',
            actionLabel: 'Open app settings',
            onAction: c.openAppSettings,
            secondaryLabel: 'Try again',
            onSecondary: c.load,
          ),
        ];
      case LocationServicesDisabled():
        return [
          StatusCard(
            icon: Icons.gps_off,
            title: 'Location services are off',
            message: 'Turn on location services on this device so the app can find your current 1 km area.',
            actionLabel: 'Open location settings',
            onAction: c.openLocationSettings,
            secondaryLabel: 'Try again',
            onSecondary: c.load,
          ),
        ];
      case LocationFailed(:final detail):
        return [StatusCard(icon: Icons.error_outline, title: 'Could not get your location', message: detail, actionLabel: 'Try again', onAction: c.load)];
      case LoadingPrediction(:final slow, :final elapsed, :final previous):
        return [
          StatusCard(
            key: const Key('loading-card'),
            icon: Icons.cloud_download_outlined,
            progress: true,
            title: slow ? 'Still working (${elapsed.inSeconds}s)…' : 'Estimating PM2.5 for your area',
            message: slow
                ? 'The first request for a location has to retrieve satellite and weather data from Earth Engine on the server, which can take up to about a minute. Later requests for the same area are much faster.'
                : 'Contacting the prediction service.',
          ),
          if (previous != null) ...[
            const SizedBox(height: kGap),
            Opacity(opacity: 0.45, child: IgnorePointer(child: ReadingHeadline(reading: previous))),
          ],
        ];
      case Success(:final reading, :final receivedAt, :final location):
        return [
          ReadingHeadline(reading: reading),
          const SizedBox(height: kGap),
          MeaningCard(reading: reading),
          const SizedBox(height: kGap),
          WhyCard(reading: reading),
          const SizedBox(height: kGap),
          DataNoteCard(
            reading: reading,
            receivedAt: receivedAt,
            // Provider attribution only when a resolved place name is on screen.
            attribution: (location?.placeName ?? '').isNotEmpty ? c.placeAttribution : null,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: c.refresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
        ];
      case OutsideCoverage(:final message):
        return [
          StatusCard(icon: Icons.public_off, title: 'Outside the supported area', message: message, actionLabel: 'Try again', onAction: c.load),
        ];
      case PredictionUnavailable(:final message):
        return [
          StatusCard(icon: Icons.cloud_off_outlined, title: 'Estimate unavailable', message: message, actionLabel: 'Try again', onAction: c.load),
        ];
      case NetworkError(:final message):
        return [
          StatusCard(icon: Icons.wifi_off_rounded, title: 'Cannot reach the prediction service', message: message, actionLabel: 'Try again', onAction: c.load),
        ];
    }
  }
}
