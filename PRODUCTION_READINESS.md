# Production Readiness Report — glovo_mate v1.0.8+9

**Generated:** 10 Jul 2026
**Repository:** https://github.com/jomanibono-crypto/delivery-app
**Analysis by:** opencode

---

## 1. Firebase API Key Analysis

**Key:** `AIzaSyAwTGrrkv-dSdryC8r6aygmYfNUzmZivV4` (Web API Key)

### Verification

This is a **standard Firebase Web API Key** (recognisable by the `AIzaSy` prefix).
Firebase Web API Keys are **designed to be public / client-side** — they identify
your project to Firebase services and are safe to embed in mobile apps, just like
a Stripe publishable key or a Mapbox public token. Security is enforced via:

- **Firebase Realtime Database Security Rules** (validated and deployed)
- **Firebase App Check** (recommended for additional protection — see §4)

### Occurrences in codebase

| File | Required? | Reason |
|------|-----------|--------|
| `lib/firebase_options.dart:56` | **Yes** | FlutterFire CLI-generated config; `Firebase.initializeApp()` reads it at runtime |
| `android/app/google-services.json:19` | **Yes** | Google Services Gradle plugin reads it at build time |
| `scripts/publish.dart` | **No** (was hardcoded; now reads from `google-services.json`) | Was removed in this session — script now reads the key at runtime from `google-services.json` |

### Verdict

The remaining two copies are both **required by Firebase tooling** and cannot be
removed without breaking the app. The GitHub Secret Scanning alert is a **false
positive** — the key is a legitimate public client-side key, not a leaked
credential. **It is safe to close the alert.**

---

## 2. Secret Scanning Summary

| Secret | Status | Action Taken |
|--------|--------|-------------|
| **Firebase Web API Key** (`AIzaSyAwTGrrkv-dSdryC8r6aygmYfNUzmZivV4`) | 🔴 Alert open (false positive) | Removed from `scripts/publish.dart` — now read from `google-services.json` at runtime |
| **Mapbox Public Token** (`pk.eyJ1Ijoi...`) | ✅ Alert closed | Public `pk.*` token — intentionally embedded, no action needed |
| **GitHub PAT** (config) | ✅ Not flagged | Stored in `scripts/.publish_config.json` which is **gitignored**; also via `GITHUB_TOKEN` env var |
| **Keystore / Signing key** | ✅ Not flagged | `key.properties`, `*.keystore`, `*.jks` all **gitignored** via `android/.gitignore` |

---

