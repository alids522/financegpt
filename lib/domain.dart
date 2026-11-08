import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

typedef FinanceRow = Map<String, dynamic>;
final bool _zonesInitialized = (() {
  tzdata.initializeTimeZones();
  return true;
})();
String reportingTimeZone = 'Asia/Jakarta';
tz.Location get reportingLocation {
  if (!_zonesInitialized) throw StateError('Timezone data unavailable');
  return tz.getLocation(reportingTimeZone);
}

DateTime localTime(dynamic value) {
  final text = '$value';
  final d = DateTime.parse(text);
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)) {
    return tz.TZDateTime(
      reportingLocation,
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      d.microsecond,
    );
  }
  return tz.TZDateTime.from(d, reportingLocation);
}

DateTime financeDate(
  int year, [
  int month = 1,
  int day = 1,
  int hour = 0,
  int minute = 0,
]) => tz.TZDateTime(reportingLocation, year, month, day, hour, minute);
DateTime financeNow() => tz.TZDateTime.now(reportingLocation);

int integer(dynamic value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;
String money(dynamic value, [String currency = 'IDR']) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: currency == 'IDR' ? 'Rp ' : '$currency ',
  decimalDigits: currency == 'IDR' ? 0 : 2,
).format(integer(value) / (currency == 'IDR' ? 1 : 100));
String dateLabel(dynamic value) =>
    DateFormat('dd MMM yyyy', 'id_ID').format(localTime(value));
int parseMoney(String value, [String currency = 'IDR']) {
  final normalized = value.trim().replaceAll('.', '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
    throw const FormatException('Masukkan nominal yang valid.');
  }
  final parts = normalized.split('.');
  if (currency == 'IDR') {
    if (parts.length > 1 && int.parse(parts[1]) != 0) {
      throw const FormatException('IDR harus bilangan bulat.');
    }
    return int.parse(parts[0]);
  }
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

class Period {
  final DateTime start;
  final DateTime end;
  Period(DateTime start, DateTime end)
    : start = financeDate(
        start.year,
        start.month,
        start.day,
        start.hour,
        start.minute,
      ),
      end = financeDate(end.year, end.month, end.day, end.hour, end.minute);
  factory Period.calendar(String kind, DateTime anchor, {int weekStart = 1}) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    switch (kind) {
      case 'Day':
        return Period(d, d.add(const Duration(days: 1)));
      case 'Week':
        final s = d.subtract(Duration(days: (d.weekday - weekStart + 7) % 7));
        return Period(s, s.add(const Duration(days: 7)));
      case 'Year':
        return Period(DateTime(d.year), DateTime(d.year + 1));
      default:
        return Period(DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
    }
  }
  bool contains(dynamic value) {
    final d = localTime(value);
    return !d.isBefore(start) && d.isBefore(end);
  }

  String get label =>
      '${DateFormat('d MMM y', 'id_ID').format(start)} – ${DateFormat('d MMM y', 'id_ID').format(end.subtract(const Duration(days: 1)))}';
  int get days => end.difference(start).inDays;
}

class Forecast {
  final int actual, scheduled, estimate, budget, elapsed, days;
  final String method;
  const Forecast({
    required this.actual,
    required this.scheduled,
    required this.estimate,
    required this.budget,
    required this.elapsed,
    required this.days,
    required this.method,
  });
  int get remaining => budget - actual;
  int get projectedVariance => budget - estimate;
  static Forecast calculate({
    required int actual,
    required int budget,
    required Period period,
    required DateTime now,
    int scheduled = 0,
    int variableActual = 0,
    String method = 'run_rate',
  }) {
    final elapsed =
        (DateTime.utc(now.year, now.month, now.day)
                    .difference(
                      DateTime.utc(
                        period.start.year,
                        period.start.month,
                        period.start.day,
                      ),
                    )
                    .inDays +
                1)
            .clamp(1, period.days);
    final total = switch (method) {
      'scheduled' => actual + scheduled,
      'hybrid' =>
        actual +
            scheduled +
            (variableActual * (period.days - elapsed) / elapsed).round(),
      _ => (actual * period.days / elapsed).round(),
    };
    return Forecast(
      actual: actual,
      scheduled: scheduled,
      estimate: total,
      budget: budget,
      elapsed: elapsed,
      days: period.days,
      method: method,
    );
  }
}

class TransactionFilter {
  String search = '',
      type = '',
      account = '',
      category = '',
      status = '',
      actor = '',
      tag = '',
      merchant = '';
  int? min, max;
  bool attachmentOnly = false, descending = true;
  String sort = 'effective_at';
  bool matches(FinanceRow t, Period period) =>
      period.contains(t['effective_at']) &&
      (search.isEmpty ||
          '${t['description']} ${t['merchant']} ${t['tags']}'
              .toLowerCase()
              .contains(search.toLowerCase())) &&
      (type.isEmpty || t['type'] == type) &&
      (account.isEmpty ||
          t['account_id'] == account ||
          t['destination_account_id'] == account) &&
      (category.isEmpty || t['category_id'] == category) &&
      (status.isEmpty || t['status'] == status) &&
      (actor.isEmpty || t['source'] == actor) &&
      (tag.isEmpty || (t['tags'] as List? ?? []).contains(tag)) &&
      (merchant.isEmpty ||
          '${t['merchant']}'.toLowerCase().contains(merchant.toLowerCase())) &&
      (min == null || integer(t['amount']) >= min!) &&
      (max == null || integer(t['amount']) <= max!) &&
      (!attachmentOnly || t['attachment_path'] != null);
}

// RFC 4180, embedded newlines, BOM, and delimiter detection. Amounts remain strings.
List<List<String>> parseCsv(String source, {String? delimiter}) {
  source = source.replaceFirst('\ufeff', '');
  final first = source.split(RegExp(r'\r?\n')).first;
  final sep =
      delimiter ??
      (first.split(';').length > first.split(',').length ? ';' : ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '"') {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == sep && !quoted) {
      row.add(cell.toString());
      cell.clear();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.isNotEmpty)) rows.add(row);
      row = [];
    } else {
      cell.write(c);
    }
  }
  if (quoted) {
    throw const FormatException('CSV memiliki tanda kutip yang belum ditutup.');
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

String encodeCsv(List<List<dynamic>> rows) =>
    '\ufeff${rows.map((r) => r.map((v) {
      var s = v?.toString() ?? '';
      if (RegExp(r'^[\s]*[=+@]').hasMatch(s) || (s.startsWith('-') && int.tryParse(s) == null)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }).join(',')).join('\r\n')}';
