import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos_waiter/main.dart';
import 'package:xorder_pos_waiter/state.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The handheld end to end against a fake till (waiter-app, WA1): pair, sign
/// in, open a table, add, send — at a phone's size and a tablet's, in Arabic
/// (the default) and English.
void main() {
  late _FakeTill till;
  late _MemoryPairing store;

  setUp(() {
    till = _FakeTill();
    store = _MemoryPairing();
  });

  Future<void> boot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pairingStoreProvider.overrideWithValue(store),
        clientFactoryProvider.overrideWithValue((uri, token) => till.client(uri, token)),
      ],
      child: const WaiterApplication(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pinIn(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.byKey(Key('pin-$d')));
    }
    await tester.tap(find.byKey(const Key('pin-enter')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('pairing, PIN, a table, an item and a round — on a phone, in Arabic', (tester) async {
    await boot(tester);
    expect(find.text('الإقران بجهاز الكاشير'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('address')), '10.0.0.5');
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.enterText(find.byKey(const Key('name')), 'Phone 1');
    await tester.tap(find.byKey(const Key('pair')));
    await tester.pumpAndSettle();

    expect(till.pairedName, 'Phone 1');
    expect(till.lastUri!.port, defaultWaiterPort, reason: 'a bare address gets the default port');
    expect(store.saved!.token, 'device-token');
    expect(find.text('مقترن بـ Main till'), findsOneWidget);

    await pinIn(tester, '1111');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('الطاولات'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('table-1')));
    await tester.pumpAndSettle();
    expect(find.text('شاي'), findsOneWidget, reason: 'the menu in Arabic');

    await tester.tap(find.byKey(const Key('product-11')));
    await tester.pumpAndSettle();
    expect(till.ops.single, isA<WaiterAdd>());

    await tester.tap(find.byKey(const Key('check-tab')));
    await tester.pumpAndSettle();
    expect(find.text('لم يُرسل'), findsOneWidget, reason: 'the new line is marked unsent');
    expect(find.text('30.00 ج.م'), findsWidgets, reason: "the till's price, in Arabic");

    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(till.ops.last, isA<WaiterSendRound>());
    expect(find.text('الدفعة 1'), findsOneWidget);
  });

  testWidgets('an item with options opens the options sheet; required ones are required', (tester) async {
    store.saved = const Pairing(address: '10.0.0.5:8787', token: 'device-token', tillName: 'Main till');
    await boot(tester, size: const Size(800, 1280));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await pinIn(tester, '1111');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('table-1')));
    await tester.pumpAndSettle();
    // Tablet: the check is beside the menu, no tabs.
    expect(find.byKey(const Key('check-tab')), findsNothing);
    expect(find.byKey(const Key('send')), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-10')));
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('add-item'));
    expect(tester.widget<FilledButton>(add).onPressed, isNull, reason: 'the heat level is required');

    await tester.tap(find.byKey(const Key('option-50')));
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final op = till.ops.single as WaiterAdd;
    expect(op.productId, 10);
    expect(op.modifierIds, [50]);
    expect(find.text('Kofta'), findsWidgets);
  });

  testWidgets('a table changed on another device shows the latest check and says so', (tester) async {
    store.saved = const Pairing(address: '10.0.0.5:8787', token: 'device-token', tillName: 'Main till');
    await boot(tester, size: const Size(800, 1280));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await pinIn(tester, '1111');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-1')));
    await tester.pumpAndSettle();

    till.conflictNext = true;
    await tester.tap(find.byKey(const Key('product-11')));
    await tester.pumpAndSettle();
    expect(find.textContaining('changed on another device'), findsOneWidget);
    expect(find.text('ROUND 1'), findsOneWidget, reason: "the other device's sent tea is shown, under its round's header");
  });

  testWidgets('a wrong PIN is worded; a revoked device goes back to pairing', (tester) async {
    store.saved = const Pairing(address: '10.0.0.5:8787', token: 'device-token', tillName: 'Main till');
    await boot(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await pinIn(tester, '9999');
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN.'), findsOneWidget);

    till.revoked = true;
    await pinIn(tester, '1111');
    await tester.pumpAndSettle();
    expect(find.text('Pair with the till'), findsOneWidget);
    expect(store.saved, isNull, reason: 'the dead token is forgotten');
  });
}

// ---------------------------------------------------------------------------

class _MemoryPairing implements PairingStore {
  Pairing? saved;
  @override
  Future<Pairing?> load() async => saved;
  @override
  Future<void> save(Pairing pairing) async => saved = pairing;
  @override
  Future<void> clear() async => saved = null;
}

const _egp = WaiterCurrency('EGP', 2);

