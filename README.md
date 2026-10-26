# Amwal ECR Flutter till

A working till built on [`amwal_ecr`](https://github.com/amwal-pay/amwal-ecr-flutter): register the terminals you own, pick one, and run sale, void, refund, inquiry, e-receipt, close receipt, and manual settlement against it — and, app to app, print a receipt image on the terminal's printer. It runs on Android, iOS and Windows. Card data stays on the terminal.

It uses `amwal_ecr` **0.5.0** from a sibling checkout, with `ecr-sdk` **1.0.11** on Android and `AmwalECR` **0.3.0** on iOS. Register a terminal, pick it, run the operation, then read the result. It is the same app as `amwal-ecr-flutter/example` and follows the Android sample till; read it as much as run it — it is the reference for how the package is used.

Launcher name: **ECR Flutter**.

## Install

- Flutter, Dart 3. Android, iOS 17 or later, Windows.
- Clone this repository and [`amwal-ecr-flutter`](https://github.com/amwal-pay/amwal-ecr-flutter) next to each other under the same parent folder. The app depends on the plugin's working tree:

```yaml
amwal_ecr:
  path: ../amwal-ecr-flutter
```

```bash
flutter pub get
flutter run              # default device
flutter run -d android
flutter run -d ios
flutter run -d windows   # on a Windows machine only
```

For a published package, replace the path with `amwal_ecr: 0.5.0` and run `flutter pub get`. Windows needs Visual Studio's **C++ ATL**; see [Windows](#windows).

## Open a session

<a id="ecropenedsession"></a>

On the **Terminals** screen, register each terminal once by its serial number and its mode, which is the terminal's TMS `ecrMode`. The **Transaction** screen keeps only the serial; picking a terminal loads its mode, checks its settings, and shows what is missing before you pay. Signing keys and the environment are on the Terminals screen too: one key for Wi-Fi, USB, and app to app, another for Web Service.

The app opens the session for the chosen terminal in `lib/data/terminal_sessions.dart`:

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: switch (registered.mode) {
    EcrMode.wifi => registered.ipAddress,            // from the terminal's idle screen
    EcrMode.appToApp => EcrPaymentApp.packageName,   // com.amwalpay.pos, on this device
    _ => '',                                         // USB cable and Web Service have no address
  },
  serialNumber: registered.serialNumber,
  transport: transport,                              // the mode's EcrTransport
  config: active.ecrConfig,                          // the key and ids for that mode
).terminal;
```

### Wi-Fi implementation

Register the IP address and port the terminal shows on its idle screen, under the card logos. The port is 9100. The phone or PC and the terminal must be on the same Wi-Fi.

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '192.168.1.50',
  serialNumber: 'P653200085189',
  transport: EcrTransport.wifi,
  config: EcrConfig(secureHashKey: wifiKey),
).terminal;
```

### Web Service implementation

Register the merchant id and terminal id, and set the environment (SIT, UAT, PROD) and the Web Service key.

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '',
  serialNumber: 'P653200008251',
  transport: EcrTransport.webService,
  config: EcrConfig(
    secureHashKey: webServiceKey,
    merchantId: '13593',
    terminalId: '101311',
    environment: EcrEnvironment.uat,
  ),
).terminal;
```

### USB cable implementation

Android only. Connect the cable; the phone is the USB host and the terminal is the accessory. There is no address to register. The key is the Wi-Fi key.

```dart
final EcrTerminal terminal = EcrSessions.open(
  host: '',
  serialNumber: 'P653200085189',
  transport: EcrTransport.usbCable,
  config: EcrConfig(secureHashKey: wifiKey),
).terminal;
```

### App to app implementation

Android only, with the app installed on the terminal itself. There is no address: the app hands each request to the payment app `com.amwalpay.pos`. The app's `AndroidManifest.xml` already declares it in `<queries>`; without that, Android 11 and later hide the payment app. The key is the Wi-Fi key.

```dart
final EcrTerminal terminal = EcrTerminal.appToApp(
  serialNumber: 'P653200085189',
  config: EcrConfig(secureHashKey: wifiKey),
);
```

The answer comes back when the terminal's receipt closes: when the cashier closes it, or 15 seconds after it appears. The app does not sign on automatically over app to app, because each sign-on would bring the payment app to the front.

#### Print

On an approved app-to-app result, the outcome dialog offers **Print receipt**. The app builds a bilingual PNG, 384 pixels wide and at most 15 MB, from the operation (`lib/print/operation_receipt_image.dart`), and the payment app's status and message come back in a **Print receipt** popup.

```dart
final EcrPrintOutcome outcome = await terminal.printReceipt(
  imagePng: receiptPng,                        // 384 px wide, ≤ 15 MB
  merchantReference: approved.merchantReference,
);

