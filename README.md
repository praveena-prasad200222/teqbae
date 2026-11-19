# REBS HRMS — Offline-Capable Employee Workspace

Flutter assignment implementation. One preconfigured employee (login is out of scope) can view a dashboard, record GPS-verified attendance while online **or offline**, and apply for leave. Pending attendance events survive app restarts and synchronize automatically when connectivity returns.

---

## 1. Architecture (MVVM + Provider)

```
lib/
├── main.dart                       Entry point: Hive init, dependency creation
├── app.dart                        MaterialApp, theme, Provider wiring
├── di.dart                         Manual dependency injection / composition root
├── constants/                      Compile-time configuration (--dart-define)
├── models/                         Immutable data classes (pure Dart)
├── utils/                          Pure rules: clock, geofence, attendance/leave rules
├── services/
│   ├── api/                        HTTP client + typed exceptions (mock REST API)
│   ├── location/                   Geolocator + deterministic simulation
│   ├── network/                    connectivity_plus wrapper
│   ├── storage/                    Hive persistence + LocalStorage contract
│   └── sync/                       Idempotent pending-event sync engine
├── repositories/                   Coordinate API + local cache, enforce rule checks
├── providers/                      ── ViewModels (MVVM) extending ChangeNotifier
├── screens/                        ── Views (4 bottom-nav tabs + shell)
└── widgets/                        ── Reusable views
mock_api/mock_server.dart           Standalone local mock REST API (dart:io)
test/                               Unit + widget tests
```

**Why this split:** Provider + `ChangeNotifier` ViewModels are lightweight, replaceable in tests, and keep all decisions out of `build()` methods. The rules (`AttendanceRules`, `LeaveRules`, `GeoFence`, `CompanyClock`) are pure Dart, so business logic is unit-testable without Flutter. `ApiClient` is the only HTTP caller; repositories own cache/API decisions; `SyncEngine` owns retry identity and ordering.

**Data flow:** View → ViewModel → Repository → (ApiClient / LocalStorage). Connectivity changes are broadcast by `ConnectivityViewModel` to the sync, dashboard, attendance and leave ViewModels.

**Storage:** Hive boxes `attendance_events` (JSON strings keyed by stable `eventId`) and `app_cache` (employee, balance, leave requests, remote attendance history, last sync). JSON strings were chosen over generated TypeAdapters to avoid a `build_runner` dependency; `LocalStorage` is an interface so tests use an in-memory implementation.

---

## 2. Setup

Requirements: Flutter 3.x / Dart 3.x (developed with Flutter 3.47.2, Dart 3.13.2), Android SDK or Xcode.

```bash
flutter pub get
flutter analyze
flutter test
```

Run the mock API **first**, in a separate terminal. It uses the same central
office configuration as the app:

```bash
dart run -DOFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
         -DOFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE> \
         mock_api/mock_server.dart --port=8090 --scenario=success
```

Then run the app. **The default `API_BASE_URL` (`http://10.0.2.2:8090`) works only
in the Android emulator.** On a physical phone it points to the phone itself,
which is why dashboard/leave calls time out. You can either pass the correct LAN
IP as a define, or — more conveniently for a phone — set it in the app:

1. Install/run the debug build without any `API_BASE_URL` define.
2. Open **Profile → API server address**.
3. Enter `http://<computer-LAN-IP>:8090` and tap **Save & retry**.
4. Return to Dashboard; server data replaces the locally cached demo history once
   the address is correct.

The five **Latest five attendance records** are seeded into the local cache on a
fresh install, so they are visible even before the API is reachable. They are
clearly demo history, not fake check-ins: real check-in/out still requires a
valid office reference and all attendance rules.

For Check In / Check Out without rebuilding, a DEBUG build automatically creates
a clearly-labelled **“DEBUG generated test point (not Teqbae)”** when no real
office coordinates were supplied. Simulation starts **ON** with **Inside 200 m**
selected, so Check In works immediately; **Outside 200 m** still rejects the
action through the unchanged 200 m rule. No coordinate is bundled in the source —
the test point is generated on the device and saved locally. You can enter your
own coordinates under **Attendance → Test office coordinates (DEBUG)**. RELEASE
never generates a test point and always uses real GPS with real office config.

In production, supply the real office through `OFFICE_LAT` / `OFFICE_LNG` or the
server.

Leave submission is local-first: **Submit request** always saves as **Pending
Sync** and returns immediately. Network attempts happen in the background, so a
broken mock server can never block the form or produce a false success.

