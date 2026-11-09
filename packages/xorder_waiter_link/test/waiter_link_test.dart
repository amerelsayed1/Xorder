import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The link end to end over a real loopback socket: the handheld's client
/// against the till's server, with a fake till behind it (waiter-app, WA1).
void main() {
  late _FakeTill till;
  late WaiterLinkServer server;
  late HttpServer http;
  late WaiterLinkClient client;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 11, 9, 20);
    till = _FakeTill();
    server = WaiterLinkServer(backend: till, clock: () => now, random: Random(7));
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.attach(http);
    client = WaiterLinkClient(baseUri: Uri.parse('http://127.0.0.1:${http.port}'));
  });

  tearDown(() async {
    client.close();
    await http.close(force: true);
  });

  Future<void> pairAndSignIn({String pin = '1111'}) async {
    final code = server.openPairing().code;
    await client.pair(code: code, deviceName: 'Phone 1');
    await client.signIn(pin);
  }

  Future<String> failureCode(Future<Object?> Function() call) async {
    try {
      await call();
    } on WaiterLinkFailure catch (e) {
      return e.code;
    }
    fail('expected a WaiterLinkFailure');
  }

  group('pairing', () {
    test('hello answers before pairing, and names the till', () async {
      expect(await client.hello(), 'Main till');
    });

    test('nothing past hello without a device token', () async {
      expect(await failureCode(() => client.signIn('1111')), WaiterError.unpaired);
    });

    test('the code the till shows pairs one device, once', () async {
      final code = server.openPairing().code;
      expect(code, matches(RegExp(r'^\d{6}$')));
      final token = await client.pair(code: code, deviceName: 'Phone 1');
      expect(token, isNotEmpty);
      expect(till.devices.single.name, 'Phone 1');

      final second = WaiterLinkClient(baseUri: client.baseUri);
      addTearDown(second.close);
      expect(
        await failureCode(() => second.pair(code: code, deviceName: 'Phone 2')),
        WaiterError.badPairingCode,
      );
    });

    test('an expired code is refused', () async {
      final code = server.openPairing().code;
      now = now.add(const Duration(minutes: 11));
      expect(
        await failureCode(() => client.pair(code: code, deviceName: 'x')),
        WaiterError.badPairingCode,
      );
    });

    test('guessing codes is cut off after five tries', () async {
      server.openPairing();
      for (var i = 0; i < 5; i++) {
        await failureCode(() => client.pair(code: '000000', deviceName: 'x'));
      }
      final code = server.currentPairing!.code;
      expect(
        await failureCode(() => client.pair(code: code, deviceName: 'x')),
        WaiterError.tooManyAttempts,
      );
    });
  });

  group('signing in', () {
    test('the right PIN gives a session with the person', () async {
      await client.pair(code: server.openPairing().code, deviceName: 'Phone');
      final session = await client.signIn('1111');
      expect(session.staff.name, 'Mona');
      expect(session.staff.can(WaiterCapability.operate), isTrue);
    });

    test('a wrong PIN is refused, and five lock the device out', () async {
      await client.pair(code: server.openPairing().code, deviceName: 'Phone');
      for (var i = 0; i < 5; i++) {
        expect(await failureCode(() => client.signIn('9999')), WaiterError.wrongPin);
      }
      expect(await failureCode(() => client.signIn('1111')), WaiterError.tooManyAttempts);
      now = now.add(const Duration(minutes: 2));
      expect((await client.signIn('1111')).staff.name, 'Mona');
    });

    test('someone who may not ring up orders cannot use a handheld', () async {
      await client.pair(code: server.openPairing().code, deviceName: 'Phone');
      expect(await failureCode(() => client.signIn('2222')), WaiterError.notPermitted);
    });

    test('the menu and floor need a signed-in waiter', () async {
      await client.pair(code: server.openPairing().code, deviceName: 'Phone');
      expect(await failureCode(client.menu), WaiterError.signInRequired);
      await client.signIn('1111');
      expect((await client.menu()).products.single.name.en, 'Koshary');
      expect((await client.floor()).tables, hasLength(2));
    });

    test('a session left idle past its limit must sign in again', () async {
      await pairAndSignIn();
      now = now.add(const Duration(hours: 13));
      expect(await failureCode(client.floor), WaiterError.signInRequired);
    });

    test('a revoked device is refused and its sessions end', () async {
      await pairAndSignIn();
      till.devices.single.revoked = true;
      expect(await failureCode(client.floor), WaiterError.revoked);
    });
  });

  group('the check', () {
    test('ops are applied by the till and the priced check comes back', () async {
      await pairAndSignIn();
      final check = await client.apply(
        tableId: 1,
        version: null,
        ops: const [WaiterAdd(productId: 10, quantity: 2), WaiterSendRound()],
      );
      expect(check.version, 1);
      expect(check.totalMinor, 9000);
      expect(till.lastOps, hasLength(2));
      expect(till.lastStaff!.name, 'Mona');
    });

    test('a stale version comes back as the current check', () async {
      await pairAndSignIn();
      await client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 10)]);
      try {
        await client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 10)]);
        fail('expected a conflict');
      } on WaiterCheckChanged catch (e) {
        expect(e.current.version, 1);
      }
    });

    test('a refused edit says why and saves nothing', () async {
      await pairAndSignIn();
      try {
        await client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 99)]);
        fail('expected a refusal');
      } on WaiterLinkFailure catch (e) {
        expect(e.code, WaiterError.refused);
        expect(e.detail, 'unknown_product');
      }
      expect(till.versions[1], isNull);
    });

    test('an unknown table is not found', () async {
      await pairAndSignIn();
      expect(await failureCode(() => client.check(404)), WaiterError.notFound);
    });
  });

  group('the wire', () {
    test('a menu survives the trip', () {
      final menu = till.theMenu;
      final back = WaiterMenu.fromJson(menu.toJson());
      expect(back.groups.single.modifiers.single.deltaMinor, 500);
      expect(back.products.single.name.pick(arabic: true), 'كشري');
      expect(back.groupsOf(back.products.single).single.id, 3);
    });

    test('ops survive the trip', () {
      const ops = <WaiterOp>[
        WaiterAdd(productId: 1, modifierIds: [2, 3], quantity: 2, note: 'no onion'),
        WaiterChangeQuantity(lineKey: 'k', delta: -1),
        WaiterRemoveLine(lineKey: 'k'),
        WaiterSetNote(lineKey: 'k', note: 'hot'),
        WaiterSetGuests(4),
        WaiterSendRound(),
      ];
      final back = [for (final op in ops) WaiterOp.fromJson(op.toJson())];
      expect([for (final op in back) op.toJson()], [for (final op in ops) op.toJson()]);
    });

    test('money formats from minor units without a double', () {
      expect(const WaiterMoney(123450, currency: 'EGP', exponent: 2).format(), '1234.50');
      expect(const WaiterMoney(5, currency: 'KWD', exponent: 3).format(), '0.005');
      expect(const WaiterMoney(-250, currency: 'EGP', exponent: 2).format(), '-2.50');
    });

    test('an unknown table state reads as free rather than failing', () {
      expect(WaiterTable.fromJson({'id': 1, 'label': 'T1', 'state': 'odd'}).state, WaiterTableState.free);
    });
  });
}

