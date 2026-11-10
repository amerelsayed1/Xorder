import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'wire.dart';

/// The till's side of the waiter link (waiter-app, WA1; sign-in revised WA3).
///
/// Runs inside the till that holds the tables — the offline app's main device,
/// or a cloud till, which keeps its own tables (pos-cloud-single-till-sqlite).
/// Handhelds talk only to this; they never hold a database password (FEATURE
/// T4, TECHNICAL section 2).
///
/// Two keys, from the outside in:
/// 1. **A device token.** A handheld's first sign-in names the device and the
///    till registers it, handing back a token the handheld keeps and sends on
///    every later request. The till lists its devices and revokes any of them;
///    a request with an unknown or revoked token is refused before anything
///    else is read. There is no pairing code (owner decision, 2026-11-09:
///    the sign-in is address, name and PIN, nothing more), so the name and
///    PIN are the whole gate — which is why TLS on this link is required
///    before any pilot, and why wrong PINs are counted per device and, for a
///    device the till does not know yet, per address.
/// 2. **A waiter session**, from that person's name and PIN on that device,
///    matched as the till's own lock screen matches them. Every edit is made
///    as, and checked against, the signed-in person.
///
/// Everything about the money — prices, tax, rounds, the version check that
/// stops two devices overwriting one table — is the backend's, which is the
/// till's own `TicketEngine` and repositories. This class only routes.
class WaiterLinkServer {
  WaiterLinkServer({
    required this.backend,
    DateTime Function()? clock,
    Random? random,
    this.sessionIdle = const Duration(hours: 12),
    this.maxFailures = 5,
    this.lockout = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final WaiterLinkBackend backend;
  final DateTime Function() _clock;
  final Random _random;
  final Duration sessionIdle;
  final int maxFailures;
  final Duration lockout;

  final _sessions = <String, _Session>{};
  final _failures = <String, _Failures>{};

  /// Sign every session of [deviceId] out — the till revoked the device.
  void forgetDevice(int deviceId) =>
      _sessions.removeWhere((_, s) => s.deviceId == deviceId);

  // ---------------------------------------------------------------- serving

  /// Serve [server] until it closes. Each request is handled on its own; one
  /// that throws is answered 500 and logged by the caller's zone, never left
  /// hanging (a handheld waiting on a socket is a waiter standing at a table).
  StreamSubscription<HttpRequest> attach(HttpServer server) =>
      server.listen((request) => unawaited(handle(request)));

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    try {
      final reply = await _route(request);
      await _send(response, reply.status, reply.body);
    } on WaiterWireError catch (e) {
      await _send(response, HttpStatus.badRequest, _error(WaiterError.badRequest, e.message));
    } on FormatException catch (e) {
      await _send(response, HttpStatus.badRequest, _error(WaiterError.badRequest, e.message));
    } on Object catch (e) {
      await _send(
        response,
        HttpStatus.internalServerError,
        _error(WaiterError.unavailable, '$e'),
      );
    }
  }

  Future<_Reply> _route(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.isEmpty || segments.first != 'v$waiterWireVersion') {
      return _Reply(HttpStatus.upgradeRequired, _error(WaiterError.versionMismatch));
    }
    final path = segments.skip(1).toList();
    final method = request.method;

    if (method == 'GET' && _is(path, ['hello'])) {
      return _Reply(HttpStatus.ok, {'wire': waiterWireVersion, 'name': await backend.tillName()});
    }
    // Sign-in is the one call a device the till does not know yet may make.
    if (method == 'POST' && _is(path, ['sign-in'])) return _signIn(request);

    // Everything below needs a registered, unrevoked device.
    final device = await _device(request);
    if (device is _Reply) return device;
    final paired = device as WaiterDeviceRecord;
    unawaited(backend.touchDevice(paired.id).catchError((_) {}));
    if (method == 'POST' && _is(path, ['sign-out'])) {
      final token = request.headers.value(sessionHeader);
      if (token != null) _sessions.remove(token);
      return const _Reply(HttpStatus.ok, {'ok': true});
    }

    // And everything below needs a signed-in waiter on that device.
    final session = _session(request, paired);
    if (session == null) {
      return _Reply(HttpStatus.unauthorized, _error(WaiterError.signInRequired));
    }

    if (method == 'GET' && _is(path, ['menu'])) {
      return _Reply(HttpStatus.ok, (await backend.menu()).toJson());
    }

    // The shift clock: one open shift per waiter, whichever device.
    if (method == 'GET' && _is(path, ['shift'])) {
      return _Reply(HttpStatus.ok, {'shift': (await backend.openShift(session.staff.id))?.toJson()});
    }
    if (method == 'POST' && _is(path, ['shift', 'start'])) {
      final shift = await backend.startShift(session.staff, paired);
      return _Reply(HttpStatus.ok, {'shift': shift.toJson()});
    }
    if (method == 'POST' && _is(path, ['shift', 'finish'])) {
      final shift = await backend.finishShift(session.staff, paired);
      return shift == null
          ? _Reply(HttpStatus.conflict, _error(WaiterError.noOpenShift))
          : _Reply(HttpStatus.ok, {'shift': shift.toJson()});
    }

    // Tables are worked on the clock: no open shift, no floor.
    if (await backend.openShift(session.staff.id) == null) {
      return _Reply(HttpStatus.forbidden, _error(WaiterError.shiftRequired));
    }

    if (method == 'GET' && _is(path, ['floor'])) {
      return _Reply(HttpStatus.ok, (await backend.floor()).toJson());
    }
    if (path.length == 3 && path[0] == 'tables') {
      final tableId = int.tryParse(path[1]);
      if (tableId == null) return _Reply(HttpStatus.notFound, _error(WaiterError.notFound));
      if (method == 'GET' && path[2] == 'check') {
        final check = await backend.check(tableId);
        return check == null
            ? _Reply(HttpStatus.notFound, _error(WaiterError.notFound))
            : _Reply(HttpStatus.ok, check.toJson());
      }
      if (method == 'POST' && path[2] == 'ops') {
        return _apply(request, tableId, session.staff, paired);
      }
    }
    return _Reply(HttpStatus.notFound, _error(WaiterError.notFound));
  }