The saved URL is persisted locally and applies to every request. **Use compile-time
default** restores `http://10.0.2.2:8090`. Make sure the phone and computer are on
the same Wi-Fi and that the mock server is listening on `0.0.0.0` (its default).

You may still provide the URL at build/run time:

```bash
# Android emulator (default API_BASE_URL already points here)
flutter run \
  --dart-define=OFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
  --dart-define=OFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE>

# iOS simulator
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8090 \
  --dart-define=OFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
  --dart-define=OFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE>

# Physical device: replace 192.168.1.10 with your computer's LAN IP
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.10:8090 \
  --dart-define=OFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
  --dart-define=OFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE>
```

Debug APK:

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://192.168.1.10:8090 \
  --dart-define=OFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
  --dart-define=OFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE>
# output: build/app/outputs/flutter-apk/app-debug.apk
```

Verify the server from the same machine:

```bash
curl http://127.0.0.1:8090/employee/me
curl http://127.0.0.1:8090/leave/balance
```

### Platform permissions

Android — `android/app/src/main/AndroidManifest.xml` already contains:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

It also sets `android:usesCleartextTraffic="true"` on `<application>` for the HTTP mock server. Remove that attribute when moving to HTTPS.

iOS — `ios/Runner/Info.plist` already contains `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription` and an `NSAppTransportSecurity` exception for the local HTTP mock server. Remove `NSAllowsArbitraryLoads` for production HTTPS.

Permissions are requested at runtime by `GeolocatorLocationService`, with explicit messages for denied, permanently denied and GPS-unavailable cases. Opening app settings is left to the OS prompt message (no extra plugin was added, to keep dependencies minimal).

---

## 3. Configuration

Most settings are compile-time overrides; no source edits are needed. The API
base URL can also be changed at runtime from **Profile → API server address**,
which is the recommended path for a physical phone.

| Setting | `--dart-define` | Default |
|---|---|---|
| API base URL | `API_BASE_URL` | `http://10.0.2.2:8090` (emulator only; override in Profile on a phone) |
| Mock scenario | `MOCK_SCENARIO` | `success` |
| Office name | `OFFICE_NAME` | `Teqbae, Kochi` |
| Office latitude | `OFFICE_LAT` | **required — no coordinate is bundled** |
| Office longitude | `OFFICE_LNG` | **required — no coordinate is bundled** |
| Geofence radius (m) | `OFFICE_RADIUS_M` | `200` |
| Company UTC offset (minutes) | `COMPANY_TZ_OFFSET_MINUTES` | `330` (UTC+05:30) |
| Company timezone label | `COMPANY_TZ_LABEL` | `IST (UTC+05:30)` |

**REBS is the machine-test / project name. The company is Teqbae, Kochi, Kerala.**
No old city office name or old-city coordinates are bundled anywhere. Teqbae's
exact office latitude/longitude were not supplied, so they must be provided at
build/run time with `OFFICE_LAT` and `OFFICE_LNG`. Until they are supplied the
app uses an explicit `0,0` sentinel with `isConfigured = false`: attendance is
blocked with a configuration message instead of reporting a fake distance.

