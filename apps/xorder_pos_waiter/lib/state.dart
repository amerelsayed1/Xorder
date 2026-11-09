import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import 'mode.dart';

/// What this handheld remembers between launches: where it signs in (the
/// till's address, or the restaurant's slug), the last name signed in, and
/// the device token the server gave it on its first sign-in. Never a PIN,
/// never a session.
class SavedConnection {
  const SavedConnection({required this.target, this.username = '', this.deviceToken, this.serverName = ''});

  /// `192.168.1.20:8787` in the offline flavor, `demo` in the cloud flavor.
  final String target;
  final String username;
  final String? deviceToken;

  /// What the server calls itself ("Main till — Maadi"), for the sign-in screen.
  final String serverName;

  SavedConnection copyWith({String? target, String? username, String? deviceToken, bool clearToken = false, String? serverName}) =>
      SavedConnection(
        target: target ?? this.target,
        username: username ?? this.username,
        deviceToken: clearToken ? null : (deviceToken ?? this.deviceToken),
        serverName: serverName ?? this.serverName,
      );

  Map<String, Object?> toJson() => {
    'target': target,
    'username': username,
    'device_token': ?deviceToken,
    'server_name': serverName,
  };

  static SavedConnection? fromJson(Object? json) {
    if (json is! Map) return null;
    final target = json['target'];
    if (target is! String || target.isEmpty) return null;
    final username = json['username'], token = json['device_token'], name = json['server_name'];
    return SavedConnection(
      target: target,
      username: username is String ? username : '',
      deviceToken: token is String && token.isNotEmpty ? token : null,
      serverName: name is String ? name : '',
    );
  }
}

/// Where the connection is kept.
///
/// A file in the app's private support folder. **Known gap (WA1):** not the OS
/// keystore yet — a rooted or jailbroken device could read the token. The
/// token only identifies the device (every order still needs a waiter's name
/// and PIN), and the till revokes it in one tap; moving it to
/// Keystore/Keychain needs a new plugin and is listed in TECHNICAL as the
/// next step.
abstract interface class ConnectionStore {
  Future<SavedConnection?> load();
  Future<void> save(SavedConnection connection);
  Future<void> clear();
}

class FileConnectionStore implements ConnectionStore {
  const FileConnectionStore();

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/waiter_connection.json');

  @override
  Future<SavedConnection?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return SavedConnection.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(SavedConnection connection) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(connection.toJson()), flush: true);
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

final connectionStoreProvider = Provider<ConnectionStore>((_) => const FileConnectionStore());

/// How a client is made for a target in this mode. Tests swap in a fake.
typedef ClientFactory = WaiterClient Function(WaiterMode mode, String target, String? deviceToken);

/// The real one: the LAN link to a till, or the same wire served by the
/// platform at the restaurant's subdomain (POS-BE-033).
WaiterClient defaultClientFactory(WaiterMode mode, String target, String? deviceToken) => switch (mode) {
  WaiterMode.offline => WaiterLinkClient(baseUri: WaiterLinkClient.addressToUri(target), deviceToken: deviceToken),
  WaiterMode.cloud => WaiterLinkClient(
    baseUri: Uri.https('${target.trim().toLowerCase()}.$cloudDomain', '/api/pos/waiter'),
    deviceToken: deviceToken,
  ),
};

final clientFactoryProvider = Provider<ClientFactory>((_) => defaultClientFactory);

/// How this handheld names itself to the server on its first sign-in.
String defaultDeviceName(String username) {
  final kind = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android' : Platform.operatingSystem);
  return '$username · $kind';
}

enum WaiterPhase {
  /// Reading the saved connection.
  loading,

  /// Nobody signed in: the sign-in screen, prefilled with what is remembered.
  signedOut,

  /// A waiter is signed in: the floor and checks.
  signedIn,
}

class WaiterAppState {
  const WaiterAppState({
    this.phase = WaiterPhase.loading,
    this.connection,
    this.staff,
    this.locale = const Locale('ar'),
  });

