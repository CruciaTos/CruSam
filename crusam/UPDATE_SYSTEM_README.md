# Crusam Self-Update System — Integration Guide

## Files Added / Changed

### New Flutter files
```
lib/core/update/version_constants.dart
lib/core/update/update_model.dart
lib/core/update/update_service.dart
lib/core/update/update_notifier.dart
lib/core/update/update_dialog.dart
lib/features/profile/widgets/update_card.dart
```

### Modified Flutter files
```
lib/main.dart
lib/main_clean.dart
lib/features/profile/presentation/profile_screen.dart
pubspec.yaml
```

### External updater project
```
updater/pubspec.yaml
updater/bin/main.dart
```

### Release metadata
```
latest.json
```

---

## Configure GitHub release metadata

`lib/core/update/version_constants.dart` is already pointed at:

```dart
const String kLatestJsonUrl =
    'https://raw.githubusercontent.com/CruciaTos/CruSam/main/latest.json';
```

Update `latest.json` in the repository root for each release.

---

## Build updater.exe

```bash
cd updater
dart pub get
dart compile exe bin/main.dart -o updater.exe
```

Copy `updater.exe` next to `crusam.exe` in the release output folder.

---

## Release flow

1. Bump version in `crusam/pubspec.yaml`.
2. Update `kAppVersion` in `lib/core/update/version_constants.dart`.
3. Build your Windows release ZIP.
4. Publish a GitHub release tagged like `v1.0.1`.
5. Upload the ZIP to that release.
6. Update root `latest.json` with the new version and ZIP URL.

---

## Data safety

The updater only writes inside the installed app directory.
It skips archive paths containing `AppData`, `Documents`, or `Roaming`, so
SQLite databases and shared preferences stored in user directories are not
touched during updates.