switch (outcome.status) {
  case EcrPrintStatus.successful:
    showToCashier('Printed');
  case EcrPrintStatus.failed:
    showToCashier(outcome.message);            // as the payment app sent it
}
```

The full rules are in [Print receipt (app to app)](#print-receipt-app-to-app).

## Operations

The **Transaction** screen offers sale, void, refund, and inquiry; the fields follow the type. The amount field works like the terminal's: digits shift in from the right against three fixed decimals, and it reads `0.000` when empty. The merchant reference field is optional; leave it blank and the package generates one.

While an operation is in flight the screen counts down the response timeout (120 s Wi-Fi, 130 s Web Service) and offers **Cancel operation**. Cancelling ends the wait only; it does not undo a payment.

### Sale

In the app: choose **Sale**, key the amount, pick the terminal, **Start transaction**. The cardholder presents the card on the terminal.

```dart
const String reference = 'ORDER-1001-1';
save(reference);   // before the call, so a lost answer can still be looked up

final EcrResult result = await terminal.sale(
  EcrAmount.parse('1.234'),
  merchantReference: reference,
);

switch (result) {
  case EcrApproved():
    record(reference, result.amount, result.rrn, result.authCode, result.maskedPan);
    if (result.partialApproval) {
      // The bank took less than you asked: collect the rest another way.
      collectBalance(asked: result.requestedAmount, taken: result.amount);
    }
  case EcrDeclined():
    showToCashier(result.reason);   // finished: nothing was taken
  case EcrFailed() when result.settled:
    // The package already asked the terminal what happened, and it found the sale.
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    // The request went out and no answer settled it: the money may have moved.
    markUnresolved(reference);
  case EcrFailed():
    showToCashier(result.failure.message);   // nothing was sent, so nothing was taken
}
```

### Void

In the app: choose **Void**, enter the sale's receipt number. The amount field is dimmed: a void takes the sale's full amount. No card.

```dart
const String voidReference = 'ORDER-1001-V1';
save(voidReference);

final EcrResult result = await terminal.voidTransaction(
  '000123',                       // the receipt number of the sale
  originalTerminalId: '',         // blank: the sale was taken on this terminal
  merchantReference: voidReference,
);

switch (result) {
  case EcrApproved():
    // The sale's full amount went back. A void has no auth code of its own.
    markVoided(order: 'ORDER-1001', rrn: result.rrn);
  case EcrDeclined():
    // For example the sale was already voided, or is no longer in the open batch.
    showToCashier(result.reason);
  case EcrFailed() when result.settled:
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    markUnresolved(voidReference);
  case EcrFailed():
    showToCashier(result.failure.message);
}
```

### Refund

In the app: choose **Refund**, key the amount, enter the original's receipt number and pick the day it was taken. The cardholder presents the card.

```dart
const String refundReference = 'ORDER-1001-R1';
save(refundReference);

final EcrResult result = await terminal.refund(
  EcrAmount.parse('1.000'),       // all or part of the original
  receiptNumber: '000123',        // the original's receipt number
  transactionDate: '20261019',    // the day the original was taken
  merchantReference: refundReference,
);

switch (result) {
  case EcrApproved():
    recordRefund(order: 'ORDER-1001', amount: result.amount, rrn: result.rrn);
  case EcrDeclined():
    // For example more than is left to refund, or the card does not match.
    showToCashier(result.reason);
  case EcrFailed() when result.settled:
    apply(result.recoveredTransaction!);
  case EcrFailed() when result.outcomeIsUnknown:
    markUnresolved(refundReference);
  case EcrFailed():
    showToCashier(result.failure.message);
}
```

### Inquiry by receipt number

In the app: choose **Inquiry**, enter the receipt number and the day. The result shows the receipt number, type, card, amount, status, and time; the rest of the answer is under **Raw response**, with a copy button. No card, no money, and the terminal answers it even mid-payment.

```dart
final EcrInquiry inquiry = await terminal.inquire(
  receiptNumber: '000123',
  transactionDate: '20261019',
);

