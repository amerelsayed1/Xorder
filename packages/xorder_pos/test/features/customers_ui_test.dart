import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/customer.dart';
import 'package:xorder_pos/domain/models/customer_summary.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_customers_pane.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// People › Customers.
///
/// The queries are `test/data/customer_directory_test.dart`'s. What only a
/// widget test can say is that the page tells the truth about the person it
/// shows — somebody who has never ordered is "never" and a dash, not zero
/// spent — that a search is one read after a pause rather than one per
/// keystroke, and that a name beside what somebody spends is not drawn for a
/// person who may not see it.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

/// May enter Admin Mode, and may not read a report — which is what gates a name
/// beside what somebody spends.
const _noReports = PosStaff(
  id: 2,
  name: 'Rana A.',
  username: 'rana',
  role: PosRole(
    id: 9,
    code: 'rota',
    nameEn: 'Rota',
    capabilities: {PosCapability.adminEnter},
  ),
);

const _mona = PosCustomer(
  id: 1,
  name: 'Mona Fathy',
  phone: '01012345678',
  email: 'mona@example.com',
  address: '12 Nile St',
  note: 'Allergic to sesame',
);
const _nour = PosCustomer(id: 2, name: 'Nour Hassan', phone: '01212345678');

final _monaSummary = CustomerSummary(
  customer: _mona,
  orders: 2,
  spent: const Money(30000),
  refunded: const Money(7500),
  lastOrderAt: DateTime(2026, 9, 11, 14, 30),
);
const _nourSummary = CustomerSummary(
  customer: _nour,
  orders: 0,
  spent: Money(0),
  refunded: Money(0),
);

class _Directory implements CustomerDirectoryRepository {
  _Directory({this.customers = const [], this.orders = const {}, this.fail = false});

  final List<CustomerSummary> customers;
  final Map<int, List<CustomerOrder>> orders;
  final bool fail;

  /// Every query a list was asked for, in order.
  final queries = <String>[];
  final orderReads = <int>[];

  @override
  Future<List<CustomerSummary>> list({String query = '', int limit = 100}) async {
    queries.add(query);
    if (fail) throw StateError('directory unavailable');
    final needle = query.toLowerCase();
    return [
      for (final s in customers)
        if (needle.isEmpty ||
            s.customer.name.toLowerCase().contains(needle) ||
            s.customer.phone.contains(needle))
          s,
    ];
  }

  @override
  Future<List<CustomerOrder>> recentOrders(int customerId, {int limit = 20}) async {
    orderReads.add(customerId);
    return orders[customerId] ?? const [];
  }
}

class _InAdminMode extends AdminSessionController {
  _InAdminMode(this.staff);

  final PosStaff staff;

  @override
  AdminSession? build() =>
      AdminSession(staff: staff, startedAt: DateTime(2026, 9, 10, 9));
}

Future<_Directory?> _pane(
  WidgetTester tester, {
  _Directory? directory,
  PosStaff staff = _owner,
  bool database = true,
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1280, 1400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = database ? (directory ?? _Directory()) : null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeRepositoryOverrides(english: language == 'en'),
        customerDirectoryRepositoryProvider.overrideWithValue(repository),
        adminSessionProvider.overrideWith(() => _InAdminMode(staff)),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: const Scaffold(body: ManagementCustomersPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// Every caption at or under [key], in reading order.
List<String> _texts(WidgetTester tester, String key) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  ))
    ?text.data,
];

