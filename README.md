# AmwalECR Flutter example

Sample till app for [`amwal_ecr`](https://github.com/amwal-pay/amwal-ecr-flutter),
aligned with the Android `ecr_sdk` simulator app and the nested
`amwal-ecr-flutter/example`.

Platforms: **Android**, **iOS**, and **Windows** (LAN Wi‑Fi + Web Service; USB
cable and app to app are Android-only).

Launcher / home-screen name: **ECR Flutter** (Android `android:label`, iOS
`CFBundleDisplayName`).

## Local package

By default this app depends on a sibling checkout so it stays in lockstep with
the plugin working tree (iOS `signOn` / `closeReceipt`, Android host, docs):

```yaml
amwal_ecr:
  path: ../amwal-ecr-flutter
```

Clone both repos next to each other under the same parent folder, then:

```bash
flutter pub get
flutter run              # default device
flutter run -d windows   # Windows host only
flutter run -d android
flutter run -d ios
```

**iOS sign-on and close-receipt** need that path dependency (Wi‑Fi). Published
pub.dev `0.3.1` still stubs iOS `signOn`; the working tree (`0.3.2`) wires both
`signOn` and `closeReceipt` like Android. Keep `path: ../amwal-ecr-flutter`
until you depend on a published build that includes those hosts.

For a **published** package, replace the path dependency with
`amwal_ecr: ^x.y.z` (or a `git:` ref) and run `flutter pub get`.

`flutter run -d windows` / `flutter build windows` work **only on a Windows
machine** (or Codemagic). They cannot run on macOS or Linux.

## Windows

### What works on Windows

| Mode | Windows |
|------|---------|
| App to app | ✘ — Android only |
| Wi‑Fi (LAN TCP, port 9100) | ✔ |
| Web Service (Hub REST) | ✔ |
| USB cable | ✘ — typed unsupported (Android only) |
| Bluetooth | ✘ |

`amwal_ecr` itself uses a pure-Dart Windows host — no extra ECR native plugin.
The example still depends on `flutter_secure_storage`, which **does** build a
native Windows plugin and needs Visual Studio ATL (below).

### Windows Visual Studio (required)

Without **C++ ATL**, MSBuild fails with a truncated error that ends in:

```text
…\flutter_secure_storage_windows_plugin.vcxproj]
No such file or directory
```

(often the real missing pieces are `atlstr.h` / `atls.lib`).

1. Open **Visual Studio Installer** → **Modify** on VS 2022
2. Workload: **Desktop development with C++**
3. Individual components: **C++ ATL for latest v143 build tools (x86 & x64)**
   (plus the Windows 10/11 SDK Flutter uses)
4. Clean and rebuild:

```bat
cd AmwalECR-flutter-example
flutter clean
rmdir /s /q build
flutter pub get
flutter doctor -v
flutter run -d windows
```

Also keep the project on local **NTFS** (not OneDrive-only sync, a network
share, or a ReFS Dev Drive) so plugin symlinks under
`windows\flutter\ephemeral\.plugin_symlinks` can be created.

If Debug still fails after ATL is installed:

```bat
flutter run -d windows --release
```

### Firewall and network

Allow the app for outbound TCP to the terminal and HTTPS to the Hub. The PC and
POS terminal must route to each other (guest Wi‑Fi with client isolation will
not work).

### Release zip locally

```bat
flutter build windows --release
:: Output under build\windows\x64\runner\Release\
```

## Live config (`--dart-define`)

Seeds fill **empty** secure-storage / preference slots and can register one
terminal when the list is empty — they never overwrite saved values.

| Define | Purpose |
|--------|---------|
| `ECR_ENVIRONMENT` | `SIT` / `UAT` / `PROD` |
| `ECR_WIFI_SECURE_HASH_KEY` | LAN signing secret (hex) |
| `ECR_WS_SECURE_HASH_KEY` | Web Service signing secret (hex) |
| `ECR_LIVE_MODE` | `wifi` (default) or `webService` |
| `ECR_LIVE_SERIAL` | Serial for the seeded terminal (required to seed) |
| `ECR_LIVE_TERMINAL_NAME` | Display name (default `Live terminal`) |
| `ECR_LIVE_IP` / `ECR_LIVE_PORT` | LAN address (port default `9100`) |
| `ECR_LIVE_MERCHANT_ID` / `ECR_LIVE_TERMINAL_ID` | Web Service ids |

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

The example owns persistence via `EcrSimulatorSettings` and
`flutter_secure_storage` (Keychain / Keystore / Windows credential store).
Transactions use `EcrSessions.open`.

## Native SDK pins (match nested example)

| Host | File | Current working-tree setting |
|------|------|------------------------------|
| Android ecr-sdk | `android/gradle.properties` | `ecrSdkDependency=maven` (`1.0.6` via plugin) |
| iOS AmwalECR | `ios/ecr_sdk.properties` | `ecrSdkDependency=project`, `ecrSdkVersion=0.2.3` |

Paths assume `AmwalECR-iOS-CocoaPods`, `AmwalECR-iOS-SPM`, and `ECR-simulator`
sit beside this repo. Set `ecrSdkDependency=cocoapods` (or `spm`) to use a
published AmwalECR instead of the local checkout.

Plugin docs for the Dart API live in
[`amwal-ecr-flutter/doc`](https://github.com/amwal-pay/amwal-ecr-flutter/tree/main/doc)
(`integration-guide.md`, `compatibility-matrix.md`).

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

Signing placeholders: `test/support/ecr_test_configs.dart` (`lan` /
`lanOther` / `webService`). Never commit real Amwal keys.
