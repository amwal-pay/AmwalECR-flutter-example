# AmwalECR Flutter example

Sample till app for [`amwal_ecr`](https://github.com/amwal-pay/amwal-ecr-flutter),
aligned with the Android `ecr_sdk` simulator app.

Platforms: **Android**, **iOS**, and **Windows** (LAN Wi‑Fi + Web Service; USB
cable is Android-only).

## Local package

By default this app depends on a sibling checkout:

```yaml
amwal_ecr:
  path: ../amwal-ecr-flutter
```

Clone both repos next to each other under the same parent folder, then:

```bash
flutter pub get
flutter run -d windows   # or chrome-less: windows / android / ios
```

To use a **published** package instead, replace the path dependency with a
version constraint (`amwal_ecr: ^x.y.z`) and run `flutter pub get`.

## Live config (`--dart-define`)

Empty Settings stay empty unless you pass compile-time seeds. Seeds fill
**empty** secure-storage / preference slots and can register one terminal when
the terminal list is empty — they never overwrite saved values.

| Define | Purpose |
|--------|---------|
| `ECR_ENVIRONMENT` | `SIT` / `UAT` / `PROD` |
| `ECR_WIFI_SECURE_HASH_KEY` | LAN (Wi‑Fi / USB) signing secret (hex) |
| `ECR_WS_SECURE_HASH_KEY` | Web Service signing secret (hex) |
| `ECR_LIVE_MODE` | `wifi` (default) or `webService` |
| `ECR_LIVE_SERIAL` | Serial for the seeded terminal (required to seed) |
| `ECR_LIVE_TERMINAL_NAME` | Display name (default `Live terminal`) |
| `ECR_LIVE_IP` / `ECR_LIVE_PORT` | LAN address (port default `9100`) |
| `ECR_LIVE_MERCHANT_ID` / `ECR_LIVE_TERMINAL_ID` | Web Service ids |

Example (Windows + live Wi‑Fi terminal):

```bash
flutter run -d windows \
  --dart-define=ECR_ENVIRONMENT=SIT \
  --dart-define=ECR_WIFI_SECURE_HASH_KEY=<hex> \
  --dart-define=ECR_LIVE_MODE=wifi \
  --dart-define=ECR_LIVE_SERIAL=SN123 \
  --dart-define=ECR_LIVE_IP=192.168.1.50 \
  --dart-define=ECR_LIVE_PORT=9100
```

## Secure hash keys

The example **owns** persistence and picks one secret per terminal mode via
`EcrSimulatorSettings.secureHashKeyFor`, then assigns it to
`EcrConfig.secureHashKey`. The plugin does not store or choose keys.

Secrets are stored with **`flutter_secure_storage`** (Keychain / Keystore /
Windows credential store). Environment preference stays in SharedPreferences.
On first load after upgrade, any plaintext SharedPreferences secrets are
migrated once and cleared.

Transactions open a client through **`EcrSessions.open`** so LAN / USB / Web
Service share one path for sale, inquiry, and receipt.

## Codemagic

`codemagic.yaml` in this repo builds the Windows release zip (`example-windows`)
and the Android debug APK (`example-android`). The plugin repo
[`amwal-ecr-flutter`](https://github.com/amwal-pay/amwal-ecr-flutter) also has
an `example-windows` workflow that builds its nested `example/` against the
local package path.

## Tests

```bash
flutter test
```

Unit-test signing placeholders live in `test/support/ecr_test_configs.dart`
(same structure as `ecr_sdk` `EcrTestConfigs`):

- `SECURE_HASH_KEY_ECR_WIFI`
- `SECURE_HASH_KEY_ECR_WIFI_OTHER`
- `SECURE_HASH_KEY_WEBSERVICE`

Exposed as `lan` / `lanOther` / `webService`. Never commit real Amwal keys.
