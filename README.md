# testflight-cleanup

A command-line tool to clean up inactive TestFlight beta testers from your App Store Connect app.

It pages through all beta testers for a given app, identifies those on outdated builds with zero sessions, and optionally removes them — helping you keep your tester list manageable.

## How It Works

For each page of testers, testflight-cleanup:

1. **Fetches** beta testers from the App Store Connect API (200 per page)
2. **Filters** testers whose latest installed build is below a given minimum
3. **Checks usage** metrics (session count) for each filtered tester over the last 30 days
4. **Deletes** testers with zero sessions (when dry run is disabled)

Processing happens page-by-page so progress is reported incrementally, and partial results are still printed if an API error occurs mid-run.

## Prerequisites

- **Swift 6.3+** / Xcode 16+
- An [App Store Connect API key](https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api) (Individual or Team)

## Setup

### 1. Environment Variables

Set the following environment variables, or place them in a `.env` file in the working directory:

| Variable | Required | Description |
|---|---|---|
| `APPSTORE_KEY_ID` | ✅ | Your API key ID (e.g. `ABC123DEFG`) |
| `APPSTORE_ISSUER_ID` | — | Issuer ID from App Store Connect (used for team keys) |
| `APPSTORE_PRIVATE_KEY` | — | The full `.p8` private key contents, inline (newlines as `\n`) |
| `PRIVATE_KEY_PATH` | — | Path to the `.p8` key file (relative or absolute) |

> If neither `APPSTORE_PRIVATE_KEY` nor `PRIVATE_KEY_PATH` is set, the tool looks for `AuthKey.p8` in the current working directory.

### 2. Build

```bash
swift build
```

## Usage

```bash
swift run beta-sweep \
  --app-id <YOUR_APP_ID> \
  --minimum-build-number <BUILD_NUMBER> \
  [--page-limit <LIMIT>] \
  [--dry-run <true|false>]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `--app-id` | The App Store Connect app ID to filter testers by | *required* |
| `--minimum-build-number` | Testers on a build below this number are candidates for removal | *required* |
| `--page-limit` | Maximum number of pages to process (useful for testing) | all pages |
| `--dry-run` | When `true`, no testers are actually deleted | `true` |

### Examples

**Preview which testers would be removed (dry run):**

```bash
swift run beta-sweep --app-id 1234567890 --minimum-build-number 150
```

**Remove inactive testers for real:**

```bash
swift run beta-sweep --app-id 1234567890 --minimum-build-number 150 --dry-run false
```

**Process only the first 3 pages:**

```bash
swift run beta-sweep --app-id 1234567890 --minimum-build-number 150 --page-limit 3
```

## Project Structure

```
Sources/testflight-cleanup/
├── testflight-cleanup.swift       # CLI entry point & main logic
├── AppStoreConnectService.swift   # API client, URL definitions, error types
├── AppStoreToken.swift            # ES256 JWT generation for authentication
├── BetaTestersResponse.swift      # Response models for beta testers endpoint
├── BetaTesterUsageResponse.swift  # Response models for usage metrics endpoint
└── Env.swift                      # .env file loader & environment helpers
```
