# PM2.5 Air Quality — mobile app

Flutter client for the PM2.5 prediction service at
<https://pm25.dcism.org>. One screen: the latest available PM2.5 estimate for
the 1 km grid cell you are standing in, what it means, protective guidance, and
which model inputs moved the estimate.

Part of an undergraduate thesis at the Department of Computer, Information
Sciences and Mathematics, University of San Carlos — *Multimodal Spatiotemporal
Fusion for PM2.5 Prediction*. Backend and model:
[pm25-web-app](https://github.com/JimTheFatJam/pm25-web-app).

> **This is a model estimate, not a measurement.** The satellite and reanalysis
> inputs lag real time by several days, so the app always labels the reading
> with the timestamp it is actually for. It is never presented as a live
> reading, and it is not a substitute for a reference monitor.

---

## What it does

- Gets a coarse GPS fix on launch, sends it to the backend, shows the estimate
  for that cell at the latest timestamp with complete input data.
- Classifies the value with the **US EPA 2024 PM2.5 AQI** bands and shows that
  category's interpretation and protective guidance.
- **Why this prediction?** — the top contributing model inputs as a diverging
  bar chart, with an explicit note that these are model attributions, not
  causes of pollution.
- States how far behind real time the estimate is, and when it was last
  fetched.
- Light and dark themes; offers its own updates (see below).

## Privacy

- Coordinates are used for one prediction request and held only while that
  reading is on screen. No location history, nothing persisted, nothing logged
  by the backend.
- The optional locality label ("Cebu City, Central Visayas") comes from
  OpenStreetMap Nominatim, which receives only the coordinates **rounded to
  ~1 km**, never the exact fix. Place names © OpenStreetMap contributors.
- No analytics, no advertising, no accounts, no third-party SDKs.

---

## Running it

Requires Flutter (stable) and the backend running — see the web app's README.

```bash
flutter pub get
```

```bash
flutter run -d windows
```

A **debug** build targets `http://127.0.0.1:5050` on desktop and
`http://10.0.2.2:5050` on the Android emulator. A **release** build targets
`https://pm25.dcism.org`. Override either with
`--dart-define=PM25_API_BASE_URL=http://host:port`.

```bash
flutter test
```

Integration test against a live backend:

```bash
flutter test integration_test/backend_integration_test.dart -d windows
```

## Updates

The app is distributed as an APK from
[Releases](https://github.com/JimTheFatJam/pm25-mobile-app/releases), so it
checks for a newer one itself: once per launch, **only on WiFi or ethernet**,
through the public GitHub API with no token. If a newer release exists a
dismissible banner offers it; **Download** hands the APK to the browser and
Android's installer. Every failure is silent and never affects the reading.

See [RELEASING.md](RELEASING.md) for the release process.

## Layout

```
lib/
  core/config.dart              backend URL, geocoder and update settings
  models/                       PredictionReading, classification
  services/                     API client, location, reverse geocoding, updates
  features/reading/             the screen, its controller and states
  features/update/              update banner and controller
  app/theme.dart                design tokens, light and dark
```

Plain `ChangeNotifier` controllers and a sealed state class — no state
management framework. Dependencies: `geolocator`, `http`, `connectivity_plus`,
`url_launcher`.
