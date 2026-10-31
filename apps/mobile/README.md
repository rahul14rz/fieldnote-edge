# Mobile app

This is the Flutter app for Android and macOS. Right now it shows one placeholder screen. It has no recording, transcription, inference or networking code. State management uses Flutter's built-in tools ([ADR 0004](../../docs/decisions/0004-mobile-state-management.md)).

## Checks

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

## Run

```bash
cd apps/mobile
flutter run -d macos
```

To run on a connected Android phone, use `flutter run` and select the device. `flutter run -d macos` needs a Mac with Xcode. Neither run command has been tried in this repository's CI or development environment, which is Linux and has no device.
