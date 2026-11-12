# DawnChat

A user-first chat application — Flutter client with a Rust core, backed by the
DawnChat API (private repository).

![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-blue)

## Features

- **Messaging** — channels, threads, replies, edits, deletes, pins, reactions,
  embeds, markdown (including inline images), file uploads, GIFs, custom emoji
- **Servers** — categories, channel reordering, roles with hierarchical
  permissions, member management, discovery, invites
- **Voice & video** — LiveKit-powered calls, screen sharing, speaking indicators
- **Profiles** — avatars, banners, statuses, badges, relationships
- **Notifications** — push (FCM/APNs), in-app toasts, per-channel settings
- **Admin panel** — user management, reports & tickets, moderation actions,
  audit logs, legal requests, policy publishing, changelogs, bots, strikes
- **Bots & webhooks** — full bot API surface, webhook management, slash-style
  interactions
- **Privacy** — Shield content scanning, report system, account deletion with
  legal retention snapshots

## Platforms

| Platform | Status |
|---|---|
| Android | Release builds via CI (Play Store internal track on release) |
| iOS | Release builds via CI (App Store Connect on release) |
| Windows | Unsigned/signed desktop builds |
| macOS | Desktop builds, App Store Connect on release |
| Linux | tarball + AppImage |
| Web | Docker image (`ghcr.io/chillboio-studios/dawnchat-flutter-edition`) |

## Tech stack

- **Client** — Flutter/Dart (`project/`), `provider` state management,
  `go_router` navigation
- **Core** — Rust library embedded via FFI (`project/rust`)
- **Backend** — separate Rust API (Rocket + MongoDB), see the backend repo
- **Realtime** — gateway websocket events, LiveKit for voice/video

## Development

```sh
cd project
flutter pub get          # Flutter 3.47.9 stable
flutter analyze --no-fatal-infos
flutter test
```

A Rust stable toolchain is required — the app compiles `project/rust` as a
native library. See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for the full
guide.

## CI pipelines

| Workflow | Trigger | Result |
|---|---|---|
| `edge.yml` | push to `bleeding` | all platform builds + `bleeding-edge` docker + prerelease |
| `pr.yml` | PR into `bleeding` | unsigned release builds + `pr-<id>` docker |
| `release.yml` | manual dispatch + version | stores, GHCR, stable GitHub release |

PRs may not modify `project/lib/src/ui/admin/` — enforced by CI.

## Links

- **Issues / feedback** — [GitHub Issues](https://github.com/Chillboio-Studios/DawnChat-Flutter-Edition/issues)
- **Contributing** — [CONTRIBUTING.md](.github/CONTRIBUTING.md)
- **Security** — [SECURITY.md](.github/SECURITY.md)

## Compatibility note

This client is built against the DawnChat API, which includes endpoints and
behaviors that are **not compatible with StoatChat/Revolt** and includes
breaking API changes. Pointing this client at Stoat or another Stoat-based
instance — including self-hosted ones — **may not work**.

## License

See [LICENSE](LICENSE).
