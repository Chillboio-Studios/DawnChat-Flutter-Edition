# project

A new Flutter project.

## Clipboard images

Paste an image into the message composer with Ctrl+V, Cmd+V, or Paste in the
selection menu. It appears in the attachment preview and uploads when the
message is sent, using the same permissions and size limits as selected files.
Text-only clipboard content still pastes normally. On web, browser paste events
provide image data without requesting clipboard-read permission; using Flutter's
selection-menu Paste may require browser clipboard permission.

## Dependency updates

Run `flutter pub upgrade --major-versions` from this directory and commit both
`pubspec.yaml` and `pubspec.lock`. Validate updates with `flutter analyze
--no-fatal-infos` and `flutter test`.

`launch_at_startup` 0.5.1 requires the win32 5.x ecosystem, so the latest mutually
compatible versions are currently file_picker 11.0.3 and package_info_plus 9.0.1.
Do not force win32 6.x with dependency overrides; replacing the startup package
requires preserving Windows, Linux, and macOS startup registration.

The desktop integration uses the compatibility libraries provided by
window_manager 0.6 and tray_manager 0.8 to preserve window and tray behavior.
Desktop code is conditionally exported so these libraries are not compiled
into the web app.
Their native build hooks require `pkg-config`, `libgtk-3-dev`, `libx11-dev`,
and `libxi-dev` when running tests or building on Debian/Ubuntu.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
