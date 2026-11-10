import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos_waiter/app.dart';
import 'package:xorder_pos_waiter/mode.dart';
import 'package:xorder_pos_waiter/screens/widgets.dart';
import 'package:xorder_pos_waiter/state.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The WA2 design pass (docs/pos/21-waiter-handheld-design.md), pinned where
/// it changes what a waiter reads: the floor's summary and area sections, the
/// check's "not sent first, then rounds" order, the sticky check bar that
/// never sends, and the menu search.
void main() {
  late _Till till;

  setUp(() => till = _Till());

  Future<void> boot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        waiterModeProvider.overrideWithValue(WaiterMode.offline),
        connectionStoreProvider.overrideWithValue(_Remembered()),
        clientFactoryProvider.overrideWithValue((mode, target, token, pin) => _Client(till)),
      ],
      child: const WaiterApplication(),
    ));
    await tester.pumpAndSettle();
    toEnglish(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin')), '1111');
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
  }

  testWidgets('the floor says how many tables are open, paying and free, grouped by area', (tester) async {
    await boot(tester);
    expect(find.text('1 open · 1 paying · 1 free'), findsOneWidget);
    expect(find.text('TERRACE'), findsOneWidget, reason: 'an area is a section header');
    expect(find.text('INDOOR'), findsOneWidget);
    expect(find.text('Paying'), findsOneWidget, reason: 'state is a word, not only a colour');
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('3 items · 2 guests'), findsOneWidget, reason: "an open table's tile carries its count and guests");
    expect(find.text('120.00 EGP'), findsOneWidget, reason: "the open table's total, from the till");
  });

  testWidgets('the check lists unsent lines first, then rounds newest first; the bar never sends', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('table-1')));
    await tester.pumpAndSettle();

    // The sticky bar under the menu: total, what is not sent, the way to the check.
    expect(find.text('120.00 EGP'), findsOneWidget);
    expect(find.text('1 line not sent'), findsOneWidget);
    expect(find.byKey(const Key('check-bar-open')), findsOneWidget);
    expect(find.byKey(const Key('send')), findsNothing, reason: 'sending is only offered while looking at the lines');

    await tester.tap(find.byKey(const Key('check-bar-open')));
    await tester.pumpAndSettle();

    final headers = ['NOT SENT YET', 'ROUND 2', 'ROUND 1'];
    final tops = [for (final h in headers) tester.getTopLeft(find.text(h)).dy];
    expect(tops, orderedEquals([...tops]..sort()), reason: 'not sent first, then the newest round');
    expect(find.text('Send to kitchen (1)'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget, reason: 'the draft line itself says so');
    expect(find.text('Voided'), findsOneWidget);
  });

  testWidgets('the menu search filters by name in either language across categories', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('table-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product-11')), findsOneWidget);
    expect(find.byKey(const Key('product-12')), findsOneWidget);

    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product-12')), findsNothing, reason: 'the chip narrows to its category');

    await tester.enterText(find.byKey(const Key('menu-search')), 'كف');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product-12')), findsOneWidget, reason: 'a search looks across every category, in Arabic too');
    expect(find.byKey(const Key('product-11')), findsNothing);

    await tester.enterText(find.byKey(const Key('menu-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches.'), findsOneWidget);
  });

  testWidgets('a free table opens on an empty check that points at the menu', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('table-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-bar-open')), findsNothing, reason: 'no bar over nothing');
    await tester.tap(find.byKey(const Key('check-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Open the menu'), findsOneWidget);
    await tester.tap(find.text('Open the menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-search')), findsOneWidget);
  });

  test('money reads as the till formats it, with the pound in Arabic', () {
    const egp = WaiterCurrency('EGP', 2);
    expect(moneyText(egp, 12050, arabic: false), '120.50 EGP');
    expect(moneyText(egp, 12050, arabic: true), '120.50 ج.م');
  });
}

// ---------------------------------------------------------------------------