class _Device {
  _Device(this.id, this.name, this.token);
  final int id;
  final String name;
  final String token;
  bool revoked = false;
}

class _FakeTill implements WaiterLinkBackend {
  final devices = <_Device>[];
  final versions = <int, int>{};
  List<WaiterOp>? lastOps;
  WaiterStaff? lastStaff;

  static const egp = WaiterCurrency('EGP', 2);

  final theMenu = const WaiterMenu(
    currency: egp,
    categories: [WaiterCategory(id: 1, name: WaiterName('Mains', 'رئيسي'))],
    products: [
      WaiterProduct(
        id: 10,
        categoryId: 1,
        name: WaiterName('Koshary', 'كشري'),
        priceMinor: 4500,
        groupIds: [3],
      ),
    ],
    groups: [
      WaiterModifierGroup(
        id: 3,
        name: WaiterName('Extras'),
        maxSelect: 2,
        modifiers: [WaiterModifier(id: 30, name: WaiterName('Fried onion'), deltaMinor: 500)],
      ),
    ],
  );

  @override
  Future<String> tillName() async => 'Main till';

  @override
  Future<WaiterPairedDevice> registerDevice(String name) async {
    final d = _Device(devices.length + 1, name, 'tok-${devices.length + 1}');
    devices.add(d);
    return WaiterPairedDevice(id: d.id, token: d.token);
  }

  @override
  Future<WaiterDeviceRecord?> authenticate(String token) async {
    for (final d in devices) {
      if (d.token == token) return WaiterDeviceRecord(id: d.id, name: d.name, revoked: d.revoked);
    }
    return null;
  }

  @override
  Future<void> touchDevice(int id) async {}

  @override
  Future<WaiterStaff?> signIn(String pin) async => switch (pin) {
    '1111' => const WaiterStaff(id: 1, name: 'Mona', capabilities: {'pos.operate'}),
    '2222' => const WaiterStaff(id: 2, name: 'Viewer'),
    _ => null,
  };

  @override
  Future<WaiterMenu> menu() async => theMenu;

  @override
  Future<WaiterFloor> floor() async => const WaiterFloor(
    currency: egp,
    tables: [WaiterTable(id: 1, label: 'T1'), WaiterTable(id: 2, label: 'T2')],
  );

  WaiterCheck _check(int tableId) => WaiterCheck(
    tableId: tableId,
    tableLabel: 'T$tableId',
    currency: egp,
    version: versions[tableId],
    lines: const [],
    totalMinor: 9000,
  );

  @override
  Future<WaiterCheck?> check(int tableId) async => tableId > 2 ? null : _check(tableId);

  @override
  Future<WaiterApplyResult> apply({
    required int tableId,
    required int? expectedVersion,
    required List<WaiterOp> ops,
    required WaiterStaff staff,
    required WaiterDeviceRecord device,
  }) async {
    if (tableId > 2) return const WaiterNoTable();
    if (versions[tableId] != expectedVersion) return WaiterConflict(_check(tableId));
    for (final op in ops) {
      if (op is WaiterAdd && op.productId != 10) return const WaiterRefusal('unknown_product');
    }
    lastOps = ops;
    lastStaff = staff;
    versions[tableId] = (versions[tableId] ?? 0) + 1;
    return WaiterApplied(_check(tableId));
  }
}