  /// The device behind the request's token: the record, a refusal, or null
  /// when the request carries no token at all.
  Future<Object?> _device(HttpRequest request, {bool required = true}) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    const scheme = 'Device ';
    if (!header.startsWith(scheme)) {
      return required ? _Reply(HttpStatus.unauthorized, _error(WaiterError.unpaired)) : null;
    }
    final record = await backend.authenticate(header.substring(scheme.length).trim());
    if (record == null) return _Reply(HttpStatus.unauthorized, _error(WaiterError.unpaired));
    if (record.revoked) {
      forgetDevice(record.id);
      return _Reply(HttpStatus.unauthorized, _error(WaiterError.revoked));
    }
    return record;
  }

  /// Name and PIN open a session. A request with no device token is a
  /// handheld the till has not met: once the person is accepted, the till
  /// registers the device under the name the handheld gives itself and hands
  /// the token back with the session. A known token is used as it is; an
  /// unknown or revoked one is refused, so a revoked phone must sign in afresh
  /// — and shows up on the till as a new device, where it can be revoked again.
  Future<_Reply> _signIn(HttpRequest request) async {
    final known = await _device(request, required: false);
    if (known is _Reply) return known;
    final device = known as WaiterDeviceRecord?;

    final key = 'pin:${device?.id ?? 'ip:${request.connectionInfo?.remoteAddress.address ?? '?'}'}';
    if (_lockedOut(key)) {
      return _Reply(HttpStatus.tooManyRequests, _error(WaiterError.tooManyAttempts));
    }
    final body = await _json(request);
    final username = body['username'];
    final pin = body['pin'];
    final staff = username is String && username.trim().isNotEmpty && pin is String && pin.isNotEmpty
        ? await backend.signIn(username: username.trim(), pin: pin)
        : null;
    if (staff == null) {
      _fail(key);
      return _Reply(HttpStatus.forbidden, _error(WaiterError.wrongPin));
    }
    if (!staff.can(WaiterCapability.operate)) {
      return _Reply(
        HttpStatus.forbidden,
        _error(WaiterError.notPermitted, WaiterCapability.operate),
      );
    }
    _failures.remove(key);

    var deviceId = device?.id;
    String? deviceToken;
    if (deviceId == null) {
      final name = body['device_name'];
      final registered = await backend.registerDevice(
        name is String && name.trim().isNotEmpty ? name.trim() : 'Waiter device',
      );
      deviceId = registered.id;
      deviceToken = registered.token;
    }

    final token = _token();
    _sessions[token] = _Session(staff, deviceId, _clock());
    return _Reply(
      HttpStatus.ok,
      WaiterSession(
        token: token,
        staff: staff,
        deviceToken: deviceToken,
        shift: await backend.openShift(staff.id),
      ).toJson(),
    );
  }

  _Session? _session(HttpRequest request, WaiterDeviceRecord device) {
    final token = request.headers.value(sessionHeader);
    final s = token == null ? null : _sessions[token];
    if (s == null || s.deviceId != device.id) return null;
    final now = _clock();
    if (now.difference(s.lastUsed) > sessionIdle) {
      _sessions.remove(token);
      return null;
    }
    s.lastUsed = now;
    return s;
  }

  Future<_Reply> _apply(
    HttpRequest request,
    int tableId,
    WaiterStaff staff,
    WaiterDeviceRecord device,
  ) async {
    final body = await _json(request);
    final ops = [for (final raw in (body['ops'] as List? ?? const [])) WaiterOp.fromJson(raw)];
    if (ops.isEmpty) return _Reply(HttpStatus.badRequest, _error(WaiterError.badRequest, 'no ops'));
    final version = body['version'];
    final result = await backend.apply(
      tableId: tableId,
      expectedVersion: version is int ? version : null,
      ops: ops,
      staff: staff,
      device: device,
    );
    return switch (result) {
      WaiterApplied(:final check) => _Reply(HttpStatus.ok, check.toJson()),
      WaiterConflict(:final current) => _Reply(HttpStatus.conflict, {
        ..._error(WaiterError.checkChanged),
        'check': current.toJson(),
      }),
      WaiterRefusal(:final reason) => _Reply(
        HttpStatus.unprocessableEntity,
        {..._error(WaiterError.refused), 'reason': reason},
      ),
      WaiterForbidden(:final capability) => _Reply(
        HttpStatus.forbidden,
        _error(WaiterError.notPermitted, capability),
      ),
      WaiterNoTable() => _Reply(HttpStatus.notFound, _error(WaiterError.notFound)),
    };
  }

  // ---------------------------------------------------------------- helpers

  static bool _is(List<String> path, List<String> wanted) =>
      path.length == wanted.length &&
      Iterable<int>.generate(path.length).every((i) => path[i] == wanted[i]);

  String _token() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  bool _lockedOut(String key) {
    final f = _failures[key];
    if (f == null || f.until == null) return false;
    if (_clock().isBefore(f.until!)) return true;
    _failures.remove(key);
    return false;
  }

  void _fail(String key) {
    final f = _failures.putIfAbsent(key, _Failures.new);
    f.count += 1;
    if (f.count >= maxFailures) f.until = _clock().add(lockout);
  }

  static Future<Map<String, Object?>> _json(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const WaiterWireError('body is not an object');
    return decoded.cast<String, Object?>();
  }

  static Map<String, Object?> _error(String code, [String? detail]) => {
    'code': code,
    'detail': ?detail,
  };

  static Future<void> _send(HttpResponse response, int status, Object body) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(jsonEncode(body));
    await response.close();
  }
}

