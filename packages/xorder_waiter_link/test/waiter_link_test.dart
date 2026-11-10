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

  Future<WaiterSession> signIn({String username = 'mona', String pin = '1111'}) =>
      client.signIn(username: username, pin: pin, deviceName: 'Phone 1');

  /// Signed in with a shift started: what working tables needs.
  Future<WaiterSession> signInOnShift() async {
    final session = await signIn();
    await client.startShift();
    return session;
  }

  Future<String> failureCode(Future<Object?> Function() call) async {
    try {
      await call();
    } on WaiterLinkFailure catch (e) {
      return e.code;
    }
    fail('expected a WaiterLinkFailure');
  }

  group('devices', () {
    test('hello answers before any sign-in, and names the till', () async {
      expect(await client.hello(), 'Main till');
    });

    test('nothing past hello and sign-in without a device token', () async {
      expect(await failureCode(client.floor), WaiterError.unpaired);
    });

    test('the first sign-in registers the device and hands back its token', () async {
      final session = await signIn();
      expect(session.deviceToken, isNotEmpty);
      expect(client.deviceToken, session.deviceToken);
      expect(till.devices.single.name, 'Phone 1');

      // The next sign-in on the same device is not a new device.
      final again = await signIn();
      expect(again.deviceToken, isNull);
      expect(till.devices, hasLength(1));
    });

    test('a revoked device is refused and must sign in afresh, as a new device', () async {
      await signIn();
      till.devices.single.revoked = true;
      expect(await failureCode(client.floor), WaiterError.revoked);
      expect(await failureCode(() => signIn()), WaiterError.revoked);

      client.deviceToken = null; // what the handheld does on DEVICE_REVOKED
      final session = await signIn();
      expect(session.deviceToken, isNotEmpty);
      expect(till.devices, hasLength(2));
    });

    test('a token the till never issued is refused', () async {
      client.deviceToken = 'made-up';
      expect(await failureCode(() => signIn()), WaiterError.unpaired);
    });
  });

  group('signing in', () {
    test('the right name and PIN give a session with the person', () async {
      final session = await signIn();
      expect(session.staff.name, 'Mona');
      expect(session.staff.can(WaiterCapability.operate), isTrue);
    });

    test('a wrong PIN, or the right PIN under the wrong name, is refused the same way', () async {
      expect(await failureCode(() => signIn(pin: '9999')), WaiterError.wrongPin);
      expect(await failureCode(() => signIn(username: 'viewer', pin: '1111')), WaiterError.wrongPin);
      expect(till.devices, isEmpty, reason: 'a refused sign-in registers nothing');
    });

    test('five wrong PINs lock the device out for a minute', () async {
      await signIn();
      for (var i = 0; i < 5; i++) {
        expect(await failureCode(() => signIn(pin: '9999')), WaiterError.wrongPin);
      }
      expect(await failureCode(() => signIn()), WaiterError.tooManyAttempts);
      now = now.add(const Duration(minutes: 2));
      expect((await signIn()).staff.name, 'Mona');
    });

    test('an unknown phone guessing PINs is cut off by its address', () async {
      for (var i = 0; i < 5; i++) {
        expect(await failureCode(() => signIn(pin: '9999')), WaiterError.wrongPin);
      }
      expect(await failureCode(() => signIn()), WaiterError.tooManyAttempts);
    });

    test('someone who may not ring up orders cannot use a handheld', () async {
      expect(await failureCode(() => signIn(username: 'viewer', pin: '2222')), WaiterError.notPermitted);
    });

    test('a session is needed past sign-in, and idles out', () async {
      await signIn();
      await client.menu();
      now = now.add(const Duration(hours: 13));
      expect(await failureCode(client.floor), WaiterError.signInRequired);
    });
  });

  group('the check', () {
    test('ops are applied by the till and the priced check comes back', () async {
      await signInOnShift();
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
      await signInOnShift();
      await client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 10)]);
      try {
        await client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 10)]);
        fail('expected a conflict');
      } on WaiterCheckChanged catch (e) {
        expect(e.current.version, 1);
      }
    });

    test('a refused edit says why and saves nothing', () async {
      await signInOnShift();
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
      await signInOnShift();
      expect(await failureCode(() => client.check(404)), WaiterError.notFound);
    });
  });

  group('the shift clock', () {
    test('tables need an open shift; the menu does not', () async {
      final session = await signIn();
      expect(session.shift, isNull);
      expect(await failureCode(client.floor), WaiterError.shiftRequired);
      expect(await failureCode(() => client.check(1)), WaiterError.shiftRequired);
      expect(
        await failureCode(() => client.apply(tableId: 1, version: null, ops: const [WaiterAdd(productId: 10)])),
        WaiterError.shiftRequired,
      );
      expect(till.lastOps, isNull, reason: 'nothing reached the till');
      await client.menu();
      expect(await client.shift(), isNull);
    });

    test('start opens a shift once; finish closes it and tables close with it', () async {
      await signIn();
      final started = await client.startShift();
      expect(started.isOpen, isTrue);
      expect((await client.startShift()).id, started.id, reason: 'a second start is the same shift');
      expect((await client.floor()).tables, hasLength(2));

      final finished = await client.finishShift();
      expect(finished.id, started.id);
      expect(finished.endedAt, isNotNull);
      expect(await client.shift(), isNull);
      expect(await failureCode(client.floor), WaiterError.shiftRequired);
      expect(await failureCode(client.finishShift), WaiterError.noOpenShift);
    });

    test("signing in again shows the shift that is still open, and the till's times", () async {
      await signIn();
      final started = await client.startShift();
      await client.signOut();
      final again = await signIn();
      expect(again.shift!.id, started.id, reason: 'signing out does not finish a shift');
      expect(again.shift!.startedAt, till.shiftStart);
    });

    test('a shift survives the trip in UTC', () {
      final shift = WaiterShift(id: 3, startedAt: DateTime.utc(2026, 11, 9, 8), endedAt: DateTime.utc(2026, 11, 9, 16, 30));
      final back = WaiterShift.fromJson(shift.toJson());
      expect(back.startedAt, shift.startedAt);
      expect(back.length(DateTime.utc(2030)), const Duration(hours: 8, minutes: 30));
      expect(WaiterShift.fromJson({'id': 1, 'started_at': '2026-11-09T08:00:00Z'}).isOpen, isTrue);
    });
  });

  group('the address', () {
    test('a typed address becomes an https base with the default port; http is corrected', () {
      expect(WaiterLinkClient.addressToUri('192.168.1.20').toString(), 'https://192.168.1.20:8787');
      expect(WaiterLinkClient.addressToUri(' 192.168.1.20:9000 ').toString(), 'https://192.168.1.20:9000');
      expect(WaiterLinkClient.addressToUri('http://till.local').toString(), 'https://till.local:8787');
    });

    test('a fingerprint is shown the way the till prints it', () {
      const cert = WaiterCertificate(sha256: 'ab12cd');
      expect(cert.formatted, 'AB:12:CD');
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

    test("a line carries its product id, and a line without one still reads", () {
      const line = WaiterLine(key: 'k1', name: WaiterName('Tea'), quantity: 2, totalMinor: 6000, productId: 11);
      expect(WaiterLine.fromJson(line.toJson()).productId, 11);
      expect(WaiterLine.fromJson({'key': 'k2', 'name': {'en': 'Tea'}, 'qty': 1, 'total_minor': 3000}).productId, isNull);
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
  Future<WaiterStaff?> signIn({required String username, required String pin}) async => switch ((username, pin)) {
    ('mona', '1111') => const WaiterStaff(id: 1, name: 'Mona', capabilities: {'pos.operate'}),
    ('viewer', '2222') => const WaiterStaff(id: 2, name: 'Viewer'),
    _ => null,
  };

  @override
  Future<WaiterMenu> menu() async => theMenu;

  final shifts = <int, WaiterShift>{};
  final shiftStart = DateTime.utc(2026, 11, 9, 17);
  var _shiftIds = 0;

  @override
  Future<WaiterShift?> openShift(int staffId) async => shifts[staffId];

  @override
  Future<WaiterShift> startShift(WaiterStaff staff, WaiterDeviceRecord device) async =>
      shifts[staff.id] ??= WaiterShift(id: ++_shiftIds, startedAt: shiftStart);

  @override
  Future<WaiterShift?> finishShift(WaiterStaff staff, WaiterDeviceRecord device) async {
    final open = shifts.remove(staff.id);
    return open == null ? null : WaiterShift(id: open.id, startedAt: open.startedAt, endedAt: shiftStart.add(const Duration(hours: 8)));
  }

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
