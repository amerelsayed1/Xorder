import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../../app/providers.dart';
import '../../core/config/deployment.dart';
import '../../data/postgres/pos_database.dart';
import '../../data/postgres/postgres_parked_tickets.dart';
import '../../data/postgres/postgres_waiter_devices.dart';
import '../../domain/models/pos_settings.dart';
import '../../domain/models/shift.dart';
import 'till_waiter_backend.dart';

/// Whether this till can serve waiter handhelds, and what it is doing about it.
class WaiterLinkStatus {
  const WaiterLinkStatus({
    this.available = false,
    this.running = false,
    this.port = defaultWaiterPort,
    this.addresses = const [],
    this.pairing,
    this.devices = const [],
    this.error,
  });

  /// This till holds the tables (offline main device, or a cloud till) and
  /// has a database: it is the one handhelds should pair with.
  final bool available;
  final bool running;
  final int port;

  /// This machine's LAN addresses, for the handheld's "till address" field.
  final List<String> addresses;
  final PairingCode? pairing;
  final List<WaiterDevice> devices;

  /// Why the last start failed (port in use, ...), in the system's words.
  final String? error;

  WaiterLinkStatus copyWith({
    bool? available,
    bool? running,
    int? port,
    List<String>? addresses,
    PairingCode? pairing,
    bool clearPairing = false,
    List<WaiterDevice>? devices,
    String? error,
    bool clearError = false,
  }) => WaiterLinkStatus(
    available: available ?? this.available,
    running: running ?? this.running,
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    pairing: clearPairing ? null : (pairing ?? this.pairing),
    devices: devices ?? this.devices,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The waiter link server inside this till (waiter-app, WA1).
///
/// **Off unless a manager turns it on** (`waiter.link_enabled`, this terminal
/// only), and then on at every launch, watched from the app root like the
/// cloud sync loop: a till that restarts mid-service must not leave its
/// waiters standing with dead handhelds.
///
/// Only a till that holds the tables may serve: the offline app's main device
/// (a child till reads the same database, but its handhelds would be one more
/// hop from it and two tills serving one floor is two sets of pairing codes),
/// or a cloud till, which keeps its own tables.
class WaiterLinkHost extends Notifier<WaiterLinkStatus> {
  HttpServer? _http;
  WaiterLinkServer? _server;
  PostgresWaiterDevices? _devices;

  @override
  WaiterLinkStatus build() {
    ref.onDispose(_close);
    final available = _canHost();
    if (available) {
      // After the first frame's reads: the settings arrive asynchronously.
      Future.microtask(_autostart);
    }
    return WaiterLinkStatus(available: available);
  }

  bool _canHost() {
    final config = ref.read(deploymentProvider);
    return ref.read(deviceRoleProvider) == TerminalRole.main &&
        ref.read(posWriteContextProvider) != null &&
        PosDatabase.hostFor(config) != null;
  }

  Future<void> _autostart() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (settings.boolean(SettingKey.waiterLinkEnabled, orElse: false)) await start();
    } on Object {
      // A till that cannot read its settings serves no handhelds; it still sells.
    }
  }

  /// Turn the link on for this till, remembered across restarts.
  Future<void> enable(PosStaff by) async {
    await _remember(true, by);
    await start();
  }

  /// Turn it off. Paired devices stay paired; they reconnect when it is on.
  Future<void> disable(PosStaff by) async {
    await _remember(false, by);
    await _close();
    state = state.copyWith(running: false, clearPairing: true);
  }

  Future<void> _remember(bool on, PosStaff by) async {
    final context = ref.read(posWriteContextProvider);
    if (context == null) return;
    await ref.read(settingsRepositoryProvider).save(
      key: SettingKey.waiterLinkEnabled,
      value: on ? 'true' : 'false',
      scope: SettingScope.terminal,
      scopeId: context.terminalId,
      by: by,
    );
    ref.invalidate(settingsProvider);
  }

  Future<void> start() async {
    if (_http != null || !_canHost()) return;
    final config = ref.read(deploymentProvider);
    final context = ref.read(posWriteContextProvider)!;
    final database = ref.read(posDatabaseProvider);
    final devices = PostgresWaiterDevices(
      database: database,
      config: config,
      businessId: context.businessId,
      branchId: context.branchId,
    );
    final parked = PostgresParkedTickets(
      database: database,
      config: config,
      businessId: context.businessId,
      branchId: context.branchId,
    );
    final profile = ref.read(terminalProfileProvider);
    final backend = TillWaiterBackend(
      name: () async => [profile.terminalName, profile.branchName]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' — '),
      catalog: () => ref.read(catalogProvider.future),
      tables: () => ref.read(tablesRepositoryProvider).liveFloor(),
      taxConfig: () => ref.read(taxConfigProvider),
      signInWithPin: (pin) => ref.read(sessionRepositoryProvider).signIn(pin),
      checks: ParkedTicketsCheckStore(parked),
      devices: PostgresWaiterDeviceStore(devices),
      // The till's own floor catches up now, not at its next 5 s refresh.
      onSaved: () => unawaited(ref.read(openTicketsProvider.notifier).refresh()),
    );
    try {
      final http = await HttpServer.bind(InternetAddress.anyIPv4, ref.read(waiterLinkPortProvider));
      final server = WaiterLinkServer(backend: backend);
      server.attach(http);
      _http = http;
      _server = server;
      _devices = devices;
      state = state.copyWith(
        running: true,
        port: http.port,
        addresses: await _lanAddresses(),
        devices: await devices.all(),
        clearError: true,
      );
    } on Object catch (e) {
      state = state.copyWith(running: false, error: '$e');
    }
  }

  /// Show a fresh pairing code for ten minutes.
  void openPairing() {
    final server = _server;
    if (server == null) return;
    state = state.copyWith(pairing: server.openPairing());
  }

  void closePairing() {
    _server?.closePairing();
    state = state.copyWith(clearPairing: true);
  }

  Future<void> refreshDevices() async {
    final devices = _devices;
    if (devices == null) return;
    // The code is used once; a device that just paired has consumed it.
    final pairing = _server?.currentPairing;
    state = state.copyWith(
      devices: await devices.all(),
      pairing: pairing,
      clearPairing: pairing == null,
    );
  }

  Future<void> revoke(int deviceId) async {
    final devices = _devices;
    if (devices == null) return;
    await devices.revoke(deviceId);
    _server?.forgetDevice(deviceId);
    state = state.copyWith(devices: await devices.all());
  }

  Future<void> _close() async {
    final http = _http;
    _http = null;
    _server = null;
    _devices = null;
    await http?.close(force: true);
  }

  static Future<List<String>> _lanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
    } on Object {
      return const [];
    }
  }
}

/// The port the link listens on. Fixed, so a handheld's saved address keeps
/// working across restarts; tests bind 0 (any free port).
final waiterLinkPortProvider = Provider<int>((_) => defaultWaiterPort);

final waiterLinkHostProvider = NotifierProvider<WaiterLinkHost, WaiterLinkStatus>(
  WaiterLinkHost.new,
);
