# Releasing the app

The app is installed as an APK from GitHub Releases rather than through a
store, so releasing is: tag a version, let CI build and sign it, and installed
apps offer it to their users automatically.

---

## One-time setup

The signing keystore was generated outside this repository and is **not** in
git. It lives in `pm25-release-signing/` wherever you keep it, alongside a
`GITHUB_SECRETS.txt` with the exact values to paste.

> **Back that folder up somewhere private.** Android refuses an update signed
> with a different key, so losing the keystore means every existing user has to
> uninstall and reinstall to ever get another update. Do not put it in a public
> repository.

Add four repository secrets — **Settings → Secrets and variables → Actions →
New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the whole contents of `keystore.base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the password from `GITHUB_SECRETS.txt` |
| `ANDROID_KEY_PASSWORD` | the same password |
| `ANDROID_KEY_ALIAS` | `pm25-upload` |

CI decodes the keystore into a temporary file, writes `android/key.properties`,
builds, and deletes both in an `always()` step. Nothing secret is committed and
nothing secret ends up inside the APK.

---

## Cutting a release

1. Bump `version:` in `pubspec.yaml` (e.g. `0.2.0+2`).
2. Commit and push to `main`.
3. Tag and push the tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The `Release APK` workflow then runs `flutter analyze` and `flutter test`
first — a tag cannot ship something that would have failed CI — builds a signed
APK, and publishes it as a release with a SHA-256 checksum.

The tag **is** the version users compare against, so `v0.2.0` must match
`pubspec.yaml`. CI passes it to the build as `PM25_APP_VERSION`.

To test the pipeline without publishing, use **Actions → Release APK → Run
workflow** and give a version: it builds and uploads an artifact but creates no
release.

---

## How users get it

`lib/services/update_service.dart`, once per launch:

1. Skip entirely if the device is **not on WiFi or ethernet** — an update check
   never spends a mobile data plan.
2. `GET https://api.github.com/repos/JimTheFatJam/pm25-mobile-app/releases/latest`
   — a public, unauthenticated read. No token ships in the APK.
3. Compare the tag against this build's version, numerically
   (`0.10.0` > `0.9.0`), ignoring drafts and prereleases.
4. If newer, show a dismissible banner above the reading. **Download** opens
   the APK URL in the browser and Android's own installer takes over, so the
   app holds no install permission.

Every step fails silently. A GitHub outage, a rate limit, a malformed response
or a missing connectivity plugin all result in no banner — never a broken
reading. Dismissal lasts for the session.

Disable it in a build with `--dart-define=PM25_UPDATE_REPO=off`, or point it at
a fork with `--dart-define=PM25_UPDATE_REPO=owner/name`.

---

## Which backend a build talks to

| Build | Backend |
|---|---|
| `flutter run` (debug) | `http://127.0.0.1:5050` desktop, `http://10.0.2.2:5050` Android emulator |
| `flutter build` (release) | `https://pm25.dcism.org` |
| any build with `--dart-define=PM25_API_BASE_URL=…` | that URL |

So a released APK always talks to the public service over HTTPS, and local
development against `python run_app.py` keeps working unchanged.

---

## Building a signed APK locally

Rarely needed — CI is the supported path — but if you must, create
`android/key.properties` (gitignored):

```
storeFile=C:/Users/<you>/pm25-release-signing/pm25-upload-key.jks
storePassword=<password>
keyPassword=<password>
keyAlias=pm25-upload
```

```bash
flutter build apk --release --dart-define=PM25_APP_VERSION=0.2.0
```

Without `key.properties` the release build falls back to the debug key. It will
run, but it is **not** a publishable update: existing installs will reject it.
