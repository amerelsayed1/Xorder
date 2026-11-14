import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/pos_settings.dart';
import 'package:shared_module/domain/models/refund.dart';

/// What the business has configured, and what happens when it has not.
///
/// The resolution rule is the load-bearing part: business, then branch, then
/// terminal, most specific winning. Getting it backwards would let a
/// business-wide default silently override the answer somebody set for the
/// one till that needed it.
void main() {
  PosSettingRow row(
    SettingScope scope,
    String key,
    String value, {
    String scopeId = '',
  }) => PosSettingRow(scope: scope, scopeId: scopeId, key: key, value: value);

  PosSettings resolve(
    List<PosSettingRow> rows, {
    String branchId = '7',
    String terminalId = 'term-1',
  }) => PosSettings.resolve(
    rows,
    branchId: branchId,
    terminalId: terminalId,
  );

  group('resolution', () {
    test('a business value applies when nothing narrower exists', () {
      final settings = resolve([
        row(SettingScope.business, SettingKey.dayStartTime, '06:00'),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '06:00');
    });

    test('a branch value beats the business', () {
      final settings = resolve([
        row(SettingScope.business, SettingKey.dayStartTime, '06:00'),
        row(SettingScope.branch, SettingKey.dayStartTime, '04:00', scopeId: '7'),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '04:00');
    });

    test('a terminal value beats them both', () {
      final settings = resolve([
        row(SettingScope.business, SettingKey.dayStartTime, '06:00'),
        row(SettingScope.branch, SettingKey.dayStartTime, '04:00', scopeId: '7'),
        row(
          SettingScope.terminal,
          SettingKey.dayStartTime,
          '05:00',
          scopeId: 'term-1',
        ),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '05:00');
    });

    test('order of arrival does not decide the winner', () {
      // The rows come back in whatever order the query returns them. If the
      // last one won, the answer would change between reads.
      final settings = resolve([
        row(
          SettingScope.terminal,
          SettingKey.dayStartTime,
          '05:00',
          scopeId: 'term-1',
        ),
        row(SettingScope.business, SettingKey.dayStartTime, '06:00'),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '05:00');
    });

    test('another branch\'s value is ignored', () {
      final settings = resolve([
        row(SettingScope.business, SettingKey.dayStartTime, '06:00'),
        row(SettingScope.branch, SettingKey.dayStartTime, '02:00', scopeId: '9'),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '06:00');
    });

    test('another terminal\'s value is ignored', () {
      final settings = resolve([
        row(SettingScope.branch, SettingKey.dayStartTime, '04:00', scopeId: '7'),
        row(
          SettingScope.terminal,
          SettingKey.dayStartTime,
          '01:00',
          scopeId: 'other',
        ),
      ]);
      expect(settings.text(SettingKey.dayStartTime), '04:00');
    });

    test('every scope round-trips through its wire value', () {
      for (final scope in SettingScope.values) {
        expect(SettingScope.fromWire(scope.wire), scope);
      }
      // These strings are migration 14's CHECK constraint.
      expect(SettingScope.values.map((s) => s.wire).toSet(), {
        'business',
        'branch',
        'terminal',
      });
    });
  });

  group('reading values', () {
    test('a blank value reads as unset', () {
      // A row somebody emptied means "no answer", not "the empty answer".
      final settings = resolve([
        row(SettingScope.business, SettingKey.dayStartTime, '   '),
      ]);
      expect(settings.text(SettingKey.dayStartTime), isNull);
    });

    test('booleans accept what a person would type', () {
      for (final yes in ['true', 'TRUE', '1', 'yes']) {
        final settings = resolve([
          row(SettingScope.business, SettingKey.cashBlindClose, yes),
        ]);
        expect(
          settings.boolean(SettingKey.cashBlindClose, orElse: false),
          isTrue,
          reason: yes,
        );
      }
      for (final no in ['false', '0', 'no']) {
        final settings = resolve([
          row(SettingScope.business, SettingKey.cashBlindClose, no),
        ]);
        expect(
          settings.boolean(SettingKey.cashBlindClose, orElse: true),
          isFalse,
          reason: no,
        );
      }
    });

    test('an unreadable boolean falls back rather than guessing', () {
      // A misconfigured blind-close flag that silently read as true would hide
      // a figure nobody meant to hide.
      final settings = resolve([
        row(SettingScope.business, SettingKey.cashBlindClose, 'maybe'),
      ]);
      expect(settings.boolean(SettingKey.cashBlindClose, orElse: false), isFalse);
      expect(settings.boolean(SettingKey.cashBlindClose, orElse: true), isTrue);
    });

    test('money is minor units, and nonsense is no ceiling', () {
      expect(
        resolve([
          row(SettingScope.business, SettingKey.refundMaxValue, '15000'),
        ]).money(SettingKey.refundMaxValue)?.minor,
        15000,
      );
      // A ceiling nobody can read is safer as no ceiling than as a number
      // somebody guessed.
      for (final bad in ['abc', '-100', '15.00']) {
        expect(
          resolve([
            row(SettingScope.business, SettingKey.refundMaxValue, bad),
          ]).money(SettingKey.refundMaxValue),
          isNull,
          reason: bad,
        );
      }
    });

    test('a time is minutes past midnight, and invalid times are null', () {
      expect(
        resolve([
          row(SettingScope.business, SettingKey.dayStartTime, '06:30'),
        ]).minutesPastMidnight(SettingKey.dayStartTime),
        390,
      );
      for (final bad in ['25:00', '06:70', '6', 'morning']) {
        expect(
          resolve([
            row(SettingScope.business, SettingKey.dayStartTime, bad),
          ]).minutesPastMidnight(SettingKey.dayStartTime),
          isNull,
          reason: bad,
        );
      }
    });
  });

  group('DayPolicy', () {
    test('defaults to six in the morning, per the SRS', () {
      expect(DayPolicy.defaults.startMinutes, 6 * 60);
      expect(DayPolicy.defaults.label, '06:00');
    });

    test('an hour before the roll-over still belongs to yesterday', () {
      // The whole reason the trading day is not the calendar day: a business
      // closing at 2 a.m. takes money on Saturday that belongs to Friday.
      const policy = DayPolicy(startMinutes: 6 * 60);
      expect(
        policy.dateFor(DateTime(2026, 9, 12, 2, 30)),
        DateTime(2026, 9, 11),
      );
    });

    test('an hour after it belongs to today', () {
      const policy = DayPolicy(startMinutes: 6 * 60);
      expect(
        policy.dateFor(DateTime(2026, 9, 12, 7, 0)),
        DateTime(2026, 9, 12),
      );
    });

    test('exactly at the roll-over starts the new day', () {
      const policy = DayPolicy(startMinutes: 6 * 60);
      expect(
        policy.dateFor(DateTime(2026, 9, 12, 6, 0)),
        DateTime(2026, 9, 12),
      );
    });

    test('a month boundary rolls back correctly', () {
      const policy = DayPolicy(startMinutes: 6 * 60);
      expect(
        policy.dateFor(DateTime(2026, 10, 1, 1, 0)),
        DateTime(2026, 9, 30),
      );
    });

    test('reads the configured start time', () {
      final policy = DayPolicy.from(
        resolve([
          row(SettingScope.business, SettingKey.dayStartTime, '04:00'),
        ]),
      );
      expect(policy.startMinutes, 240);
      // 03:00 is now before the roll-over, so it is still yesterday.
      expect(
        policy.dateFor(DateTime(2026, 9, 12, 3, 0)),
        DateTime(2026, 9, 11),
      );
    });
  });

  group('CashPolicy', () {
    test('blind close is off until somebody asks for it', () {
      // The safe default is the one that surprises nobody.
      expect(CashPolicy.defaults.blindClose, isFalse);
      // And an unexplained drawer opening is the one thing a till can notice.
      expect(CashPolicy.defaults.drawerOpenNeedsReason, isTrue);
    });

    test('reads what was configured', () {
      final policy = CashPolicy.from(
        resolve([
          row(SettingScope.business, SettingKey.cashBlindClose, 'true'),
          row(SettingScope.business, SettingKey.cashPayOutMax, '50000'),
        ]),
      );
      expect(policy.blindClose, isTrue);
      expect(policy.payOutCeiling?.minor, 50000);
    });

    test('the pay-out ceiling is inclusive', () {
      const policy = CashPolicy(payOutCeiling: Money(50000));
      expect(policy.permitsPayOut(const Money(50000)), isTrue);
      expect(policy.permitsPayOut(const Money(50001)), isFalse);
    });

    test('no ceiling permits anything', () {
      expect(
        CashPolicy.defaults.permitsPayOut(const Money(999999)),
        isTrue,
      );
    });
  });

  group('RefundPolicy from settings', () {
    test('empty settings give the documented defaults', () {
      final policy = RefundPolicy.from(PosSettings.empty);
      expect(policy.enabled, isTrue);
      expect(policy.window, RefundWindow.days7);
      expect(policy.reasonRequired, isTrue);
      expect(policy.maxValue, isNull);
    });

    test('each key falls back on its own', () {
      // Partial configuration is the normal case — somebody sets a ceiling and
      // nothing else — so one missing key must not revert the whole object.
      final policy = RefundPolicy.from(
        resolve([
          row(SettingScope.business, SettingKey.refundMaxValue, '25000'),
        ]),
      );
      expect(policy.maxValue?.minor, 25000);
      expect(policy.window, RefundWindow.days7);
      expect(policy.enabled, isTrue);
    });

    test('an unreadable window falls back to seven days', () {
      final policy = RefundPolicy.from(
        resolve([
          row(SettingScope.business, SettingKey.refundWindow, 'fortnight'),
        ]),
      );
      expect(policy.window, RefundWindow.days7);
    });

    test('a configured window is honoured', () {
      final policy = RefundPolicy.from(
        resolve([
          row(SettingScope.business, SettingKey.refundWindow, 'same_day'),
          row(SettingScope.business, SettingKey.refundEnabled, 'false'),
        ]),
      );
      expect(policy.window, RefundWindow.sameDay);
      expect(policy.enabled, isFalse);
    });
  });
}
