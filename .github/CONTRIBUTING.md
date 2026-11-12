# Contributing to DawnChat

Thanks for your interest in contributing! DawnChat is a Flutter client for the DawnChat
platform, targeting Android, iOS, Windows, macOS, Linux, and Web.

## Getting started

### Prerequisites

- **Flutter** `3.47.9` stable (see `.github/workflows/_build.yml` for the pinned version)
- **Rust** stable toolchain — the app embeds a Rust core under `project/rust`
- Platform toolchains for your target (Android SDK/NDK, Xcode for Apple platforms,
  Visual Studio for Windows, clang/GTK for Linux)

### Setup

```sh
cd project
flutter pub get
```

## Before you open a PR

Run the same checks CI runs:

```sh
cd project
flutter analyze --no-fatal-infos
flutter test
```

PR builds are unsigned release builds — if it compiles in CI, it compiles for release.

## Branches & PRs

- **`bleeding`** is the mainline — all PRs target it.
- Every push to `bleeding` produces an edge prerelease; manual releases are cut
  from `release.yml` with a version input.
- Keep PRs focused; small PRs get reviewed faster.
- **Do not modify anything under `project/lib/src/ui/admin/`** — the admin
  panel is maintained internally and PRs touching it are rejected automatically
  by the `admin-guard` CI job. If your change needs admin UI work, open an
  issue describing the requirement.

## Code style

- Follow the existing patterns in the surrounding code — `provider` for state,
  `go_router` for navigation, `NetImage`/`netImageProvider` for remote images.
- No new dependencies without discussion — check `pubspec.yaml` first.
- Don't commit secrets, tokens, or personal data. Firebase/Keystore values come
  from CI secrets only.

## Reporting bugs & requesting features

Use the issue templates — they ask for the details we actually need.

## License

By contributing, you agree your contributions are licensed under the same
license as the project (see `LICENSE`).
