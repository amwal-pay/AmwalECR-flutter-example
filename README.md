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
flutter run -d windows   # Windows host only
flutter run -d android
flutter run -d ios
```

For a **published** package, replace the path dependency with
`amwal_ecr: ^x.y.z` (or a `git:` ref) and run `flutter pub get`.

`flutter run -d windows` / `flutter build windows` work **only on a Windows
machine** (or Codemagic). They cannot run on macOS or Linux.

## Windows

### What works on Windows

| Mode | Windows |
|------|---------|
| Wi‑Fi (LAN TCP, default port `9100`) | ✔ |
| Web Service (Hub REST) | ✔ |
| USB cable | ✘ — marked unsupported in the UI (Android only) |
| Bluetooth | ✘ |

`amwal_ecr` on Windows is a pure-Dart host (`AmwalEcrWindows`) — same Dart API
as mobile, no separate ECR native binary. The example also uses
`flutter_secure_storage`, which builds a native Windows plugin and needs
Visual Studio **C++ ATL**.

### Windows Visual Studio (required)

Without ATL, MSBuild fails with a truncated error that ends in:

```text
…\flutter_secure_storage_windows_plugin.vcxproj]
No such file or directory
```

(often the real missing pieces are `atlstr.h` / `atls.lib`).

1. Open **Visual Studio Installer** → **Modify** on VS 2022
2. Workload: **Desktop development with C++**
3. Individual components — enable **C++ ATL for latest v143 build tools (x86 & x64)**
   (and the Windows 10/11 SDK Flutter already uses)
4. Clean and rebuild:

```bat
cd AmwalECR-flutter-example
flutter clean
rmdir /s /q build
flutter pub get
flutter doctor -v
flutter run -d windows
```

Also put the project on a local **NTFS** drive (not OneDrive-only sync, a
network share, or a ReFS Dev Drive) so plugin symlinks under
`windows\flutter\ephemeral\.plugin_symlinks` can be created.

If Debug still fails after ATL is installed, try Release once:

```bat
flutter run -d windows --release
```

### Firewall and network

Allow the app through Windows Firewall for outbound TCP to the terminal and
HTTPS to the Hub. The PC and the POS terminal must be able to route to each
other (guest Wi‑Fi with client isolation will not work).

### Release zip locally

```bat
flutter build windows --release
:: Output under build\windows\x64\runner\Release\
```

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

`codemagic.yaml` in this repo:

| Workflow | When | Artifact |
|----------|------|----------|
| `example-windows` | tag `example-windows-*` or push to `release/example` | Windows Release zip |
| `example-android` | push / PR | Debug APK |

CI clones sibling [`amwal-ecr-flutter`](https://github.com/amwal-pay/amwal-ecr-flutter)
so `path: ../amwal-ecr-flutter` resolves. The plugin repo also has its own
`example-windows` workflow for the nested `example/`.

```bash
git tag example-windows-1 && git push origin example-windows-1
```

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
