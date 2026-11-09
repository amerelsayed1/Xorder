import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// What this handheld remembers between launches: which till, and the token
/// that till gave it. Nothing else — no PIN, no session, no money.
class Pairing {
  const Pairing({required this.address, required this.token, required this.tillName});

  final String address;
  final String token;
  final String tillName;

  Map<String, Object?> toJson() => {'address': address, 'token': token, 'till_name': tillName};

  static Pairing? fromJson(Object? json) {
    if (json is! Map) return null;
    final address = json['address'], token = json['token'];
    if (address is! String || token is! String || address.isEmpty || token.isEmpty) return null;
    final name = json['till_name'];
    return Pairing(address: address, token: token, tillName: name is String ? name : address);
  }
}

/// Where the pairing is kept.
///
/// A file in the app's private support folder. **Known gap (WA1):** not the OS
/// keystore yet — a rooted or jailbroken device could read the token. The
/// token only opens the PIN screen (every order still needs a waiter's PIN),
/// and the till revokes it in one tap; moving it to Keystore/Keychain needs a
/// new plugin and is listed in TECHNICAL as the next step.
abstract interface class PairingStore {
  Future<Pairing?> load();
  Future<void> save(Pairing pairing);
  Future<void> clear();
}

class FilePairingStore implements PairingStore {
  const FilePairingStore();

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/waiter_pairing.json');

  @override
  Future<Pairing?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return Pairing.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(Pairing pairing) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(pairing.toJson()), flush: true);
  }

  @override
  Future<void> clear() async {
    try {
      await (await _file()).delete();
    } on Object {
      // Nothing to forget.
    }
  }
}

final pairingStoreProvider = Provider<PairingStore>((_) => const FilePairingStore());

/// How a client is made for an address. Tests swap in a fake.
typedef ClientFactory = WaiterLinkClient Function(Uri baseUri, String? deviceToken);

final clientFactoryProvider = Provider<ClientFactory>(
  (_) => (uri, token) => WaiterLinkClient(baseUri: uri, deviceToken: token),
);

enum WaiterPhase {
  /// Reading the saved pairing.
  loading,

  /// Not paired with a till: show the pairing screen.
  unpaired,

  /// Paired, nobody signed in: show the PIN screen.
  signedOut,

  /// A waiter is signed in: the floor and checks.
  signedIn,
}

class WaiterAppState {
  const WaiterAppState({
    this.phase = WaiterPhase.loading,
    this.pairing,
    this.staff,
    this.locale = const Locale('ar'),
  });

  final WaiterPhase phase;
  final Pairing? pairing;
  final WaiterStaff? staff;
  final Locale locale;

  WaiterAppState copyWith({
    WaiterPhase? phase,
    Pairing? pairing,
    bool clearPairing = false,
    WaiterStaff? staff,
    bool clearStaff = false,
    Locale? locale,
  }) => WaiterAppState(
    phase: phase ?? this.phase,
    pairing: clearPairing ? null : (pairing ?? this.pairing),
    staff: clearStaff ? null : (staff ?? this.staff),
    locale: locale ?? this.locale,
  );
}

/// The handheld's one piece of app state: paired or not, who is signed in.
class WaiterApp extends Notifier<WaiterAppState> {
  WaiterLinkClient? _client;

  /// The client for the paired till. Only valid while paired.
  WaiterLinkClient get client => _client!;

  @override
  WaiterAppState build() {
    ref.onDispose(() => _client?.close());
    Future.microtask(_restore);
    return const WaiterAppState();
  }

  Future<void> _restore() async {
    final pairing = await ref.read(pairingStoreProvider).load();
    if (pairing == null) {
      state = state.copyWith(phase: WaiterPhase.unpaired);
      return;
    }
    _client = ref.read(clientFactoryProvider)(WaiterLinkClient.addressToUri(pairing.address), pairing.token);
    state = state.copyWith(phase: WaiterPhase.signedOut, pairing: pairing);
  }

  void toggleLanguage() => state = state.copyWith(
    locale: state.locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar'),
  );

  /// Pair with the till at [address] using the code it shows. Throws
  /// [WaiterLinkFailure] for the screen to word.
  Future<void> pair({required String address, required String code, required String deviceName}) async {
    final uri = WaiterLinkClient.addressToUri(address);
    final client = ref.read(clientFactoryProvider)(uri, null);
    try {
      final tillName = await client.hello();
      final token = await client.pair(code: code, deviceName: deviceName);
      final pairing = Pairing(
        address: '${uri.host}:${uri.port}',
        token: token,
        tillName: tillName.isEmpty ? uri.host : tillName,
      );
      await ref.read(pairingStoreProvider).save(pairing);
      _client?.close();
      _client = client;
      state = state.copyWith(phase: WaiterPhase.signedOut, pairing: pairing);
    } on Object {
      client.close();
      rethrow;
    }
  }

  Future<void> signIn(String pin) async {
    final session = await client.signIn(pin);
    state = state.copyWith(phase: WaiterPhase.signedIn, staff: session.staff);
  }

  Future<void> signOut() async {
    await _client?.signOut();
    state = state.copyWith(phase: WaiterPhase.signedOut, clearStaff: true);
  }

  Future<void> unpair() async {
    await _client?.signOut();
    _client?.close();
    _client = null;
    await ref.read(pairingStoreProvider).clear();
    state = state.copyWith(phase: WaiterPhase.unpaired, clearPairing: true, clearStaff: true);
  }

  /// What a failure means for where the app should be. Returns true when it
  /// moved the app (the screen should stop what it was doing).
  Future<bool> absorb(Object error) async {
    if (error is! WaiterLinkFailure) return false;
    switch (error.code) {
      case WaiterError.unpaired || WaiterError.revoked:
        _client?.close();
        _client = null;
        await ref.read(pairingStoreProvider).clear();
        state = state.copyWith(phase: WaiterPhase.unpaired, clearPairing: true, clearStaff: true);
        return true;
      case WaiterError.signInRequired:
        state = state.copyWith(phase: WaiterPhase.signedOut, clearStaff: true);
        return true;
    }
    return false;
  }
}

final waiterAppProvider = NotifierProvider<WaiterApp, WaiterAppState>(WaiterApp.new);

/// The menu, read once per sign-in (the till's catalog changes rarely; a
/// waiter who needs the newest pulls to refresh the floor and signs in again).
final menuProvider = FutureProvider<WaiterMenu>((ref) {
  ref.watch(waiterAppProvider.select((s) => s.staff?.id));
  return ref.read(waiterAppProvider.notifier).client.menu();
});