switch (inquiry) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    showToCashier('${transaction.type} ${transaction.status} '
        '${transaction.amount} ${transaction.currency} · card ${transaction.maskedPan}');
    // What the terminal would accept for this transaction right now.
    voidEnabled = transaction.canVoid;
    refundEnabled = transaction.canRefund;
  case EcrInquiryNotFound(:final String reason):
    showToCashier(reason.isEmpty ? 'No transaction with that receipt number on that day' : reason);
  case EcrInquiryFailed(:final EcrFailure failure):
    showToCashier(failure.message);   // the lookup failed: ask again
}
```

### Inquiry by merchant reference

In the app: choose **Inquiry**, turn on **Look up by reference**, and enter the reference the sale was sent with. This is the lookup after an answer that never came: you still have the reference, and you do not yet have a receipt number. The inquiry keeps its own reference; only the original names the sale being looked up.

```dart
const String reference = 'ORDER-1001-1';   // the sale whose answer never came

switch (await terminal.inquireByReference(reference)) {
  case EcrInquiryFound(:final EcrTransaction transaction):
    switch (transaction.status.toLowerCase()) {
      case 'approved':
        apply(transaction);          // it went through: record it, do not charge again
      case 'declined':
        releaseOrder(reference);     // it did not: a new attempt needs a new reference
      default:
        markUnresolved(reference);   // voided, reversed, or anything else: leave it open
    }
  case EcrInquiryNotFound():
    // No record is not proof nothing was taken. Confirm before you charge again.
    markUnresolved(reference);
  case EcrInquiryFailed():
    retryLater(reference);           // the lookup failed: ask again
}
```

### E-receipt

In the app: on an inquiry result, tap the receipt button. The app draws the receipt URL as a QR code on the device; the customer scans it and reads the receipt on their own phone. Wi-Fi, USB, and app to app.

```dart
final EcrReceipt receipt = await terminal.receipt(
  receiptNumber: '000123',
  transactionDate: '20261019',
);

switch (receipt) {
  case EcrReceiptReady(:final String url):
    showQr(url);                     // the customer reads the receipt on their own phone
  case EcrReceiptUnavailable(:final String reason):
    showToCashier(reason);           // no receipt to show: unknown transaction, or Web Service
  case EcrReceiptFailed(:final EcrFailure failure):
    showToCashier(failure.message);  // ask again
}
```

### Close receipt

<a id="close-receipt"></a>

In the app: **Close receipt** is a button on the result, beside Close. It clears the terminal's screen; Close only dismisses the app's dialog. Wi-Fi and USB only. The terminal also puts its receipt away by itself 15 seconds after it appears; this clears it sooner.

```dart
// From the cashier's Close receipt button, once they are finished with the sale.
switch (await terminal.closeReceipt()) {
  case EcrReceiptClosedIdle():
    break;                                           // the terminal is on its idle screen
  case EcrReceiptClosedRefused(:final String reason):
    showToCashier(reason);                           // firmware has no CLOSE_RECEIPT; leave the receipt up
  case EcrReceiptClosedFailed(:final EcrFailure failure):
    showToCashier(failure.message);                  // nothing changed; the call can be repeated
}
```

### Manual settlement

In the app: **Manual settlement** is a button under Start transaction (Wi-Fi, USB, and app to app). It asks you to confirm — the terminal does not — then shows the batch totals. The terminal prints the settlement receipt when its profile prints, and puts the summary away after 15 seconds.

```dart
if (!await confirm('Settle the terminal now? It closes the current batch.')) return;