/// Header carrying the waiter session.
const sessionHeader = 'x-waiter-session';

/// The capability names the link itself looks at. The strings are the till's
/// (`PosCapability`), repeated here so this package needs nothing from it.
abstract final class WaiterCapability {
  /// Ring up an order: the gate for using a handheld at all.
  static const operate = 'pos.operate';

  /// Take an unsent line off.
  static const cancelLine = 'order.item.delete_before_send';
}

class _Session {
  _Session(this.staff, this.deviceId, this.lastUsed);
  final WaiterStaff staff;
  final int deviceId;
  DateTime lastUsed;
}

class _Failures {
  int count = 0;
  DateTime? until;
}

class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final Object body;
}

// ---------------------------------------------------------------------------
// What the till implements.

/// A registered handheld, as the till stores it.
class WaiterDeviceRecord {
  const WaiterDeviceRecord({
    required this.id,
    required this.name,
    this.revoked = false,
    this.pairedAt,
    this.lastSeenAt,
  });
  final int id;
  final String name;
  final bool revoked;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
}

/// A device just registered, with the token it alone will ever see.
class WaiterPairedDevice {
  const WaiterPairedDevice({required this.id, required this.token});
  final int id;
  final String token;
}

sealed class WaiterApplyResult {
  const WaiterApplyResult();
}

