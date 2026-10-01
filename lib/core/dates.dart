import 'package:intl/intl.dart';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ertesi günün başlangıcı (aralık sonu olarak dışlayıcı kullanılır).
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// Pazartesi başlangıçlı hafta.
DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime parseDayKey(String key) => DateFormat('yyyy-MM-dd').parse(key);

/// "1 sa 25 dk", "40 dk", "0 dk"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m dk';
  if (m == 0) return '$h sa';
  return '$h sa $m dk';
}

/// 25:00 biçiminde (saat varsa 1:05:00).
String formatClock(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}${h > 0 ? '$h:' : ''}$m:$s';
}

final _time = DateFormat('HH:mm');
String formatTime(DateTime d) => _time.format(d);

/// "Bugün", "Yarın", "Dün", aksi halde "3 Eki Cum".
String formatRelativeDay(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final diff = startOfDay(d).difference(startOfDay(now)).inDays;
  return switch (diff) {
    0 => 'Bugün',
    1 => 'Yarın',
    -1 => 'Dün',
    _ when diff > 1 && diff < 7 => DateFormat('EEEE', 'tr').format(d),
    _ when d.year == now.year => DateFormat('d MMM EEE', 'tr').format(d),
    _ => DateFormat('d MMM y', 'tr').format(d),
  };
}

String formatDue(DateTime due, bool hasTime, {DateTime? now}) {
  final day = formatRelativeDay(due, now: now);
  return hasTime ? '$day ${formatTime(due)}' : day;
}

/// Haftanın günü bit maskesi (bit 0 = Pazartesi).
bool weekdayInMask(int mask, DateTime d) => mask & (1 << (d.weekday - 1)) != 0;

const weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