switch (await terminal.settlement()) {
  case final EcrSettlementSettled settled:
    showToCashier('Batch ${settled.batchId} closed: ${settled.totalTransactions} '
        'transactions, net ${settled.netAmount} ${settled.currency}');
    // Every type is present, with zeros where the batch had none.
    settled.totals.forEach((String type, EcrSettlementTotal total) =>
        showToCashier('$type × ${total.count}: ${total.amount}'));
  case EcrSettlementNothingToSettle(:final String message):
    showToCashier(message);                          // nothing was open
  case EcrSettlementNotSettled(:final String status, :final String reason,
        :final int? uploadedTransactions):
    switch (status) {
      case 'MISMATCH':
        showToCashier('Not settled: the backend counted a different number '
            '($uploadedTransactions uploaded)');
      case 'SESSION_EXPIRED':
        showToCashier('Sign the terminal in again, then settle');
      default:
        showToCashier(reason);   // FAILED, or refused before it started (96, 91, 12)
    }
  case EcrSettlementFailed(:final EcrFailure failure):
    showToCashier(failure.message);                  // safe to ask again
}
```

### Print receipt (app to app)

<a id="print-receipt-app-to-app"></a>

In the app: on an approved app-to-app result, tap **Print receipt**. Android app to app only; Wi-Fi, USB, and Web Service never show the button.

The image is a PNG exactly **384 pixels wide**, any height, at most **15 MB**. A wrong width or a bigger image never reaches the payment app. The app builds it from the operation's result in `lib/print/`; it does not rely on the payment app reprinting its last transaction. One print at a time.

```dart
final EcrPrintOutcome outcome = await terminal.printReceipt(
  imagePng: receiptPng,                        // 384 px wide, ≤ 15 MB
  merchantReference: approved.merchantReference,
);