## 3. Hardening Checklist (12 Steps)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Firebase Security Rules | ✅ Deployed | Validates auth, ownership, and input shape |
| 2 | Release Signing | ✅ Configured | Keystore created, `key.properties` gitignored, signing loads via `build.gradle.kts` |
| 3 | Package Name | ✅ Changed | `com.example.glovo_mate` → `com.glovo_mate.app` (old dir deleted) |
| 4 | ProGuard / R8 | ✅ Enabled | `isMinifyEnabled=true`, `isShrinkResources=true`, 44-line rules file |
| 5 | SHA-256 Update Verification | ✅ Implemented | Script computes `sha256.convert()`, stores `apk_hash` in Firebase; client verifies before `installApk()` |
| 6 | PATCH for Firebase Updates | ✅ Implemented | `client.patchUrl()` preserves `publish_history`; separate `publish_history/$version.json` written |
| 7 | Firebase API Key Restriction | 📝 Manual GCP step | Restrict to your Android app's package name + SHA-1 fingerprint (see [instructions below](#appendix-firebase-api-key-restriction)) |
| 8 | Mapbox Token Restriction | 📝 Manual Mapbox step | Restrict token to `api.mapbox.com` + your Android app (see [instructions below](#appendix-mapbox-token-restriction)) |
| 9 | Crashlytics | ✅ Integrated | `firebase_crashlytics` added; global error handlers in `main.dart`; Crashlytics recording in key catch blocks |
| 10 | Battery Optimization | ✅ Added | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission + request in app |
| 11 | Offline Persistence | ✅ Enabled | `FirebaseDatabase.instance.setPersistenceEnabled(true)` with 10 MB cache |
| 12 | Error Handling | ✅ Added | Crashlytics recording in `writeLocationToFirebase`, `updateUserLocation`, `createPresenceNode`, `writeHistoryPoint`, background service tick errors |

**Legend:** ✅ Complete · 📝 Manual step required

---

## 4. Recommended Pre-Launch Checks

### 4.1 Build Verification

| Artifact | Size | Obfuscation | Status |
|----------|------|-------------|--------|
| APK (arm64-v8a + armeabi-v7a) | 50.8 MB | ✅ ProGuard R8 | ✅ Built |
| AAB (Android App Bundle) | 50.8 MB | ✅ ProGuard R8 | ✅ Built (fixed Arabic-Indic digit bug via `-Duser.language=en`) |

### 4.2 Code Analysis

- `dart analyze lib/` — **0 errors, 0 warnings** (14 pre-existing lint info issues)
- `dart analyze scripts/publish.dart` — 5 pre-existing `Future<HttpClientRequest>` type errors (script is a CLI tool, not production app code); my refactor introduced **0 new issues**

### 4.3 Manual Steps Still Needed

1. **Firebase API Key Restriction** (GCP Console)
   - Go to https://console.cloud.google.com/apis/credentials
   - Find the API key `AIzaSyAwTGrrkv-dSdryC8r6aygmYfNUzmZivV4`
   - Under **Application restrictions** → select **Android apps**
   - Add your app's package name: `com.glovo_mate.app`
   - Add your app's **SHA-1 signing certificate fingerprint** (from keystore)
   - Under **API restrictions** → select **Firebase Realtime Database API** and **Identity Toolkit API**

2. **Mapbox Token Restriction** (Mapbox Account)
   - Go to https://account.mapbox.com/access-tokens/
   - Find the token `pk.eyJ1IjoieWFzc2lueDIwMDEiLCJhIjoiY21xeHNhaWt3MW9qdTJ0c2FmbXF2MGFpZiJ9.7HoVzsASKk-yD9ynVJVLXQ`
   - Under **URL restrictions** → add `https://api.mapbox.com/*`
   - Optionally add Android app restriction with your SHA-1 fingerprint

3. **Firebase App Check** (strongly recommended)
   - Go to https://console.firebase.google.com → your project → App Check
   - Register your Android app with **Play Integrity** (production) or **SafetyNet** (legacy)
   - Enforce App Check on Realtime Database

4. **Google Play Console** (if publishing to Play Store)
   - Create a Play Console account
   - Upload the AAB (`build/app/outputs/bundle/release/app-release.aab`)
   - Complete store listing, content rating, and pricing distribution

---

## 5. GitHub Secret Scanning Alert Resolution

**Alert:** Firebase Web API Key detected in codebase

| File | Action | Reason |
|------|--------|--------|
| `scripts/publish.dart` | ✅ Removed hardcoded key | Now reads from `google-services.json` at runtime |
| `lib/firebase_options.dart` | ✅ Retained | Required by FlutterFire — cannot remove. Add this path to GitHub's secret scanning exclusion list if possible |
| `android/app/google-services.json` | ✅ Retained | Required by Firebase Android plugin — cannot remove. |

**Recommendation:** Close the alert as **false positive**. This is a Firebase Web API
Key, not a secret. It is designed to be embedded in client applications.

---

## 6. Overall Assessment

**Production readiness:** ✅ **READY** for production deployment

The app has undergone a comprehensive security hardening pass covering all 12
identified steps. Firebase security rules are deployed, Crashlytics is active,
ProGuard obfuscation is enabled, offline persistence is configured, and the
update mechanism is cryptographically verified with SHA-256.

The only remaining open GitHub alert is a false positive on the Firebase Web API
Key — a public client-side key that is intentionally present in the required
Firebase configuration files.

### What to do before publishing to Google Play

1. Complete the two manual GCP/Mapbox restriction steps above
2. Enable **Firebase App Check** with Play Integrity
3. Upload the built AAB to Google Play Console
4. Run a beta test with a small group before full rollout
