import '../../state/settings_store.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// ULID timestamp decoding (Crockford base32, first 10 chars).
DateTime ulidTime(String id) {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  var ms = 0;
  for (final ch in id.substring(0, 10).split('')) {
    ms = ms * 32 + alphabet.indexOf(ch.toUpperCase());
  }
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// dayjs `LT` using the user's time format ("HH:mm" or "h:mm A").
String formatTime(SettingsStore s, DateTime t) {
  t = t.toLocal();
  if (s.timeFormat == 'HH:mm') return '${_p2(t.hour)}:${_p2(t.minute)}';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${_p2(t.minute)} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

/// dayjs `L` using the user's date format.
String formatDate(SettingsStore s, DateTime t) {
  t = t.toLocal();
  return switch (s.dateFormat) {
    'MM/DD/YYYY' => '${_p2(t.month)}/${_p2(t.day)}/${t.year}',
    'YYYY-MM-DD' => '${t.year}-${_p2(t.month)}-${_p2(t.day)}',
    _ => '${_p2(t.day)}/${_p2(t.month)}/${t.year}',
  };
}

/// Profile "Joined" dates: `L` with the month spelled out as `MMM`.
String formatJoined(SettingsStore s, DateTime t) {
  t = t.toLocal();
  const short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final m = short[t.month - 1];
  return switch (s.dateFormat) {
    'MM/DD/YYYY' => '$m ${_p2(t.day)} ${t.year}',
    'YYYY-MM-DD' => '${t.year} $m ${_p2(t.day)}',
    _ => '${_p2(t.day)} $m ${t.year}',
  };
}

/// dayjs `LL`.
String formatLongDate(DateTime t) {
  t = t.toLocal();
  return '${_months[t.month - 1]} ${t.day}, ${t.year}';
}

String formatDateTime(SettingsStore s, DateTime t) => '${formatDate(s, t)} ${formatTime(s, t)}';

String formatFull(SettingsStore s, DateTime t) {
  t = t.toLocal();
  return '${_weekdays[t.weekday - 1]}, ${formatLongDate(t)} ${formatTime(s, t)}';
}

/// dayjs `calendar()` with the client's strings.
String formatCalendar(SettingsStore s, DateTime t, [DateTime? now]) {
  t = t.toLocal();
  now = (now ?? DateTime.now()).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final lt = formatTime(s, t);
  if (diff == 0) return 'Today at $lt';
  if (diff == -1) return 'Yesterday at $lt';
  if (diff == 1) return 'Tomorrow at $lt';
  if (diff < -1 && diff > -7) return 'Last ${_weekdays[t.weekday - 1]} at $lt';
  if (diff > 1 && diff < 7) return '${_weekdays[t.weekday - 1]} at $lt';
  return formatDate(s, t);
}

/// dayjs `relativeTime` thresholds.
String formatRelative(DateTime t, {DateTime? reference, bool hideSuffix = false}) {
  final ref = reference ?? DateTime.now();
  final ms = t.difference(ref).inMilliseconds;
  final future = ms > 0;
  final secs = ms.abs() / 1000;
  final mins = secs / 60, hours = mins / 60, days = hours / 24;
  String text;
  if (secs < 45) {
    text = 'a few seconds';
  } else if (secs < 90) {
    text = 'a minute';
  } else if (mins < 45) {
    text = '${mins.round()} minutes';
  } else if (mins < 90) {
    text = 'an hour';
  } else if (hours < 22) {
    text = '${hours.round()} hours';
  } else if (hours < 36) {
    text = 'a day';
  } else if (days < 26) {
    text = '${days.round()} days';
  } else if (days < 46) {
    text = 'a month';
  } else if (days < 320) {
    text = '${(days / 30.4).round()} months';
  } else if (days < 548) {
    text = 'a year';
  } else {
    text = '${(days / 365).round()} years';
  }
  if (hideSuffix) return text;
  return future ? 'in $text' : '$text ago';
}
