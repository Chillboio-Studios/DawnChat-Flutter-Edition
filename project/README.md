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

Prefer targeted dependency updates over blanket major-version upgrades, and
commit both `pubspec.yaml` and `pubspec.lock`. Validate updates with
`flutter analyze --no-fatal-infos`, `flutter test`, and affected platform builds.

`launch_at_startup` 0.5.1 requires the win32 5.x ecosystem, so the latest mutually
compatible versions are currently file_picker 11.0.3 and package_info_plus 9.0.1.
Do not force win32 6.x with dependency overrides; replacing the startup package
requires preserving Windows, Linux, and macOS startup registration.

The desktop integration keeps window_manager on 0.5.x following a Linux
custom-frame regression reported after upgrading to 0.6 (clicking the bottom
message bar causes the window to lose focus). tray_manager stays on the
previous 0.5.x backend too. file_picker 11.0.3 is retained because it aligns
Android Java and Kotlin JVM targets; pasteboard and mime support clipboard images.
With AGP 9, file_picker assumes built-in Kotlin is enabled. While the app keeps
`android.builtInKotlin=false` for older plugins, the root Android Gradle script
explicitly applies the Kotlin plugin to file_picker and targets JVM 17. Remove
that compatibility block when migrating the whole Android build to built-in Kotlin.
Desktop code is conditionally exported so these libraries are not compiled
into the web app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
