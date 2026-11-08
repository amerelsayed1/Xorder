import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'secret_store.dart';

/// The till's secrets on macOS: generic-password items in the login keychain,
/// service `io.xorder.pos`, one account per key.
///
/// **Security.framework through `dart:ffi`, not the `security` command.** The
/// app runs under App Sandbox (`macos/Runner/*.entitlements`), and a child
/// process inherits the sandbox. How `/usr/bin/security` behaves against the
/// keychain from inside our sandbox is not documented, and its items would
/// trust `/usr/bin/security` rather than this app, so any process in the
/// session could read them back with one command and no prompt. The calls
/// below are the documented API a sandboxed app is given. They also keep the
/// secret out of every process's argv, which `add-generic-password -w <value>`
/// would not.
///
/// **The cost, carried over from the decision this reverses.** On 2026-09-04
/// the owner took secrets *out* of the keychain because each rebuild of an
/// ad-hoc-signed app looks to the keychain like a different app, and asks the
/// operator's login password ("XOrder POS wants to use your confidential
/// information"). That is still true of these items on an ad-hoc or unsigned
/// build. ADR-006 accepts the OS store anyway. A build signed with a stable
/// Developer ID keeps the same designated requirement from one version to the
/// next, and should not prompt after an update; that has not been
/// demonstrated on a real install yet.
///
/// Not the data-protection keychain (`kSecUseDataProtectionKeychain`): it
/// needs a keychain-access-groups entitlement that ad-hoc builds do not have,
/// and fails with errSecMissingEntitlement (-34018) where the legacy keychain
/// would only prompt.
class MacKeychainSecretStore implements SecretStore {
  MacKeychainSecretStore({KeychainBackend? backend})
    : _backend = backend ?? SecurityFrameworkKeychain();

  /// The keychain item's service. One per product, so a technician can find
  /// every item this till keeps under one name in Keychain Access.
  static const service = 'io.xorder.pos';

  final KeychainBackend _backend;

  /// Enough passes to clear duplicates that a crash between two calls could
  /// have left behind. A bound rather than "until empty", because a keychain
  /// that answers success without removing anything would otherwise spin the
  /// boot forever.
  static const _deletePasses = 64;

  @override
  bool get protectedByOperatingSystem => true;

  @override
  String get description => 'macOS Keychain';

  SecretStoreUnavailable _refused(String operation, Object cause) =>
      SecretStoreUnavailable(
        store: description,
        operation: operation,
        cause: cause,
      );

  /// Every native call here is synchronous. Wrapped so a throw from the FFI
  /// layer itself (a framework that will not load) becomes the typed refusal
  /// the callers already show, instead of a crash before the first frame.
  Future<T> _guard<T>(String operation, T Function() action) async {
    try {
      return action();
    } on SecretStoreUnavailable {
      rethrow;
    } on Object catch (error) {
      throw _refused(operation, error);
    }
  }

  @override
  Future<String?> read(String key) => _guard('read', () {
    final found = _backend.read(service, key);
    if (found.status == KeychainStatus.itemNotFound) return null;
    if (found.status != KeychainStatus.success) {
      throw _refused('read', KeychainStatus(found.status));
    }
    try {
      return utf8.decode(found.data ?? Uint8List(0));
    } on FormatException catch (error) {
      throw _refused('read', error);
    }
  });

  @override
  Future<void> write(String key, String value) => _guard('write', () {
    final data = Uint8List.fromList(utf8.encode(value));
    // Update first: the ordinary case, after the first save, is an item that
    // already exists, and add-then-update would fail on every save but one.
    var status = _backend.update(service, key, data);
    if (status == KeychainStatus.itemNotFound) {
      status = _backend.add(service, key, data);
      // Somebody added it between the two calls. Once more, as an update.
      if (status == KeychainStatus.duplicateItem) {
        status = _backend.update(service, key, data);
      }
    }
    if (status != KeychainStatus.success) {
      throw _refused('write', KeychainStatus(status));
    }
  });

  @override
  Future<void> delete(String key) =>
      _guard('delete', () => _deleteMatching(key));

  @override
  Future<void> deleteAll() => _guard('delete', () => _deleteMatching(null));

  /// [account] null deletes every item under [service].
  ///
  /// In a loop because macOS `SecItemDelete` has, on some releases, removed
  /// one matching item per call rather than every match.
  void _deleteMatching(String? account) {
    for (var pass = 0; pass < _deletePasses; pass++) {
      final status = _backend.delete(service, account);
      if (status == KeychainStatus.itemNotFound) return;
      if (status != KeychainStatus.success) {
        throw _refused('delete', KeychainStatus(status));
      }
    }
  }
}

/// An `OSStatus` from Security.framework, named where a technician would want
/// the name. Never carries item data.
class KeychainStatus {
  const KeychainStatus(this.code);

  final int code;

  static const success = 0;
  static const itemNotFound = -25300;
  static const duplicateItem = -25299;
  static const interactionNotAllowed = -25308;
  static const authFailed = -25293;
  static const userCanceled = -128;
  static const missingEntitlement = -34018;

