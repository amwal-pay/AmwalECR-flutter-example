# AmwalECR Flutter example

Sample till app for [`amwal_ecr`](https://github.com/amwal-pay/amwal-ecr-flutter),
aligned with the Android `ecr_sdk` simulator app.

## Secure hash keys

The example **owns** persistence and picks one secret per terminal mode via
`EcrSimulatorSettings.secureHashKeyFor`, then assigns it to
`EcrConfig.secureHashKey`. The plugin does not store or choose keys.

Secrets are stored with **`flutter_secure_storage`** (iOS Keychain / Android
Keystore-backed). Environment preference stays in SharedPreferences. On first
load after upgrade, any plaintext SharedPreferences secrets are migrated once
and cleared.

Transactions open a client through **`EcrSessions.open`** so LAN / USB / Web
Service share one path for sale, inquiry, and receipt.

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
