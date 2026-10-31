# Mobile app

This is the Flutter app for Android and macOS. It records a meeting and transcribes it on the device with Whisper base. It then extracts a summary with Gemma 4 E2B and validates the summary against the `MeetingSummary` schema. If the phone's summary is invalid and the paired Mac is reachable, the app sends the job to the Mac. [ADR 0012](../../docs/decisions/0012-mobile-pipeline.md) describes the pipeline. [ADR 0007](../../docs/decisions/0007-job-store-and-routing-rules.md) describes the job store and routing.

The app has not been run on a device. Its tests use fake engines.

## Screens

- **Home.** The list of recordings, with transcript and summary status (where each ran, retries, failures and reasons). The Record button asks for the meeting language first.
- **Recording.** Shows the transcript and the summary: participants, topics, decisions, and action items with owner and due date.
- **Settings.** Downloads the models, finds the Mac over mDNS or takes its address by hand, and pairs with the code from `fieldnote-gateway pair`. It can unpair, and it has a switch for sending jobs to the Mac.

## Checks

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

## Build

```bash
cd apps/mobile
flutter build apk --release --target-platform android-arm64
```

This build succeeded in the Linux development container. The APK has `minSdkVersion` 30, LiteRT-LM for `arm64-v8a`, and the permissions `RECORD_AUDIO`, `INTERNET`, `ACCESS_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE`. `FOREGROUND_SERVICE`, `WAKE_LOCK` and `RECEIVE_BOOT_COMPLETED` come from `background_downloader`, which `flutter_edge_ai` uses for model downloads.

`flutter run -d macos` needs a Mac with Xcode and has not been tried. `flutter_secure_storage` on macOS may need a signing team for Keychain access.

## Use it with the Mac

1. On the Mac, start a model server and the gateway on the LAN. See [`services/gateway/README.md`](../../services/gateway/README.md#serve-the-phone).
2. On the Mac, run `node services/gateway/dist/src/cli.js pair`.
3. On the phone, open Settings, tap **Find my Mac** (or type the address and port), enter the code, and tap **Pair**.