  final WaiterPhase phase;
  final SavedConnection? connection;
  final WaiterStaff? staff;
  final Locale locale;

  WaiterAppState copyWith({
    WaiterPhase? phase,
    SavedConnection? connection,
    bool clearConnection = false,
    WaiterStaff? staff,
    bool clearStaff = false,
    Locale? locale,
  }) => WaiterAppState(
    phase: phase ?? this.phase,
    connection: clearConnection ? null : (connection ?? this.connection),
    staff: clearStaff ? null : (staff ?? this.staff),
    locale: locale ?? this.locale,
  );
}

/// The handheld's one piece of app state: where it signs in, who is signed in.
class WaiterApp extends Notifier<WaiterAppState> {
  WaiterClient? _client;
  String? _clientTarget;

  /// The client for the signed-in server. Only valid while signed in.
  WaiterClient get client => _client!;

  @override
  WaiterAppState build() {
    ref.onDispose(() => _client?.close());
    Future.microtask(_restore);
    return const WaiterAppState();
  }

  Future<void> _restore() async {
    final saved = await ref.read(connectionStoreProvider).load();
    state = state.copyWith(phase: WaiterPhase.signedOut, connection: saved);
  }

  void toggleLanguage() => state = state.copyWith(
    locale: state.locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar'),
  );

  /// Sign in at [target] as [username] with [pin]. The first sign-in from
  /// this phone registers it there; the token that comes back is kept so the
  /// next sign-in is the same device. Throws [WaiterLinkFailure] for the
  /// screen to word.
  Future<void> signIn({required String target, required String username, required String pin}) async {
    final mode = ref.read(waiterModeProvider);
    final cleanTarget = target.trim();
    final saved = state.connection;
    final sameTarget = saved != null && saved.target == cleanTarget;
    final token = sameTarget ? saved.deviceToken : null;

    if (_client == null || _clientTarget != cleanTarget) {
      _client?.close();
      _client = ref.read(clientFactoryProvider)(mode, cleanTarget, token);
      _clientTarget = cleanTarget;
    }
    final client = _client!;
    client.deviceToken = token;

    final serverName = sameTarget && saved.serverName.isNotEmpty ? saved.serverName : await client.hello();
    final session = await client.signIn(username: username.trim(), pin: pin, deviceName: defaultDeviceName(username.trim()));

    final connection = SavedConnection(
      target: cleanTarget,
      username: username.trim(),
      deviceToken: client.deviceToken,
      serverName: serverName,
    );
    await ref.read(connectionStoreProvider).save(connection);
    state = state.copyWith(phase: WaiterPhase.signedIn, connection: connection, staff: session.staff);
  }

  Future<void> signOut() async {
    await _client?.signOut();
    state = state.copyWith(phase: WaiterPhase.signedOut, clearStaff: true);
  }

  /// Forget where this phone signs in (and its device token there).
  Future<void> forget() async {
    await _client?.signOut();
    _client?.close();
    _client = null;
    _clientTarget = null;
    await ref.read(connectionStoreProvider).clear();
    state = state.copyWith(phase: WaiterPhase.signedOut, clearConnection: true, clearStaff: true);
  }

  /// What a failure means for where the app should be. Returns true when it
  /// moved the app (the screen should stop what it was doing).
  Future<bool> absorb(Object error) async {
    if (error is! WaiterLinkFailure) return false;
    switch (error.code) {
      case WaiterError.unpaired || WaiterError.revoked:
        // The server no longer knows this device: the next sign-in registers
        // it afresh. Target and name are kept; only the token is dropped.
        _client?.deviceToken = null;
        final saved = state.connection?.copyWith(clearToken: true);
        if (saved != null) await ref.read(connectionStoreProvider).save(saved);
        state = state.copyWith(phase: WaiterPhase.signedOut, connection: saved, clearStaff: true);
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