class _Remembered implements ConnectionStore {
  @override
  Future<SavedConnection?> load() async =>
      const SavedConnection(target: '10.0.0.5:8787', username: 'mona', deviceToken: 't', serverName: 'Main till');
  @override
  Future<void> save(SavedConnection connection) async {}
  @override
  Future<void> clear() async {}
}

const _egp = WaiterCurrency('EGP', 2);

class _Till {
  final menu = const WaiterMenu(
    currency: _egp,
    categories: [
      WaiterCategory(id: 1, name: WaiterName('Drinks', 'مشروبات')),
      WaiterCategory(id: 2, name: WaiterName('Mains', 'رئيسي')),
    ],
    products: [
      WaiterProduct(id: 11, categoryId: 1, name: WaiterName('Tea', 'شاي'), priceMinor: 3000),
      WaiterProduct(id: 12, categoryId: 2, name: WaiterName('Kofta', 'كفتة'), priceMinor: 10000),
    ],
    groups: [],
  );

  final floor = const WaiterFloor(currency: _egp, tables: [
    WaiterTable(id: 1, label: 'T1', area: 'Terrace', state: WaiterTableState.open, totalMinor: 12000, items: 3, guests: 2),
    WaiterTable(id: 2, label: 'T2', area: 'Terrace', seats: 4),
    WaiterTable(id: 3, label: 'B1', area: 'Indoor', state: WaiterTableState.billAsked, totalMinor: 4500, items: 1),
  ]);

  WaiterCheck check(int tableId) => tableId == 1
      ? const WaiterCheck(
          tableId: 1,
          tableLabel: 'T1',
          currency: _egp,
          version: 3,
          lines: [
            WaiterLine(key: 'a', name: WaiterName('Tea', 'شاي'), quantity: 1, totalMinor: 3000, stage: WaiterLineStage.sent, round: 1),
            WaiterLine(key: 'b', name: WaiterName('Kofta', 'كفتة'), quantity: 1, totalMinor: 10000, stage: WaiterLineStage.voided, round: 1),
            WaiterLine(key: 'c', name: WaiterName('Tea', 'شاي'), quantity: 2, totalMinor: 6000, stage: WaiterLineStage.sent, round: 2),
            WaiterLine(key: 'd', name: WaiterName('Tea', 'شاي'), quantity: 1, totalMinor: 3000),
          ],
          subtotalMinor: 12000,
          totalMinor: 12000,
          roundsSent: 2,
          guests: 2,
        )
      : WaiterCheck.empty(tableId: tableId, tableLabel: 'T$tableId', currency: _egp);
}

class _Client implements WaiterClient {
  _Client(this.till);
  final _Till till;

  @override
  String? deviceToken = 't';

  @override
  Future<String> hello() async => 'Main till';
  @override
  Future<WaiterSession> signIn({required String username, required String pin, required String deviceName}) async =>
      WaiterSession(
        token: 's',
        staff: const WaiterStaff(id: 1, name: 'Mona', capabilities: {'pos.operate'}),
        shift: WaiterShift(id: 1, startedAt: DateTime.now().subtract(const Duration(hours: 2))),
      );
  @override
  Future<void> signOut() async {}
  @override
  Future<WaiterMenu> menu() async => till.menu;
  @override
  Future<WaiterFloor> floor() async => till.floor;
  @override
  Future<WaiterCheck> check(int tableId) async => till.check(tableId);
  @override
  Future<WaiterCheck> apply({required int tableId, required int? version, required List<WaiterOp> ops}) async =>
      till.check(tableId);
  @override
  Future<WaiterShift?> shift() async => null;
  @override
  Future<WaiterShift> startShift() async => WaiterShift(id: 1, startedAt: DateTime.now());
  @override
  Future<WaiterShift> finishShift() async => throw const WaiterLinkFailure(WaiterError.noOpenShift, 409);
  @override
  void close() {}
}

/// The app bar has no language switch; English-worded tests flip the locale
/// through the app's own state instead.
void toEnglish(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WaiterApplication))).read(waiterAppProvider.notifier).toggleLanguage();