void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  group('the list', () {
    testWidgets('a customer: name, phone, orders, what they kept, last seen', (
      tester,
    ) async {
      await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );

      // 300.00 spent less 75.00 refunded.
      expect(_texts(tester, 'customer-row-1'), [
        'Mona Fathy',
        '01012345678',
        '2',
        '225.00 EGP',
        '2026-09-11 14:30',
      ]);
    });

    testWidgets('somebody who never ordered is "never" and a dash — not zero', (
      tester,
    ) async {
      await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );

      expect(_texts(tester, 'customer-row-2'), [
        'Nour Hassan',
        '01212345678',
        '0',
        '—',
        s.customersNever,
      ]);
    });

    testWidgets('says what the figures are, once', (tester) async {
      await _pane(tester, directory: _Directory(customers: [_monaSummary]));

      expect(find.text(s.customersBranchOnly), findsOneWidget);
    });

    testWidgets('an empty directory says how customers get on it', (tester) async {
      await _pane(tester);

      expect(find.text(s.customersNone), findsOneWidget);
      expect(find.byKey(const Key('customer-row-1')), findsNothing);
    });
  });

  group('search', () {
    testWidgets('one read after a pause, not one per keystroke', (tester) async {
      final directory = await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );
      expect(directory!.queries, ['']);

      for (final typed in ['m', 'mo', 'mon', 'mona']) {
        await tester.enterText(find.byKey(const Key('customers-search')), typed);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(directory.queries, ['', 'mona']);
    });

    testWidgets('narrows the list to who matches', (tester) async {
      await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );

      await tester.enterText(find.byKey(const Key('customers-search')), 'nour');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-row-2')), findsOneWidget);
      expect(find.byKey(const Key('customer-row-1')), findsNothing);
    });

    testWidgets('a phone fragment finds them too', (tester) async {
      await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );

      await tester.enterText(find.byKey(const Key('customers-search')), '0101');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-row-1')), findsOneWidget);
    });

    testWidgets('no match is said, and is not "no customers"', (tester) async {
      await _pane(tester, directory: _Directory(customers: [_monaSummary]));

      await tester.enterText(find.byKey(const Key('customers-search')), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text(s.customersNoMatch), findsOneWidget);
      expect(find.text(s.customersNone), findsNothing);
    });
  });

  group('one customer', () {
    final orders = {
      1: [
        CustomerOrder(
          orderId: 21,
          invoiceNumber: 'POS-21',
          occurredAt: DateTime(2026, 9, 11, 14, 30),
          total: const Money(10000),
          refunded: const Money(7500),
        ),
        CustomerOrder(
          orderId: 20,
          invoiceNumber: 'POS-20',
          occurredAt: DateTime(2026, 9, 10, 12),
          total: const Money(20000),
          refunded: const Money(0),
        ),
      ],
    };

    Future<_Directory> open(WidgetTester tester) async {
      final directory = (await _pane(
        tester,
        directory: _Directory(
          customers: [_monaSummary, _nourSummary],
          orders: orders,
        ),
      ))!;
      await tester.tap(find.byKey(const Key('customer-row-1')));
      await tester.pumpAndSettle();
      return directory;
    }

    testWidgets('how to reach them', (tester) async {
      await open(tester);

      final dialog = find.byKey(const Key('customer-detail'));
      for (final shown in [
        'Mona Fathy',
        '01012345678',
        'mona@example.com',
        '12 Nile St',
        'Allergic to sesame',
      ]) {
        expect(
          find.descendant(of: dialog, matching: find.text(shown)),
          findsOneWidget,
          reason: shown,
        );
      }
    });

    testWidgets('what they have bought, net of refunds', (tester) async {
      await open(tester);

      expect(_texts(tester, 'customer-orders'), ['2']);
      final dialog = find.byKey(const Key('customer-detail'));
      // 300.00 − 75.00; the average is that over two orders; the 75.00 is said.
      expect(
        find.descendant(of: dialog, matching: find.text('225.00 EGP')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('112.50 EGP')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('75.00 EGP')),
        findsWidgets,
      );
    });

    testWidgets('their recent orders, each net of its own refund', (tester) async {
      await open(tester);

      expect(_texts(tester, 'customer-order-21'), [
        'POS-21',
        '2026-09-11 14:30',
        '25.00 EGP',
      ]);
      expect(_texts(tester, 'customer-order-20'), [
        'POS-20',
        '2026-09-10 12:00',
        '200.00 EGP',
      ]);
    });

    testWidgets('somebody who never ordered has no orders and no average', (
      tester,
    ) async {
      await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary, _nourSummary]),
      );
      await tester.tap(find.byKey(const Key('customer-row-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-no-orders')), findsOneWidget);
      expect(find.text(s.customersDetailAverage.toUpperCase()), findsNothing);
      expect(find.text(s.customersDetailRefunded.toUpperCase()), findsNothing);
    });

    testWidgets('a refund is only mentioned when there was one', (tester) async {
      await _pane(
        tester,
        directory: _Directory(
          customers: [
            CustomerSummary(
              customer: _mona,
              orders: 1,
              spent: const Money(10000),
              refunded: Money.zero,
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('customer-row-1')));
      await tester.pumpAndSettle();

      expect(find.text(s.customersDetailRefunded.toUpperCase()), findsNothing);
    });

    testWidgets('reads that customer\'s orders, and only theirs', (tester) async {
      final directory = await open(tester);

      expect(directory.orderReads, [1]);
    });

    testWidgets('closes', (tester) async {
      await open(tester);

      await tester.tap(find.text(s.close));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-detail')), findsNothing);
    });
  });

  group('when it cannot be shown', () {
    testWidgets('no database is said, not drawn as an empty directory', (
      tester,
    ) async {
      await _pane(tester, database: false);

      expect(find.text(s.reportNoDatabase), findsOneWidget);
      expect(find.text(s.customersNone), findsNothing);
    });

    testWidgets('a failed read says so', (tester) async {
      await _pane(tester, directory: _Directory(fail: true));

      expect(find.text(s.reportUnavailable), findsOneWidget);
    });

    testWidgets('somebody who may not read reports sees no customers, and '
        'nothing is read for them', (tester) async {
      final directory = await _pane(
        tester,
        directory: _Directory(customers: [_monaSummary]),
        staff: _noReports,
      );

      expect(find.byKey(const Key('customer-row-1')), findsNothing);
      expect(find.text('Mona Fathy'), findsNothing);
      expect(directory!.queries, isEmpty);
    });
  });

  testWidgets('in Arabic it is the owner\'s word, and still fits', (tester) async {
    await _pane(
      tester,
      directory: _Directory(customers: [_monaSummary, _nourSummary]),
      language: 'ar',
    );

    const ar = ArStrings();
    expect(find.text(ar.customersColumnCustomer.toUpperCase()), findsOneWidget);
    expect(find.text(ar.customersBranchOnly), findsOneWidget);
    expect(find.text(ar.customersNever), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
