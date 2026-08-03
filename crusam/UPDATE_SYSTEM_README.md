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

---

## Update source: GitHub Releases API (no metadata file)

Update information is no longer sourced from a manually-maintained
`latest.json` file. `UpdateService` queries the GitHub Releases REST API
directly:

```
GET https://api.github.com/repos/CruciaTos/CruSam/releases/latest
```

The owner/repo pair is declared once in
`lib/core/updater/version_constants.dart` (`kGitHubRepoOwner`,
`kGitHubRepoName`) and the endpoint is built from those constants — nothing
else in the codebase should hardcode the repo path.

There is nothing to "update" between releases beyond publishing the GitHub
release itself with a correctly-named installer asset
(`CruSam-Setup-<version>.exe`) — see `RELEASE.md` for the full flow and
naming convention.

`latest.json` at the repo root is no longer read by the app. See
`RELEASE.md` for whether/when it's safe to delete it.

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

`pubspec.yaml`'s `version:` field is the single source of truth for the app
version — there is no separate version constant to keep in sync. See
`RELEASE.md` for the full, required build procedure (including why
`flutter clean` is mandatory on Windows and how to verify the built
`crusam.exe`).

1. Bump `version:` in `crusam/pubspec.yaml`.
2. Follow the build + verification steps in `RELEASE.md`.
3. Publish a GitHub release tagged like `v1.0.1`.
4. Upload the installer as `CruSam-Setup-1.0.1.exe` to that release.
   The in-app updater discovers it automatically via the GitHub Releases
   API — no metadata file to update.

---

## Data safety

The updater only writes inside the installed app directory.
It skips archive paths containing `AppData`, `Documents`, or `Roaming`, so
SQLite databases and shared preferences stored in user directories are not
touched during updates.