class _FakeTill {
  String? pairedName;
  Uri? lastUri;
  bool revoked = false;
  bool conflictNext = false;
  final ops = <WaiterOp>[];
  var lines = <WaiterLine>[];
  int? version;

  WaiterLinkClient client(Uri uri, String? token) {
    lastUri = uri;
    return _FakeClient(this, uri, token);
  }

  final menu = const WaiterMenu(
    currency: _egp,
    categories: [WaiterCategory(id: 1, name: WaiterName('Mains', 'رئيسي'))],
    products: [
      WaiterProduct(id: 10, categoryId: 1, name: WaiterName('Kofta', 'كفتة'), priceMinor: 10000, groupIds: [5]),
      WaiterProduct(id: 11, categoryId: 1, name: WaiterName('Tea', 'شاي'), priceMinor: 3000),
    ],
    groups: [
      WaiterModifierGroup(
        id: 5,
        name: WaiterName('Heat', 'الحرارة'),
        minSelect: 1,
        modifiers: [
          WaiterModifier(id: 50, name: WaiterName('Spicy', 'حار'), deltaMinor: 500),
          WaiterModifier(id: 51, name: WaiterName('Mild', 'عادي'), deltaMinor: 0),
        ],
      ),
    ],
  );

  WaiterCheck get check => WaiterCheck(
    tableId: 1,
    tableLabel: 'T1',
    currency: _egp,
    version: version,
    lines: lines,
    subtotalMinor: lines.fold(0, (s, l) => s + l.totalMinor),
    totalMinor: lines.fold(0, (s, l) => s + l.totalMinor),
    roundsSent: lines.any((l) => l.round != null) ? 1 : 0,
  );

  WaiterCheck apply(List<WaiterOp> applied) {
    if (conflictNext) {
      conflictNext = false;
      lines = [
        const WaiterLine(key: 'tea', name: WaiterName('Tea', 'شاي'), quantity: 1, totalMinor: 3000,
            stage: WaiterLineStage.sent, round: 1),
      ];
      version = (version ?? 0) + 1;
      throw WaiterCheckChanged(check);
    }
    for (final op in applied) {
      ops.add(op);
      switch (op) {
        case WaiterAdd():
          final p = menu.products.firstWhere((p) => p.id == op.productId);
          lines = [
            ...lines,
            WaiterLine(key: 'k${lines.length}', name: p.name, quantity: op.quantity, totalMinor: p.priceMinor * op.quantity),
          ];
        case WaiterSendRound():
          lines = [
            for (final l in lines)
              l.isDraft
                  ? WaiterLine(key: l.key, name: l.name, quantity: l.quantity, totalMinor: l.totalMinor,
                      stage: WaiterLineStage.sent, round: 1)
                  : l,
          ];
        default:
      }
    }
    version = (version ?? 0) + 1;
    return check;
  }
}

class _FakeClient implements WaiterLinkClient {
  _FakeClient(this.till, this.baseUri, this.deviceToken);

  final _FakeTill till;
  @override
  final Uri baseUri;
  @override
  String? deviceToken;
  @override
  String? sessionToken;
  @override
  Duration get timeout => const Duration(seconds: 1);

  void _guard() {
    if (till.revoked) throw const WaiterLinkFailure(WaiterError.revoked, 401);
  }

  @override
  Future<String> hello() async => 'Main till';

  @override
  Future<String> pair({required String code, required String deviceName}) async {
    if (code != '123456') throw const WaiterLinkFailure(WaiterError.badPairingCode, 403);
    till.pairedName = deviceName;
    return deviceToken = 'device-token';
  }

  @override
  Future<WaiterSession> signIn(String pin) async {
    _guard();
    if (pin != '1111') throw const WaiterLinkFailure(WaiterError.wrongPin, 403);
    sessionToken = 's';
    return const WaiterSession(token: 's', staff: WaiterStaff(id: 1, name: 'Mona', capabilities: {'pos.operate'}));
  }

  @override
  Future<void> signOut() async => sessionToken = null;

  @override
  Future<WaiterMenu> menu() async => till.menu;

  @override
  Future<WaiterFloor> floor() async {
    _guard();
    return const WaiterFloor(currency: _egp, tables: [
      WaiterTable(id: 1, label: 'T1', seats: 4),
      WaiterTable(id: 2, label: 'T2', seats: 2),
    ]);
  }

  @override
  Future<WaiterCheck> check(int tableId) async => till.check;

  @override
  Future<WaiterCheck> apply({required int tableId, required int? version, required List<WaiterOp> ops}) async =>
      till.apply(ops);

  @override
  void close() {}

  // Never reached by the screens; here so the fake is a full client.
  HttpClient get http => throw UnimplementedError();
}