  /// A non-data answer to a request for data. Our own code, not Apple's.
  static const unexpectedResult = -1;

  @override
  String toString() => switch (code) {
    interactionNotAllowed =>
      'the keychain is locked (errSecInteractionNotAllowed, $code)',
    authFailed => 'the keychain refused this app (errSecAuthFailed, $code)',
    userCanceled => 'the keychain prompt was cancelled (errSecUserCanceled)',
    missingEntitlement =>
      'this build lacks a keychain entitlement (errSecMissingEntitlement)',
    unexpectedResult => 'the keychain returned something that was not data',
    _ => 'keychain status $code',
  };
}

/// What a keychain lookup found: a status, and the item's bytes on success.
class KeychainRead {
  const KeychainRead(this.status, [this.data]);

  final int status;
  final Uint8List? data;
}

/// The four Security.framework calls, behind a seam.
///
/// The seam is what lets [MacKeychainSecretStore]'s handling of each status
/// be tested on Linux. The real one is [SecurityFrameworkKeychain], tested
/// only on macOS. Each returns an `OSStatus` rather than throwing, because
/// "not found" is an ordinary answer and the store decides what it means.
abstract interface class KeychainBackend {
  KeychainRead read(String service, String account);
  int add(String service, String account, Uint8List data);
  int update(String service, String account, Uint8List data);

  /// [account] null matches every item under [service].
  int delete(String service, String? account);
}

// --- Security.framework and CoreFoundation, by hand --------------------------
//
// Top-level finals are lazy in Dart, so nothing below is loaded until a macOS
// till first asks for a secret. On Windows and Linux this file is imported and
// never reached.

final _security = DynamicLibrary.open(
  '/System/Library/Frameworks/Security.framework/Security',
);
final _coreFoundation = DynamicLibrary.open(
  '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
);

/// `extern const CFStringRef kSecClass;` and the like: the symbol is the
/// address of a pointer, so it is read once through. These are owned by the
/// framework and are never released.
Pointer<Void> _constant(DynamicLibrary library, String name) =>
    library.lookup<Pointer<Void>>(name).value;

final _kSecClass = _constant(_security, 'kSecClass');
final _kSecClassGenericPassword = _constant(
  _security,
  'kSecClassGenericPassword',
);
final _kSecAttrService = _constant(_security, 'kSecAttrService');
final _kSecAttrAccount = _constant(_security, 'kSecAttrAccount');
final _kSecAttrLabel = _constant(_security, 'kSecAttrLabel');
final _kSecValueData = _constant(_security, 'kSecValueData');
final _kSecReturnData = _constant(_security, 'kSecReturnData');
final _kSecMatchLimit = _constant(_security, 'kSecMatchLimit');
final _kSecMatchLimitOne = _constant(_security, 'kSecMatchLimitOne');
final _kCFBooleanTrue = _constant(_coreFoundation, 'kCFBooleanTrue');

/// `kCFTypeDictionaryKeyCallBacks` is a struct, not a pointer to one, so its
/// own address is what `CFDictionaryCreate` wants.
final _keyCallBacks = _coreFoundation.lookup<Void>(
  'kCFTypeDictionaryKeyCallBacks',
);
final _valueCallBacks = _coreFoundation.lookup<Void>(
  'kCFTypeDictionaryValueCallBacks',
);

/// `kCFStringEncodingUTF8`.
const _utf8Encoding = 0x08000100;

final _cfRelease = _coreFoundation
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CFRelease',
    );

final _cfStringCreateWithCString = _coreFoundation
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
    >('CFStringCreateWithCString');

final _cfDataCreate = _coreFoundation
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Long),
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
    >('CFDataCreate');

final _cfDataGetBytePtr = _coreFoundation
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)
    >('CFDataGetBytePtr');

final _cfDataGetLength = _coreFoundation
    .lookupFunction<Long Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'CFDataGetLength',
    );

final _cfGetTypeID = _coreFoundation
    .lookupFunction<
      UnsignedLong Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('CFGetTypeID');

final _cfDataGetTypeID = _coreFoundation
    .lookupFunction<UnsignedLong Function(), int Function()>('CFDataGetTypeID');

final _cfDictionaryCreate = _coreFoundation
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        Long,
        Pointer<Void>,
        Pointer<Void>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CFDictionaryCreate');

final _secItemAdd = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('SecItemAdd');

final _secItemCopyMatching = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    >('SecItemCopyMatching');

final _secItemUpdate = _security
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)
    >('SecItemUpdate');

final _secItemDelete = _security
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'SecItemDelete',
    );

/// The real keychain.
///
/// **Ownership, the whole of it:** every CoreFoundation object created in a
/// call goes into that call's `owned` list the moment it exists, and the list
/// is released in the call's `finally`. A dictionary built with the CFType
/// callbacks retains its keys and values, so releasing ours after building it
/// is correct; the `kSec…` constants belong to the framework and are never in
/// the list. Native buffers come from `calloc` and go back in the same
/// `finally`, the one that held a secret zeroed first.
class SecurityFrameworkKeychain implements KeychainBackend {
  SecurityFrameworkKeychain();

