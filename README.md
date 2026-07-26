# Apple Health to Garmin

Convert Apple Watch workouts to Garmin's FIT format with full-resolution heart rate, running power, stride length, vertical oscillation, and ground contact time.

Apple's "Export All Health Data" aggregates workout heart rate into low-resolution chunks. This tool bypasses that by reading HealthKit directly on the iPhone via a small sideloaded app, then converting the full-resolution data to FIT files for Garmin Connect.

## How it works

```mermaid
graph LR
    A[HealthKit on iPhone] -->|HTTP JSON| B[fetch-healthkit]
    B -->|apple_health_export/*.json| C[convert-to-fit]
    C -->|fit_files/*.fit| D[upload-to-garmin]
    D -->|Garmin API| E[Garmin Connect]
```

1. **iOS app** serves workout data from HealthKit over a local HTTP server
2. **fetch-healthkit** pulls all workouts (metrics + GPS) from the phone to your Mac
3. **convert-to-fit** produces FIT files with linearly interpolated metrics
4. **upload-to-garmin** pushes FIT files to Garmin Connect via the API

## Requirements

- iPhone with Apple Health data
- Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835) (for sideloading the iOS app)
- [uv](https://docs.astral.sh/uv/) (Python package manager)

## Quick start

```bash
git clone https://github.com/brtkwr/apple-health-export.git
cd apple-health-export
```

### 1. Install the iOS app

1. Open `HealthExport.xcodeproj` in Xcode
2. Set your development team in **Signing & Capabilities**
3. Connect your iPhone via USB and hit **Run**
4. On your iPhone: **Settings > General > VPN & Device Management** → trust the developer certificate

### Multi-server workout export (iOS)

The app can POST full-resolution workout JSON to one or more remote destination servers. Configure servers under **Destination Servers** in the app.

#### Destination server configuration

| Field | Description |
| ----- | ----------- |
| **Name** | Display label only |
| **Host or URL** | Hostname (`api.example.com`) or full URL (`https://api.example.com:8443/v1`) |
| **Port** | Optional when not already in the host/URL (1–65535) |
| **Upload path** | POST path; defaults to `/workouts`. If the host/URL already includes a path and this field is left at the default, the embedded path is used |
| **Use HTTP (insecure)** | Off by default (HTTPS). When enabled, the app shows a warning that traffic is unencrypted |
| **Enabled** | Only enabled servers receive exports |
| **Authentication** | None, Bearer token, or custom header name + secret |

Auth secrets are stored in the iOS Keychain (per server). Server metadata is stored in UserDefaults; secrets are never written there or logged.

**HTTPS vs HTTP:** HTTPS is the default. Plain HTTP may be blocked by iOS App Transport Security unless the host is eligible (for example, a local network address). If blocked, the app reports: `HTTP blocked by App Transport Security. Use HTTPS or a local network host.` Do not assume arbitrary HTTP endpoints will work.

#### Exporting workouts

- **Push Latest Workout to All Servers** — reads the most recent HealthKit workout and POSTs it concurrently to every enabled server.
- **Push Selected Workouts** (per server) — pick from the **100 most recent** workouts (newest first) and push to that server in **Concurrent** or **Sequential** mode.

Each delivery attempt is recorded in per-server **Push History** (status, HTTP code, timing, workout snapshot). History is persisted on device (up to 500 entries total).

#### HealthKit access requirements

Exports read HealthKit while the app is in use. Keep the phone **unlocked and the app in the foreground** — HealthKit data is not available when the screen is locked (same constraint as the Mac fetch workflow below). **Automatic background export is not implemented.**

#### Outbound POST contract

Each workout is sent as a single `POST` to the configured upload URL (default `https://<host>/workouts`).

**Request headers**

| Header | Value |
| ------ | ----- |
| `Content-Type` | `application/json` |
| `Idempotency-Key` | HealthKit workout UUID (stable per workout) |
| `X-Workout-Source` | `apple-health-export` |
| `Authorization` | `Bearer <token>` when auth type is Bearer (only if a secret is saved) |
| *(custom)* | Secret value in the configured header name when auth type is Custom Header |

Request timeout: 60 seconds.

**Success:** HTTP `2xx` is treated as delivered. Any other status or transport error is recorded as a failure (response body snippet, up to 500 characters, may be stored in history).

**Idempotency-Key:** Set to the workout's HealthKit `uuid` string. Re-sending the same workout sends the same key so receivers can deduplicate. The key is per workout, not per delivery attempt or server.

**Example JSON body**

```json
{
  "exported_at": "2026-01-01T10:31:00Z",
  "metrics": {
    "heart_rate": [
      {
        "date": "2026-01-01T10:00:00Z",
        "timestamp": 1735732800,
        "value": 145
      }
    ],
    "route": [
      {
        "altitude": 10,
        "course": 90,
        "date": "2026-01-01T10:00:00Z",
        "horizontal_accuracy": 5,
        "latitude": 37,
        "longitude": -122,
        "speed": 3.5,
        "timestamp": 1735732800,
        "vertical_accuracy": 3
      }
    ]
  },
  "schema_version": 1,
  "source": "apple_health_export_ios",
  "source_workout_id": "550e8400-e29b-41d4-a716-446655440000",
  "workout": {
    "activity_type": "running",
    "activity_type_raw": 37,
    "duration_seconds": 1800,
    "end_date": "2026-01-01T10:30:00Z",
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Morning Run",
    "source": "Apple Watch",
    "start_date": "2026-01-01T10:00:00Z",
    "total_distance_metres": 5000,
    "total_energy_kcal": 420
  }
}
```

Keys are sorted in the encoded payload. Metric series (`heart_rate`, `running_power`, `running_speed`, `stride_length`, `vertical_oscillation`, `ground_contact_time`, `route`) are omitted when empty.

### 2. Fetch workouts from the phone

Open the app on your iPhone, tap **Start**, then from your Mac:

```bash
uv run fetch-healthkit <iphone-ip>
```

This pulls all Apple Watch workouts with full-resolution metrics and GPS routes into `apple_health_export/`. Keep the phone screen on while fetching — HealthKit data is inaccessible when the screen is locked.

### 3. Convert to FIT

```bash
uv run convert-to-fit apple_health_export
```

FIT files are written to `fit_files/`, organised by year and month.

Filter by activity type:

```bash
uv run convert-to-fit apple_health_export --activity running
```

### 4. Upload to Garmin Connect

```bash
# First time: log in and save tokens
uv run login-garmin

# Upload all FIT files
uv run upload-to-garmin fit_files
```

Set `GARMIN_EMAIL` and `GARMIN_PASSWORD` as environment variables. MFA is supported — you'll be prompted for the code on first login. Tokens are saved to `~/.garmin_tokens/` for subsequent runs.

Use `--dry-run` to preview without uploading:

```bash
uv run upload-to-garmin fit_files --dry-run
```

Or import manually: go to [Garmin Connect](https://connect.garmin.com), click **"+"** → Import Data, and upload your FIT files.

## What gets exported

| Data                 | Included |
| -------------------- | -------- |
| GPS coordinates      | Yes      |
| Heart rate           | Yes      |
| Distance             | Yes      |
| Calories             | Yes      |
| Altitude             | Yes      |
| Running power        | Yes      |
| Stride length        | Yes      |
| Vertical oscillation | Yes      |
| Ground contact time  | Yes      |
| Running speed        | Yes      |

## Why not use Apple's XML export?

Apple's "Export All Health Data" stores workout heart rate as aggregated records spanning ~15 minute windows. A 65-minute run might only have 23 HR data points in the export. The same workout viewed on Strava (which reads HealthKit directly) shows 513 data points.

This is a [known limitation](https://discussions.apple.com/thread/253843222) of Apple's XML export. The full-resolution data exists on the phone via `HKQuantitySeriesSampleQuery` — this tool accesses it.

## Local HTTP API (on-device export)

The iOS app can also serve JSON on port 8080 for Mac-side fetching (see step 2 above):

| Endpoint               | Description                           |
| ---------------------- | ------------------------------------- |
| `GET /workouts`        | List all workouts with metadata       |
| `GET /workouts/{index}` | All metrics + GPS route for a workout |

## Development

### Mock server

For local development and testing without a phone:

```bash
python3 tests/mock_server.py
```

Serves sample workouts on `http://localhost:8080` with the same API as the iOS app.

### Tests

```bash
uv run pytest tests/ -v
```

### CI

Tests run on GitHub Actions for Python 3.11–3.14. Coverage is reported on PRs. iOS build can be triggered manually via workflow dispatch.

## License

MIT
