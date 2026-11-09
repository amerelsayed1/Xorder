import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos_waiter/app.dart';
import 'package:xorder_pos_waiter/mode.dart';
import 'package:xorder_pos_waiter/state.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The handheld end to end against a fake till (waiter-app, WA1; sign-in
/// WA3): sign in with address, name and PIN, open a table, add, send — at a
/// phone's size and a tablet's, in Arabic (the default) and English. And the
/// cloud flavor's door, against the same fake standing in for xorder.io.
void main() {
  late _FakeTill till;
  late _MemoryConnection store;

  setUp(() {
    till = _FakeTill();
    store = _MemoryConnection();
  });

  Future<void> boot(WidgetTester tester, {WaiterMode mode = WaiterMode.offline, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        waiterModeProvider.overrideWithValue(mode),
        connectionStoreProvider.overrideWithValue(store),
        clientFactoryProvider.overrideWithValue((mode, target, token, pin) => till.client(mode, target, token, pin)),
      ],
      child: const WaiterApplication(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, {String? target, String? username, String pin = '1111'}) async {
    if (target != null) await tester.enterText(find.byKey(const Key('target')), target);
    if (username != null) await tester.enterText(find.byKey(const Key('username')), username);
    await tester.enterText(find.byKey(const Key('pin')), pin);
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
  }

  testWidgets('address, name and PIN; a table, an item and a round — on a phone, in Arabic', (tester) async {
    await boot(tester);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('عنوان الجهاز'), findsOneWidget, reason: 'the offline flavor asks for the till');

    await signIn(tester, target: '10.0.0.5', username: 'mona');
    expect(till.lastUri!.port, defaultWaiterPort, reason: 'a bare address gets the default port');
    expect(till.registeredAs, 'mona · linux', reason: 'the first sign-in registers the phone under the name');
    expect(store.saved!.deviceToken, 'device-token');
    expect(store.saved!.username, 'mona');
    expect(store.saved!.serverName, 'Main till');
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

  testWidgets('a remembered till and name need only the PIN; the same device signs in again', (tester) async {
    store.saved = const SavedConnection(target: '10.0.0.5:8787', username: 'mona', deviceToken: 'device-token', serverName: 'Main till');
    await boot(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Main till'), findsOneWidget, reason: 'the door says where it signs in');
    expect(tester.widget<TextField>(find.byKey(const Key('target'))).controller!.text, '10.0.0.5:8787');
    expect(tester.widget<TextField>(find.byKey(const Key('username'))).controller!.text, 'mona');

    await signIn(tester);
    expect(find.text('Tables'), findsOneWidget);
    expect(till.registeredAs, isNull, reason: 'a known device is not registered again');
    expect(till.signInTokens.single, 'device-token');
  });

  testWidgets('an item with options opens the options sheet; required ones are required', (tester) async {
    store.saved = const SavedConnection(target: '10.0.0.5:8787', username: 'mona', deviceToken: 'device-token', serverName: 'Main till');
    await boot(tester, size: const Size(800, 1280));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await signIn(tester);

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
    store.saved = const SavedConnection(target: '10.0.0.5:8787', username: 'mona', deviceToken: 'device-token', serverName: 'Main till');
    await boot(tester, size: const Size(800, 1280));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await signIn(tester);
    await tester.tap(find.byKey(const Key('table-1')));
    await tester.pumpAndSettle();

    till.conflictNext = true;
    await tester.tap(find.byKey(const Key('product-11')));
    await tester.pumpAndSettle();
    expect(find.textContaining('changed on another device'), findsOneWidget);
    expect(find.text('ROUND 1'), findsOneWidget, reason: "the other device's sent tea is shown, under its round's header");
  });

  testWidgets('a wrong PIN is worded; a revoked phone is told, then registers itself again', (tester) async {
    store.saved = const SavedConnection(target: '10.0.0.5:8787', username: 'mona', deviceToken: 'device-token', serverName: 'Main till');
    await boot(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await signIn(tester, pin: '9999');
    expect(find.text('That name and PIN were not accepted.'), findsOneWidget);

    till.revoked = true;
    await signIn(tester);
    expect(find.textContaining('removed on the till'), findsOneWidget);
    expect(store.saved!.deviceToken, isNull, reason: 'the dead token is forgotten; the till and name are kept');
    expect(store.saved!.target, '10.0.0.5:8787');

    till.revoked = false;
    await signIn(tester);
    expect(find.text('Tables'), findsOneWidget);
    expect(till.registeredAs, 'mona · linux', reason: 'signed in afresh as a new device');
    expect(store.saved!.deviceToken, 'device-token');
  });

  testWidgets('the first sign-in to a till shows its fingerprint to compare; confirming pins it', (tester) async {
    till.certificateSha256 = 'ab12' * 16;
    await boot(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await signIn(tester, target: '10.0.0.5', username: 'mona');
    expect(find.text('Is this the till?'), findsOneWidget);
    expect(find.text(('AB:12:' * 16).substring(0, 95)), findsOneWidget, reason: 'the fingerprint as the till prints it');
    expect(find.text('Valid until 2029-02-11'), findsOneWidget);
    expect(till.signInTokens, isEmpty, reason: 'no name or PIN left the phone before the till was confirmed');

    await tester.tap(find.byKey(const Key('certificate-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets, reason: 'cancelled: still at the door, nothing pinned');
    expect(store.saved?.pinnedSha256, isNull);

    await signIn(tester, target: '10.0.0.5', username: 'mona');
    await tester.tap(find.byKey(const Key('certificate-match')));
    await tester.pumpAndSettle();
    expect(find.text('Tables'), findsOneWidget);
    expect(store.saved!.pinnedSha256, 'ab12' * 16);
    expect(till.lastPin, 'ab12' * 16, reason: 'the client that signed in was made with the pin');
  });

  testWidgets('a till answering with a different certificate is refused, not re-asked', (tester) async {
    till.certificateSha256 = 'ab12' * 16;
    store.saved = SavedConnection(
      target: '10.0.0.5:8787', username: 'mona', deviceToken: 'device-token', serverName: 'Main till',
      pinnedSha256: 'ff00' * 16,
    );
    await boot(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await signIn(tester);
    expect(find.text('Is this the till?'), findsNothing);
    expect(find.textContaining('different certificate'), findsOneWidget);
    expect(store.saved!.pinnedSha256, 'ff00' * 16, reason: 'the old pin stays; only Forget clears it');
  });

  testWidgets('the cloud flavor never asks about a certificate', (tester) async {
    till.certificateSha256 = 'ab12' * 16;
    await boot(tester, mode: WaiterMode.cloud);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await signIn(tester, target: 'demo', username: 'mona');
    expect(find.text('Is this the till?'), findsNothing);
    expect(find.text('The secure connection to xorder.io could not be verified.'), findsOneWidget);
  });

  testWidgets('the cloud flavor signs in with the restaurant, a name and a PIN', (tester) async {
    await boot(tester, mode: WaiterMode.cloud);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('XOrder Waiter Cloud'), findsOneWidget);
    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('.xorder.io'), findsOneWidget, reason: 'the slug completes to the subdomain');

    await signIn(tester, target: 'Demo', username: 'mona');
    expect(till.lastMode, WaiterMode.cloud);
    expect(till.lastTarget, 'Demo');
    expect(find.text('Tables'), findsOneWidget);
    expect(store.saved!.target, 'Demo');
  });

  test('both flavors reach their server over https; only the offline one carries a pin', () {
    final cloud = defaultClientFactory(WaiterMode.cloud, 'Demo', null, null) as WaiterLinkClient;
    expect(cloud.baseUri.toString(), 'https://demo.xorder.io/api/pos/waiter');
    expect(cloud.pinnedSha256, isNull);
    final offline = defaultClientFactory(WaiterMode.offline, '10.0.0.5', 'tok', 'abc') as WaiterLinkClient;
    expect(offline.baseUri.toString(), 'https://10.0.0.5:8787');
    expect(offline.deviceToken, 'tok');
    expect(offline.pinnedSha256, 'abc');
  });
}

// ---------------------------------------------------------------------------

class _MemoryConnection implements ConnectionStore {
  SavedConnection? saved;
  @override
  Future<SavedConnection?> load() async => saved;
  @override
  Future<void> save(SavedConnection connection) async => saved = connection;
  @override
  Future<void> clear() async => saved = null;
}

const _egp = WaiterCurrency('EGP', 2);

class _FakeTill {
  String? registeredAs;
  Uri? lastUri;
  WaiterMode? lastMode;
  String? lastTarget;
  bool revoked = false;
  bool conflictNext = false;
  final ops = <WaiterOp>[];
  final signInTokens = <String?>[];
  var lines = <WaiterLine>[];
  int? version;

  /// The till's certificate; null for a fake that offers no TLS.
  String? certificateSha256;
  String? lastPin;

  WaiterClient client(WaiterMode mode, String target, String? token, String? pin) {
    lastMode = mode;
    lastTarget = target;
    lastPin = pin;
    lastUri = mode == WaiterMode.offline ? WaiterLinkClient.addressToUri(target) : null;
    return _FakeClient(this, token, pin);
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

class _FakeClient implements WaiterClient {
  _FakeClient(this.till, this.deviceToken, this.pinnedSha256);

  final _FakeTill till;
  @override
  String? deviceToken;
  final String? pinnedSha256;

  void _guard() {
    if (till.revoked && deviceToken != null) throw const WaiterLinkFailure(WaiterError.revoked, 401);
  }

  /// What a real client does at the handshake (WA4): a till with a
  /// certificate is refused unless this phone pinned exactly it.
  void _handshake() {
    final cert = till.certificateSha256;
    if (cert == null) return;
    if (pinnedSha256 == cert) return;
    throw WaiterLinkUntrustedCertificate(
      WaiterCertificate(sha256: cert, notAfter: DateTime.utc(2029, 2, 11)),
      pinned: pinnedSha256 != null,
    );
  }

  @override
  Future<String> hello() async {
    _handshake();
    return 'Main till';
  }

  @override
  Future<WaiterSession> signIn({required String username, required String pin, required String deviceName}) async {
    _handshake();
    _guard();
    till.signInTokens.add(deviceToken);
    if (username != 'mona' || pin != '1111') throw const WaiterLinkFailure(WaiterError.wrongPin, 403);
    String? issued;
    if (deviceToken == null) {
      till.registeredAs = deviceName;
      issued = deviceToken = 'device-token';
    }
    return WaiterSession(
      token: 's',
      staff: const WaiterStaff(id: 1, name: 'Mona', capabilities: {'pos.operate'}),
      deviceToken: issued,
    );
  }

  @override
  Future<void> signOut() async {}

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
}