Example (replace the coordinates with Teqbae's real ones):

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8090 \
  --dart-define=OFFICE_NAME="Teqbae, Kochi" \
  --dart-define=OFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
  --dart-define=OFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE> \
  --dart-define=OFFICE_RADIUS_M=200 \
  --dart-define=COMPANY_TZ_OFFSET_MINUTES=330
```

Start the mock server with the **same** office defines so client and server
agree on the geofence:

```bash
dart run -DOFFICE_LAT=<TEQBAE_OFFICE_LATITUDE> \
         -DOFFICE_LNG=<TEQBAE_OFFICE_LONGITUDE> \
         mock_api/mock_server.dart --port=8090 --scenario=success
```

`AppConfig` in `lib/constants/app_config.dart` is the single central office
configuration. Both the Flutter app and `mock_api/mock_server.dart` import it;
the server has no independent office name or coordinates. The office returned by
`GET /employee/me` wins when online; `AppConfig` is the offline fallback. The
company timezone is a fixed UTC offset so "the company day" is deterministic.

## 4. GPS Simulation for Testing (DEBUG builds only)

The **Attendance** screen contains a **GPS Simulation (DEBUG)** card. It is
created only when `LocationSimulationViewModel.isSupported` is true, which is
`!kReleaseMode`. Release builds never create the simulation controller and
always use real device GPS. No emulator tooling or `--dart-define` is required.

1. Run a debug build: `flutter run` (or install the debug APK).
2. Open **Attendance → GPS Simulation (DEBUG)**.
3. The switch is off initially, so **Real device GPS is active** is displayed.
4. Turn the switch on. The card now displays **Simulated coordinates are being
   used for check-in/out**, and `getCurrentPosition()` returns the simulated
   point instead of the device GPS point.
5. Tap **Inside 200 m**. This sets simulated coordinates at the configured
   office (0 m from the office, which is within 50 m). The card shows the
   Haversine distance and `inside the 200 m geofence`. Check In is allowed if
   all other attendance rules are satisfied.
6. Tap **Outside 200 m**. This sets simulated coordinates 275 m from the
   configured office, which is more than 200 m. The card shows `outside the
   200 m geofence` and Check In / Check Out are rejected by the same rule used
   for real coordinates.
7. The simulation selection is not reset when the Check In / Check Out
   confirmation dialog is opened or dismissed.
8. Turn the switch off to return to real device GPS at any time.

The distance shown on the Attendance screen uses the office from the loaded
employee record, which is the exact office used by check-in/check-out
validation. The same debug-only controller is also available from
**Profile → Development GPS simulation**.

If office coordinates are not configured, the presets are disabled and the card
shows the `OFFICE_LAT` / `OFFICE_LNG` configuration message instead of pretending
that `0,0` is the Teqbae office.

The simulation fields pre-fill from the central `OFFICE_LAT` / `OFFICE_LNG`
configuration; there are no separate `MOCK_LAT` / `MOCK_LNG` settings.
`LocationSimulationViewModel` implements `LocationService`, so the
simulated point goes through the unchanged `GeoFence` / `AttendanceRules`
validation path. No attendance rule, duplicate check or server validation is
bypassed.

**Release builds do not contain this feature.** `AppDependencies.createLocationServices`
returns only `GeolocatorLocationService` when `kReleaseMode` is true, and
`app.dart` omits the simulation Provider. The final release APK has no
simulation switch or fields.

Alternative device-level simulation (works in release-testing builds too):

* **Android emulator:** Extended controls → *Location*, or
  `adb emu geo fix <OFFICE_LNG> <OFFICE_LAT>` using the configured Teqbae office coordinates.
* **iOS simulator:** Xcode → Debug → Location → Custom Location… (or a `.gpx` file).

### Dashboard caching and leave balance data

The dashboard and leave screens are **cached-first**. On load they publish the
Hive snapshot (employee, attendance history and leave balance) immediately, set
`ViewState.ready`, and then run one deduplicated background refresh. A slow or
unreachable API can therefore never leave the full-screen loading indicator on.
The request timeout is 8 seconds (`AppConfig.apiTimeout`). Failures show an
inline message with a **Retry** button; the global offline banner is shown by
the app shell whenever connectivity is offline. Pull-to-refresh and the
connectivity-restored listener reuse the same refresh Future while one is
already running.

The preconfigured employee's leave balance uses **sample data**:
**12 casual and 6 sick days (18 total)**. These are demonstration values, not
actual company leave records. They are stored in Hive on first launch so the
balance remains visible offline, and `GET /leave/balance` overwrites them as
soon as the API responds. Missing/null fields in an API response also fall back
to the sample values; an explicit `0` is preserved as a real zero balance.

The leave calendar's `firstDate` is the current company date from
`CompanyClock`, and the end-date picker starts no earlier than the selected
start date. Past dates are additionally rejected by `LeaveViewModel.submit`,
so the calendar restriction is not only a UI rule.

### Leave submission and error messages

A leave request is **always saved locally first** with a stable client id
(`LRV-LOCAL-<uuid>`). It is then submitted to `POST /leave/requests` when online:

* Success: the local pending copy is replaced by the server receipt and a real
  success message is shown.
* Offline while connectivity is offline: the request stays **Pending Sync**.
  If the API is unreachable during a send attempt, it is marked **Failed** but
  kept locally for automatic retry. The message says so explicitly; it is never
  reported as submitted to the server.
* HTTP 422: the server's actual validation message is displayed and the
  rejected local copy is kept out of the pending queue.
* HTTP 5xx / 4xx: the server message is displayed and the request is marked
  **Failed** locally for automatic retry.

`Connection Lost` is no longer used as a catch-all. A reachability failure names
the configured `API_BASE_URL` and explains how to correct it. Pending leave
requests are included in the Sync badge and are sent automatically when
connectivity returns.

---

## 5. Mock REST API

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/employee/me` | Employee + office configuration |
| GET | `/attendance?month=YYYY-MM` | Attendance history |
| POST | `/attendance/events` | Submit check-in / check-out event |
| GET | `/leave/balance` | Leave balance |
| GET | `/leave/requests` | Leave request history |
| POST | `/leave/requests` | Submit leave application |

The Flutter app calls these through `package:http` (`ApiClient`); no widget contains hardcoded response data. The server keeps in-memory state, seeds three past attendance days and three leave requests, and repeats geofence / duplicate / leave validation so client and server behaviour can be compared.

### Sample request and response JSON

`GET /employee/me`:

```json
{
  "id": "EMP-1001",
  "name": "Aarav Sharma",
  "department": "Human Resources",
  "designation": "HR Executive",
  "email": "aarav.sharma@rebs.example",
  "office": {
    "name": "Teqbae, Kochi",
    "latitude": "<OFFICE_LAT>",
    "longitude": "<OFFICE_LNG>",
    "radiusMeters": 200,
    "timezoneOffsetMinutes": 330,
    "isConfigured": true
  }
}
```

Replace `<OFFICE_LAT>` and `<OFFICE_LNG>` with the real values supplied through
`OFFICE_LAT` / `OFFICE_LNG`. No office coordinates are bundled in the app or the
mock server.

`POST /attendance/events` request:

```json
{
  "eventId": "UUID_GENERATED_ONCE_ON_DEVICE",
  "employeeId": "EMP-1001",
  "type": "checkIn",
  "timestampUtc": "2026-01-15T04:00:00.000Z",
  "latitude": "<DEVICE_OR_SIMULATED_LATITUDE>",
  "longitude": "<DEVICE_OR_SIMULATED_LONGITUDE>",
  "dateKey": "2026-01-15",
  "sequence": 1
}
```

`POST /attendance/events` success response:

```json
{
  "eventId": "UUID_GENERATED_ONCE_ON_DEVICE",
  "serverEventId": "SRV-1",
  "duplicate": false
}
```

`POST /leave/requests` request:

```json
{
  "id": "LRV-LOCAL-UUID",
  "employeeId": "EMP-1001",
  "type": "casual",
  "startDate": "2026-01-15",
  "endDate": "2026-01-16",
  "reason": "Family function at home.",
  "days": 2
}
```

`POST /leave/requests` success response:

```json
{
  "id": "LRV-LOCAL-UUID",
  "type": "casual",
  "startDate": "2026-01-15",
  "endDate": "2026-01-16",
  "reason": "Family function at home.",
  "days": 2,
  "status": "pending",
  "submittedAtUtc": "2026-01-15T04:00:00.000Z"
}
```

The stable `id` / `eventId` is the idempotency key. Replaying the same request
after a timeout returns the original receipt instead of creating a duplicate.

### Repeatable scenarios

Start with `--scenario=<name>`, or run the app with `--dart-define=MOCK_SCENARIO=<name>` (the app sends `X-Mock-Scenario` on every request and overrides the server default).

| Scenario | Behaviour |
|---|---|
| `success` | Normal responses (default) |
| `slow` | Attendance POST delayed 4 s (still succeeds) |
| `timeout` | Attendance POST never answers quickly → client times out locally |
| `server_error` | HTTP 500 on POSTs |
| `conflict` | HTTP 409 on attendance POST → event becomes **Rejected** |
| `leave_rejected` | HTTP 422 on leave POST → server message shown in the form |

Stopping the mock server (or enabling airplane mode) exercises offline behaviour.

---

## 6. Business rules and sync design

* One check-in per company-local day; one check-out after a successful check-in; no second check-out; one session per day, no overnight shifts.
* GPS is captured for both events; both must be within the configured radius.
* The UI disables buttons and shows confirmation dialogs; the repository serialises writes and re-checks every rule, so simultaneous taps cannot create duplicates (tested).
* Company day/month keys and all displayed times come from `CompanyClock` using the configured UTC offset. Event timestamps are persisted in UTC.
* Leave types: Casual / Sick. Start date ≥ current company date; end ≥ start; reason ≥ 10 non-whitespace characters; requested calendar days ≤ balance; no overlap with Pending or Approved requests. Weekends/holidays are not excluded (per the assignment).
* Leave submission is queued locally even when offline and is sent by the sync engine when connectivity returns. Previously loaded leave requests remain viewable offline from Hive. Attendance is also always accepted offline.

### Event identity and idempotency

Every attendance event is created once with a UUID `eventId` and a monotonic local `sequence`; every leave request gets a stable `LRV-LOCAL-<uuid>` id. Neither changes on retry. The mock server stores processed attendance `eventId`s and leave request ids and returns the original receipt for a replay. Therefore:

* A retry after a timeout cannot create a second server record for either entity.
* Pending events are sent in `sequence` order; sync stops at the first network failure so check-out can never overtake check-in.
* Pending and Failed leave requests are sent oldest-first. A 422 response marks that local request **Rejected** with the real server message; network/server failures mark it **Failed** with an attempt count and error text and keep it for retry.
* Network/server failures leave records **Pending** with an attempt count and error text. Local records are never deleted by a failed sync.
* `Sync Now` is available in the app bar, attendance screen and profile. Connectivity return also triggers a silent sync. Background execution while terminated is out of scope (PDF §3).

### Validations that a production backend MUST repeat

Device checks are UX only. The production server must independently enforce:

1. **Duplicate prevention / event integrity** — verify a stable client event ID (idempotency key), reject unknown or reused IDs with different payloads, enforce one session per employee/company-day, and reject check-out without the matching stored check-in. Never trust client sequence/order.
2. **GPS/geofence** — recompute distance from the stored office coordinates using the server's own location source; detect impossible jumps, mock/spoofed locations and unrealistic speeds. Client coordinates are advisory.
3. **Timestamps and timezone** — derive the working day from the server's authoritative time and the contracted company timezone, reject back-dated/future timestamps, and verify check-out occurs after check-in. Do not accept a client-supplied `dateKey` as truth.
4. **Leave validation** — re-check dates, balance, overlaps and reason, and return field-level 422 errors (the app already surfaces server 422 messages).
5. **Authentication/authorisation and audit integrity** — the demo has no login; production must authenticate the employee, sign/hash event payloads, and keep an append-only audit trail.

---

## 7. Tests

```bash
flutter test
```

65 tests cover: check-out without check-in, duplicate/repeated check-in, duplicate check-out, successful check-in/check-out, geofence distances and configurable radius, inside/outside 200 m classification, unconfigured-office blocking, stale office reference detection, central Teqbae configuration and configured-office distance checks, runtime device office coordinates and DEBUG auto-generated test point, five-day demo history, company-timezone day keys, leave validation (including past start/end dates, overlap and calendar-day counting), cached-first dashboard loading / API failure / offline / deduplication, latest-five-record selection, sample leave-balance persistence and API overwrite, ViewModel rejection of past dates, local-first leave submission that API errors cannot block, 422 validation messages, 5xx and genuine network error classification, pending leave sync without duplicates, runtime API base URL validation/persistence/reset, development GPS simulation and release wiring, persistence and ordered sync of pending events, Failed-status retention after network failure, conflict → Rejected, idempotent retry after timeout, and widget tests for pending-sync / loading states and the disabled-past-date calendar.

---

## 8. Completed features, assumptions and limitations

**Completed:** dashboard (name/ID/department, today's status, times, duration, balance, latest five attendance records visible even offline, loading/empty/error/offline states); bottom navigation (Dashboard, Attendance, Leave, Profile); runtime API base URL setting for physical devices with saved override and retry; runtime DEBUG test office coordinates so Check In / Check Out work without rebuilding; local-first leave submission that cannot be blocked by API failures; GPS check-in/out with permission and geofence handling; DEBUG-only GPS Simulation card on the Attendance screen; offline Hive storage and event queue; automatic + manual sync with Pending/Synced/Failed/Rejected states; leave form with all PDF validations and history; six-endpoint mock HTTP API with six scenarios; Material 3 responsive UI; unit and widget tests.

**Assumptions:** one employee, no login; fixed company UTC offset; one session per day; no overnight shifts; all calendar days count as leave; background execution after termination out of scope; mock API data is in-memory and resets when the server restarts.

**Known limitations / production improvements:**
* No installable APK is committed here; build it with `flutter build apk --debug`. A 3–5 minute demonstration video is similarly a submission artifact rather than source code — record the sequence listed in §8 of the PDF.
* No push/background sync (Android work manager / iOS background tasks) — sync runs while the app is in the foreground.
* The mock server is in-memory, single-process and unauthenticated; replace it with a real service using HTTPS and auth tokens.
* Timezone is a fixed offset; use IANA zones (e.g. `Asia/Kolkata`) with DST rules for production.
* GPS simulation is deliberately unavailable in release builds; use device-level emulator location (or a physical device) for release-mode geofence verification.
* No biometric/device attestation for GPS spoof detection; no local database encryption; no field-level server error mapping into individual form fields.

**Time spent:** approximately 7 hours of implementation, testing and documentation, within the 8-hour limit.

**AI disclosure:** this submission was generated with the assistance of an AI coding agent (OpenCode, model Big Pickle). All files are present as plain source; review and modification are expected. No credentials or secrets are included.