switch (outcome.status) {
  case EcrPrintStatus.successful:
    showToCashier('Printed');
  case EcrPrintStatus.failed:
    showToCashier(outcome.message);            // as the payment app sent it
}
```

`status` and `message` are separate fields, shown separately in the popup. A failed print leaves the sale exactly as it was, and you can print again.

### Sign-on

In the app: runs by itself when you pick a Wi-Fi or USB terminal, and shows **Terminal ready** with what it permits, or why it cannot take work. The transaction types narrow to what the terminal's profile allows.

```dart
switch (await terminal.signOn()) {
  case EcrSignOnAvailable(:final EcrTerminalCapabilities capabilities):
    // Offer only what the terminal's profile permits, within its limits.
    showOperations(capabilities.permitted.map((p) => p.type).toList());
    for (final EcrPermittedTransaction p in capabilities.permitted) {
      if (p.type == EcrTransactionType.sale) setSaleLimits(min: p.minAmount, max: p.maxAmount);
    }
  case EcrSignOnUnavailable(:final String reason):
    // The terminal is there but cannot take work now — mid-transaction, or not in ECR mode.
    showToCashier(reason);
  case EcrSignOnFailed(:final EcrFailure failure):
    showToCashier(failure.message);
}
```

### Reachability

In the app: checked before every operation on Wi-Fi, USB, and app to app. A terminal that does not answer is reported with what to check, and nothing is sent.

```dart
final EcrReachability probe = await terminal.probeReachability();
if (!probe.reachable) {
  showToCashier('${probe.endpoint} is not reachable: ${probe.error}');
}
```

## Read the result

<a id="handle-the-result"></a>

| The app shows | Means |
|---|---|
| **Approved** | Money moved. Amount, auth code, and card. A void shows no auth code: it has none of its own. |
| **Partially approved** | The bank took less than asked. Collect the difference by another means. |
| **Declined** | The terminal answered and refused, with its reason. Nothing was taken. |
| **Not completed** | No answer settled it: timeout, lost connection, unreadable answer, or cancelled. The payment may have completed. Inquire by reference before trying again. |
| Inquiry result | The transaction's own status, not the lookup's: finding a declined sale is a successful inquiry. |
| **Settled** / **Nothing to settle** / **Not settled** | The batch closed with its totals, there was nothing open, or it is still open and why. |

The package's result types behind each of these are in the [plugin README](https://github.com/amwal-pay/amwal-ecr-flutter#read-the-result).

## Important notes

### Resolve an unknown outcome

**Not completed is not a decline.** The terminal may have taken the payment and been unable to say so. Do not start the sale again: choose **Inquiry**, turn on **Look up by reference**, and enter the sale's reference. `Approved` means it went through; `Declined` means it did not, and a new attempt needs a new reference; anything else, or no record, stays unresolved until confirmed on the terminal.

### Merchant reference, receipt number, amounts

The merchant reference is 32 characters at most, without space, `&`, or `=`. A void and a refund each get their own. The receipt number is the STAN on the receipt, unique on one terminal for one day, so refund, inquiry by receipt number, and e-receipt also need the day. Amounts are three-decimal OMR; the bounds are in `lib/ui/amount_limits.dart`.

### Keys

`EcrSimulatorSettings` keeps the keys in `flutter_secure_storage` (Keychain, Keystore, or the Windows credential store), never in plaintext preferences. Wi-Fi, USB, and app to app share one key; Web Service has its own. Never commit real Amwal keys.

### Live config (`--dart-define`)

Seeds fill **empty** slots and can register one terminal when the list is empty. They never overwrite saved values.

| Define | Purpose |
|---|---|
| `ECR_ENVIRONMENT` | `SIT` / `UAT` / `PROD` |
| `ECR_WIFI_SECURE_HASH_KEY` | Wi-Fi signing secret (hex) |
| `ECR_WS_SECURE_HASH_KEY` | Web Service signing secret (hex) |
| `ECR_LIVE_MODE` | `wifi` (default) or `webService` |
| `ECR_LIVE_SERIAL` | Serial for the seeded terminal (required to seed) |
| `ECR_LIVE_TERMINAL_NAME` | Display name (default `Live terminal`) |
| `ECR_LIVE_IP` / `ECR_LIVE_PORT` | Wi-Fi address (port default `9100`) |
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

### What each platform can do

| | Android | iOS | Windows |
|---|---|---|---|
| Wi-Fi | ✔ | ✔ | ✔ |
| Web Service | ✔ | ✔ | ✔ |
| USB cable | ✔ | ✘ | ✘ |
| App to app, Print receipt | ✔ | ✘ | ✘ |
| Manual settlement | ✔ | ✘ | ✔ Wi-Fi |
| Bluetooth | ✘ | ✘ | ✘ |

---

## Windows

`amwal_ecr` uses a pure-Dart host on Windows, with no native ECR plugin. The app still depends on `flutter_secure_storage`, which builds a native Windows plugin and needs Visual Studio's ATL.

### Windows Visual Studio (required)

<a id="windows-visual-studio-required"></a>

Without **C++ ATL**, MSBuild fails with a truncated error ending in `flutter_secure_storage_windows_plugin.vcxproj` (the real missing pieces are `atlstr.h` / `atls.lib`).

1. Open **Visual Studio Installer** → **Modify** on VS 2022.
2. Workload: **Desktop development with C++**.
3. Individual components: **C++ ATL for latest v143 build tools (x86 & x64)**, plus the Windows SDK Flutter uses.
4. Clean and rebuild:

```bat
flutter clean
rmdir /s /q build
flutter pub get
flutter run -d windows
```

Keep the project on local **NTFS** — not OneDrive-only sync, a network share, or a ReFS Dev Drive — so plugin symlinks under `windows\flutter\ephemeral\.plugin_symlinks` can be created. If Debug still fails after ATL is installed, try `flutter run -d windows --release`.

### Firewall and network

Allow the app for outbound TCP to the terminal and HTTPS to the Hub. The PC and the terminal must route to each other; guest Wi-Fi with client isolation does not work.

### Release zip locally

```bat
flutter build windows --release
:: Output under build\windows\x64\runner\Release\
```

## Native SDK pins

| Host | File | Setting |
|---|---|---|
| Android `ecr-sdk` | the plugin's `amwal-ecr-flutter/android/gradle.properties` | **1.0.11** (`ecrSdkDependency` in this app's `android/gradle.properties` may be `maven` or `project`) |
| iOS `AmwalECR` | `ios/ecr_sdk.properties` | `ecrSdkVersion=0.3.0` |

Paths assume `AmwalECR-iOS-CocoaPods`, `AmwalECR-iOS-SPM`, and `ECR-simulator` sit beside this repository. Set `ecrSdkDependency=cocoapods` (or `spm`) to use a published `AmwalECR`. The package's own documentation is in [`amwal-ecr-flutter/doc`](https://github.com/amwal-pay/amwal-ecr-flutter/tree/main/doc).

## Codemagic

| Workflow | When | Artifact |
|---|---|---|
| `example-windows` | tag `example-windows-*` or push to `release/example` | Windows Release zip |
| `example-android` | push / PR | Debug APK |

CI clones the sibling `amwal-ecr-flutter` so `path: ../amwal-ecr-flutter` resolves.

```bash
git tag example-windows-1 && git push origin example-windows-1
```

## Tests

```bash
flutter test
```

Signing placeholders come from `test/support/ecr_test_configs.dart`. Never commit real Amwal keys.
