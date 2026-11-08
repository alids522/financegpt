import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/domain.dart';

void main() {
  test('PRD budget example distinguishes remaining and projected variance', () {
    final f = Forecast.calculate(
      actual: 2800000,
      budget: 5000000,
      period: Period(DateTime(2026, 11), DateTime(2026, 12)),
      now: DateTime(2026, 11, 14),
    );
    expect(f.estimate, 6000000);
    expect(f.remaining, 2200000);
    expect(f.projectedVariance, -1000000);
  });
  test('month is a calendar month with an exclusive end', () {
    final p = Period.calendar('Month', DateTime(2026, 11, 8));
    expect(p.start.toUtc(), DateTime.utc(2026, 10, 31, 17));
    expect(p.end.toUtc(), DateTime.utc(2026, 11, 30, 17));
    expect(
      p.contains(DateTime(2026, 11, 30, 23, 59, 59).toIso8601String()),
      true,
    );
    expect(p.contains(DateTime(2026, 12).toIso8601String()), false);
  });
  test('week honors selected week start', () {
    expect(
      Period.calendar('Week', DateTime(2026, 11, 8)).start,
      financeDate(2026, 11, 2),
    );
    expect(
      Period.calendar('Week', DateTime(2026, 11, 8), weekStart: 7).start,
      financeDate(2026, 11, 8),
    );
  });
  test('money parsing never uses floating point', () {
    expect(parseMoney('12.450.000'), 12450000);
    expect(parseMoney('12,34', 'USD'), 1234);
    expect(() => parseMoney('0,50'), throwsFormatException);
    expect(() => parseMoney('-100'), throwsFormatException);
  });
  test('quoted CSV round trip preserves newlines, commas and UTF8', () {
    final rows = [
      ['date', 'description', 'amount'],
      ['2026-11-08', 'Makan, "siang"\ndan kopi', '35000'],
    ];
    expect(parseCsv(encodeCsv(rows)), rows);
  });
  test('CSV detects semicolon and rejects unclosed quote', () {
    expect(parseCsv('name;amount\r\nMakan;35000'), [
      ['name', 'amount'],
      ['Makan', '35000'],
    ]);
    expect(() => parseCsv('a,b\n"broken'), throwsFormatException);
  });
  test('CSV neutralizes spreadsheet formulas', () {
    expect(
      parseCsv(
        encodeCsv([
          ['=IMPORTXML("x")', '@SUM(A1)', '-35000'],
        ]),
      )[0],
      ["'=IMPORTXML(\"x\")", "'@SUM(A1)", '-35000'],
    );
  });
  test('scheduled method does not project actual twice', () {
    final f = Forecast.calculate(
      actual: 100,
      budget: 500,
      scheduled: 200,
      method: 'scheduled',
      period: Period(DateTime(2026, 11), DateTime(2026, 12)),
      now: DateTime(2026, 11, 14),
    );
    expect(f.estimate, 300);
  });
}
