# AGENTS.md

Venera: a Flutter comic reader (desktop + mobile), a personal fork of `venera-app/venera`. Push to `origin` (`bgzo-sandbox/venera`) on branch `main`; upstream is `haukuen/venera` (rebased/merged with local changes).

## Toolchain

- Flutter is FVM-pinned: use `fvm flutter ...` (SDK 3.41.9 in `.fvmrc`; `.vscode` already points at it). CI reads the Flutter version from `pubspec.yaml` (`flutter-version-file`), not `.fvmrc`.
- Rust toolchain 1.85.1 (`rust-toolchain.toml`) feeds native deps (`rhttp`, `flutter_qjs`); local desktop builds need a working rust toolchain.
- Many dependencies are git-ref-pinned forks under `venera-app/*` (flutter_qjs, webdav_client, flutter_inappwebview, photo_view, flutter_saf, flutter_7zip, lodepng_flutter...). Don't bump those refs casually; `flutter pub get` needs GitHub access.

## Verification gate (enforced by `.github/workflows/analyze.yml`)

```
fvm dart format --set-exit-if-changed .
fvm flutter analyze --fatal-infos
fvm flutter test
```

Run all three (in that order) before pushing; CI runs them on every PR/push to main.

## Architecture

- Comic sources are **JavaScript** loaded at runtime through `flutter_qjs`: `lib/foundation/js_engine.dart` + `lib/foundation/comic_source/`. Source authoring API: `assets/init.js`, `doc/comic_source.md`, `doc/js_api.md`.
- UI strings use custom i18n, not gen-l10n: `'Text'.tl` (see `lib/utils/translations.dart`) with keys in `assets/translation.json` under `en_US` / `zh_CN` / `zh_TW`. New UI strings must be added there.
- Comments and commit messages are frequently in Chinese.
- `lib/main.dart` routes `--headless` to `lib/headless.dart` CLI mode (`webdav up|down`, `updatescript all`, `updatesubscribe`); protocol documented in `doc/headless_doc.md`. All CLI output is JSON prefixed `[CLI PRINT]`.
- App data lives in SQLite via `lib/foundation/sqlite_connection.dart`; runtime settings via `appdata` (`lib/foundation/appdata.dart`).
- Super-resolution subsystem: `lib/super_resolution/` (pure-Dart Anime4K upscaler, cache store, task scheduler), initialized from `lib/init.dart`.
- Local-comic import expects directories with `cover.[ext]` + images (chapters as subdirs) — see `doc/import_comic.md`. CBZ/EPUB export in `lib/utils/cbz.dart` / `lib/utils/epub.dart`.

## Release

- Bump `version:` in `pubspec.yaml`, then tag `v*`. `.github/workflows/main.yml` builds all platforms (macOS DMG, iOS unsigned IPA, APKs, Windows via `windows/build.py`, Linux .deb via `debian/build.py` + `flutter_to_arch`) and publishes a GitHub release.