class WaiterApplied extends WaiterApplyResult {
  const WaiterApplied(this.check);
  final WaiterCheck check;
}

/// The table moved on since the version the handheld named.
class WaiterConflict extends WaiterApplyResult {
  const WaiterConflict(this.current);
  final WaiterCheck current;
}

/// The ticket rules refused an edit; nothing was saved.
class WaiterRefusal extends WaiterApplyResult {
  const WaiterRefusal(this.reason);

  /// A stable code: `out_of_stock`, `options_required`, `too_many_options`,
  /// `line_sent`, `unknown_product`, `unknown_line`, `nothing_to_send` ...
  final String reason;
}

class WaiterForbidden extends WaiterApplyResult {
  const WaiterForbidden(this.capability);
  final String capability;
}

class WaiterNoTable extends WaiterApplyResult {
  const WaiterNoTable();
}

/// The till's half: its repositories and its `TicketEngine`, behind the
/// questions the link asks.
abstract interface class WaiterLinkBackend {
  /// What the handheld calls this till ("Main till — Maadi").
  Future<String> tillName();

  /// Store a new device and return its token. The till keeps only a hash.
  Future<WaiterPairedDevice> registerDevice(String name);

  /// The device a token belongs to, revoked or not; null for a token the till
  /// has never issued.
  Future<WaiterDeviceRecord?> authenticate(String token);

  Future<void> touchDevice(int id);

  /// The person [username] names, if [pin] is theirs — matched together, as
  /// the till's own lock screen matches them; null otherwise, with nothing
  /// said about which of the two was wrong.
  Future<WaiterStaff?> signIn({required String username, required String pin});

  Future<WaiterMenu> menu();

  Future<WaiterFloor> floor();

  /// The table's check, empty for a free table; null for no such table.
  Future<WaiterCheck?> check(int tableId);

  /// [staffId]'s open shift, or null.
  Future<WaiterShift?> openShift(int staffId);

  /// Open a shift for [staff] now, on [device]; return the open one instead
  /// if there already is one.
  Future<WaiterShift> startShift(WaiterStaff staff, WaiterDeviceRecord device);

  /// Close [staff]'s open shift now and return it; null when none is open.
  Future<WaiterShift?> finishShift(WaiterStaff staff, WaiterDeviceRecord device);

  /// Apply [ops] to the table's check, all or none, as [staff], and save it if
  /// the table is still at [expectedVersion] (null: the waiter saw it free).
  Future<WaiterApplyResult> apply({
    required int tableId,
    required int? expectedVersion,
    required List<WaiterOp> ops,
    required WaiterStaff staff,
    required WaiterDeviceRecord device,
  });
}
