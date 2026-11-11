/// Launch-at-login stubs for platforms without `dart:io` (web).
Future<bool> autostartIsEnabled() async => false;

Future<void> autostartSetEnabled(bool enabled) async {}
