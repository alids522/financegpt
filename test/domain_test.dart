import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/domain.dart';

void main() {
  test(
    'statement month includes last day for 28, 29, 30 and 31 day months',
    () {
      expect(StatementRange.month(2026, 1).end, '2026-01-31');
      expect(StatementRange.month(2026, 2).end, '2026-02-28');
      expect(StatementRange.month(2024, 2).end, '2024-02-29');
      expect(StatementRange.month(2026, 4).end, '2026-04-30');
      expect(StatementRange.month(2026, 12).start, '2026-12-01');
      expect(StatementRange.month(2026, 12).end, '2026-12-31');
    },
  );
  test('statement custom dates are inclusive and reject reversed dates', () {
    final range = StatementRange(
      financeDate(2026, 11, 7, 23),
      financeDate(2026, 11, 9),
    );
    expect(range.start, '2026-11-07');
    expect(range.end, '2026-11-09');
    expect(
      () => StatementRange(financeDate(2026, 11, 9), financeDate(2026, 11, 1)),
      throwsFormatException,
    );
  });
  test(
    'hybrid uses historical variable spend without counting scheduled actual again',
    () {
      final f = Forecast.calculate(
        actual: 50000,
        budget: 1000000,
        period: Period(financeDate(2026, 11), financeDate(2026, 12)),
        now: financeDate(2026, 11, 14),
        scheduled: 200000,
        variableActual: 50000,
        historicalVariable: 100000,
        historicalDays: 20,
        method: 'hybrid',
      );
      expect(f.estimate, 330000);
    },
  );
  test('monthly dates retain the original day after a short month', () {
    final dates = scheduledOccurrences(
      {
        'active': true,
        'next_at': '2026-01-31T09:00:00+07:00',
        'cadence': 'monthly',
        'anchor_day': 31,
      },
      Period(financeDate(2026, 2), financeDate(2026, 4)),
      financeDate(2026, 1, 30),
    );
    expect(dates.map((d) => d.day).toList(), [28, 31]);
  });
  test(
    'daily schedule expands all future occurrences in a selected period',
    () {
      final dates = scheduledOccurrences(
        {
          'active': true,
          'next_at': '2026-11-09T09:00:00+07:00',
          'cadence': 'daily',
        },
        Period(financeDate(2026, 11), financeDate(2026, 12)),
        financeDate(2026, 11, 8),
      );
      expect(dates.length, 22);
    },
  );
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
    expect(moneyInput(1234, 'USD'), '12,34');
    expect(parseMoney(moneyInput(1234, 'USD'), 'USD'), 1234);
    expect(parseMoney('12.450.000'), 12450000);
    expect(parseMoney('12,34', 'USD'), 1234);
    expect(() => parseMoney('0,50'), throwsFormatException);
    expect(() => parseMoney('-100'), throwsFormatException);
  });
  test(
    'multi-selection includes account destinations and category descendants',
    () {
      final filter = TransactionFilter()
        ..accounts.addAll(['cash', 'bank'])
        ..categories.add('parent');
      final transaction = <String, dynamic>{
        'effective_at': '2026-11-08T12:00:00+07:00',
        'account_id': 'cash',
        'category_id': 'child',
        'amount': 100,
      };
      expect(
        filter.matches(
          transaction,
          Period(financeDate(2026, 11), financeDate(2026, 12)),
          categoryIds: {'parent', 'child'},
        ),
        true,
      );
      filter.accounts
        ..clear()
        ..add('other');
      expect(
        filter.matches(
          transaction,
          Period(financeDate(2026, 11), financeDate(2026, 12)),
          categoryIds: {'parent', 'child'},
        ),
        false,
      );
    },
  );
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
  test(
    'native CSV restores escaped formulas and literal apostrophes without data loss',
    () {
      final values = [
        '=SUM(A1)',
        "'=literal",
        "'note",
        '  +command',
        '-formula',
        '-35000',
        ' meal, with whitespace ',
      ];
      expect(
        parseCsv(encodeCsv([values])).single.map(decodeCsvText).toList(),
        values,
      );
    },
  );
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
