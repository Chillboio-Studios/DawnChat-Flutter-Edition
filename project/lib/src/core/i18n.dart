import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'languages.dart';

/// Runtime translation catalog (msgid is the English source string, as in the web client's lingui catalogs).
class I18n {
  static Map<String, String> _catalog = const {};
  static String code = 'en';

  /// Bumped whenever the active catalog changes so the app can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String _catalogName(String lang) => lang == 'esperanto' ? 'eo' : lang;

  static Future<void> load(String lang) async {
    final name = _catalogName(lang);
    Map<String, String> next = const {};
    if (name != 'en') {
      try {
        final raw = await rootBundle.loadString('assets/i18n/$name.json');
        next = (jsonDecode(raw) as Map).cast<String, String>();
      } catch (_) {
        // Missing catalog falls back to English.
      }
    }
    _catalog = next;
    code = lang;
    revision.value++;
  }

  static String? lookup(String msgid) => _catalog[msgid];
}

/// Translates [msgid]; `{0}`, `{name}` and ICU `plural` blocks are filled from [args].
String tr(String msgid, [Map<Object, Object?>? args]) {
  final s = I18n.lookup(msgid) ?? msgid;
  if (args == null && !s.contains('{')) return s;
  return _format(s, {for (final e in (args ?? const {}).entries) '${e.key}': e.value});
}

String _format(String s, Map<String, Object?> a) {
  final b = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c != '{') {
      b.write(c);
      i++;
      continue;
    }
    final end = _closing(s, i);
    if (end < 0) {
      b.write(c);
      i++;
      continue;
    }
    b.write(_arg(s.substring(i + 1, end), a));
    i = end + 1;
  }
  return b.toString();
}

int _closing(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return i;
  }
  return -1;
}

String _arg(String inner, Map<String, Object?> a) {
  final comma = inner.indexOf(',');
  if (comma < 0) {
    final v = a[inner.trim()];
    return v == null ? '{$inner}' : '$v';
  }
  final name = inner.substring(0, comma).trim();
  final rest = inner.substring(comma + 1).trimLeft();
  if (!rest.startsWith('plural,')) return '{$inner}';
  final n = a[name];
  final count = n is num ? n : num.tryParse('$n') ?? 0;
  final options = <String, String>{};
  final body = rest.substring('plural,'.length);
  var i = 0;
  while (i < body.length) {
    final open = body.indexOf('{', i);
    if (open < 0) break;
    final key = body.substring(i, open).trim();
    final close = _closing(body, open);
    if (close < 0) break;
    options[key] = body.substring(open + 1, close);
    i = close + 1;
  }
  final text =
      options['=$count'] ??
      (count == 0 ? options['zero'] : null) ??
      (count == 1 ? options['one'] : null) ??
      options['other'] ??
      '';
  return _format(text.replaceAll('#', '$count'), a);
}

/// Mirrors the web client's browser-language detection for first launch.
String preferredLanguageCode() {
  final known = {for (final l in appLanguages) l.code};
  final locales = PlatformDispatcher.instance.locales;
  for (final l in locales) {
    final full = [
      l.languageCode,
      if (l.scriptCode != null) l.scriptCode,
      if (l.countryCode != null && l.scriptCode == null) l.countryCode,
    ].join('-');
    if (known.contains(full)) return full;
  }
  for (final l in locales) {
    if (known.contains(l.languageCode)) return l.languageCode;
  }
  return 'en';
}