  @override
  KeychainRead read(String service, String account) {
    final owned = <Pointer<Void>>[];
    final result = calloc<Pointer<Void>>();
    try {
      final query = _own(
        owned,
        _dictionary([
          (_kSecClass, _kSecClassGenericPassword),
          (_kSecAttrService, _own(owned, _string(service))),
          (_kSecAttrAccount, _own(owned, _string(account))),
          (_kSecReturnData, _kCFBooleanTrue),
          (_kSecMatchLimit, _kSecMatchLimitOne),
        ]),
      );
      final status = _secItemCopyMatching(query, result);
      if (status != KeychainStatus.success) return KeychainRead(status);

      // "Copy" in the name: the caller owns what came back.
      final data = result.value;
      if (data == nullptr) {
        return const KeychainRead(KeychainStatus.unexpectedResult);
      }
      owned.add(data);
      if (_cfGetTypeID(data) != _cfDataGetTypeID()) {
        return const KeychainRead(KeychainStatus.unexpectedResult);
      }
      final length = _cfDataGetLength(data);
      if (length == 0) return KeychainRead(status, Uint8List(0));
      final bytes = _cfDataGetBytePtr(data);
      return KeychainRead(
        status,
        Uint8List.fromList(bytes.asTypedList(length)),
      );
    } finally {
      _releaseAll(owned);
      calloc.free(result);
    }
  }

  @override
  int add(String service, String account, Uint8List data) {
    final owned = <Pointer<Void>>[];
    try {
      final attributes = _own(
        owned,
        _dictionary([
          (_kSecClass, _kSecClassGenericPassword),
          (_kSecAttrService, _own(owned, _string(service))),
          (_kSecAttrAccount, _own(owned, _string(account))),
          // What Keychain Access shows in its list, so a technician looking
          // for "the till's passwords" finds them by name.
          (_kSecAttrLabel, _own(owned, _string('XOrder POS — $account'))),
          (_kSecValueData, _own(owned, _data(data))),
        ]),
      );
      return _secItemAdd(attributes, nullptr);
    } finally {
      _releaseAll(owned);
    }
  }

  @override
  int update(String service, String account, Uint8List data) {
    final owned = <Pointer<Void>>[];
    try {
      final query = _own(
        owned,
        _dictionary([
          (_kSecClass, _kSecClassGenericPassword),
          (_kSecAttrService, _own(owned, _string(service))),
          (_kSecAttrAccount, _own(owned, _string(account))),
        ]),
      );
      final changes = _own(
        owned,
        _dictionary([(_kSecValueData, _own(owned, _data(data)))]),
      );
      return _secItemUpdate(query, changes);
    } finally {
      _releaseAll(owned);
    }
  }

  @override
  int delete(String service, String? account) {
    final owned = <Pointer<Void>>[];
    try {
      final query = _own(
        owned,
        _dictionary([
          (_kSecClass, _kSecClassGenericPassword),
          (_kSecAttrService, _own(owned, _string(service))),
          if (account != null)
            (_kSecAttrAccount, _own(owned, _string(account))),
        ]),
      );
      return _secItemDelete(query);
    } finally {
      _releaseAll(owned);
    }
  }

  static Pointer<Void> _own(List<Pointer<Void>> owned, Pointer<Void> object) {
    owned.add(object);
    return object;
  }

  static void _releaseAll(List<Pointer<Void>> owned) {
    for (final object in owned.reversed) {
      if (object != nullptr) _cfRelease(object);
    }
  }

  static Pointer<Void> _string(String value) {
    final native = value.toNativeUtf8(allocator: calloc);
    try {
      final string = _cfStringCreateWithCString(nullptr, native, _utf8Encoding);
      if (string == nullptr) throw StateError('CFStringCreateWithCString');
      return string;
    } finally {
      calloc.free(native);
    }
  }

  /// A CFData copy of [bytes]. CFDataCreate copies, so the native staging
  /// buffer — which holds the secret — is zeroed and freed before returning.
  static Pointer<Void> _data(Uint8List bytes) {
    final length = bytes.length;
    final native = calloc<Uint8>(length == 0 ? 1 : length);
    try {
      native.asTypedList(length).setAll(0, bytes);
      final data = _cfDataCreate(nullptr, native, length);
      if (data == nullptr) throw StateError('CFDataCreate');
      return data;
    } finally {
      native.asTypedList(length).fillRange(0, length, 0);
      calloc.free(native);
    }
  }

  static Pointer<Void> _dictionary(
    List<(Pointer<Void>, Pointer<Void>)> pairs,
  ) {
    final keys = calloc<Pointer<Void>>(pairs.length);
    final values = calloc<Pointer<Void>>(pairs.length);
    try {
      for (var i = 0; i < pairs.length; i++) {
        keys[i] = pairs[i].$1;
        values[i] = pairs[i].$2;
      }
      final dictionary = _cfDictionaryCreate(
        nullptr,
        keys,
        values,
        pairs.length,
        _keyCallBacks,
        _valueCallBacks,
      );
      if (dictionary == nullptr) throw StateError('CFDictionaryCreate');
      return dictionary;
    } finally {
      calloc.free(keys);
      calloc.free(values);
    }
  }
}
