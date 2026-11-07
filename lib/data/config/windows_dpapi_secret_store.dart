import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'secret_store.dart';

/// The till's secrets on Windows: each one sealed with DPAPI, the ciphertext
/// kept in `secrets.dpapi` beside `config.json`.
///
/// **What DPAPI buys, stated rather than implied.** `CryptProtectData` in
/// current-user scope seals each value with a key derived from this Windows
/// account's logon credential. The file copied to a USB stick, attached to a
/// support email or restored onto another machine is noise; the same file read
/// by a process running *as this user, on this machine* decrypts — DPAPI cannot
/// tell the till from anything else in its session. That is the line ADR-006
/// draws, and the one `secrets.json` (plaintext, no ACL at all on Windows)
/// never had.
///
/// **Why a file of ciphertext and not Credential Manager.** `CredWrite` caps a
/// generic credential at 2,560 bytes, roams it with the profile under policy
/// nobody at a business controls, and shows every entry in a control-panel
/// list a cashier can delete by mistake. A DPAPI blob in Application Support
/// has none of those properties and is wiped by the same hard reset as every
/// other file the till keeps.
///
/// One blob per key, not one blob for all: a damaged entry costs that secret
/// only, and the key name is bound into each blob's entropy, so a blob copied
/// from one entry to another fails to open instead of answering as the wrong
/// password.
class WindowsDpapiSecretStore implements SecretStore {
  WindowsDpapiSecretStore({
    Future<Directory> Function()? directory,
    DpapiCipher? cipher,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _cipher = cipher ?? const Win32DpapiCipher();

  static const fileName = 'secrets.dpapi';

  /// Written into the file so a later build can change the layout and still
  /// recognise this one, instead of reading it as damage.
  static const format = 'xorder-pos-dpapi-1';

  final Future<Directory> Function() _directory;
  final DpapiCipher _cipher;

  /// Every read-modify-write of the file, one at a time. Two consumers saving
  /// at once (the wizard's database password and its admin password) would
  /// otherwise each read the same map and the second rename would drop the
  /// first one's entry.
  Future<void> _tail = Future.value();

  @override
  bool get protectedByOperatingSystem => true;

  @override
  String get description => 'Windows DPAPI';

  /// One at a time, and every failure typed. `on Object` because the folder
  /// comes from `path_provider`, whose failures are not file-system errors,
  /// and an untyped one escaping `main()`'s first read is a blank window.
  Future<T> _serial<T>(String operation, Future<T> Function() action) {
    Future<T> guarded() async {
      try {
        return await action();
      } on SecretStoreUnavailable {
        rethrow;
      } on Object catch (error) {
        throw _refused(operation, error);
      }
    }

    final result = _tail.then((_) => guarded());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  SecretStoreUnavailable _refused(String operation, Object cause) =>
      SecretStoreUnavailable(
        store: description,
        operation: operation,
        cause: cause,
      );

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  /// The entry key's entropy: an app-wide constant plus the key's own name.
  ///
  /// The constant is in this binary, so it is not a secret and is not meant to
  /// be one. What it does is make `CryptUnprotectData` with *no* entropy — the
  /// one call every DPAPI-dumping tool tries first — fail on these blobs.
  static Uint8List entropyFor(String key) =>
      Uint8List.fromList(utf8.encode('io.xorder.pos/secret-store/v1/$key'));

  /// The file's entries, or an empty map when there is no file.
  ///
  /// A file that is there but cannot be parsed **throws**: it held every
  /// secret this till has, and answering "empty" would send the operator back
  /// through the wizard with no clue why. `FileSecretStore` made that bargain;
  /// the discovery review (SECURITY_AND_RECOVERY §3) named it as a defect.
  Future<Map<String, String>> _entries(String operation) async {
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      return _parse(await file.readAsString());
    } on FileSystemException catch (error) {
      throw _refused(operation, error);
    } on FormatException catch (error) {
      throw _refused(operation, error);
    }
  }

  static Map<String, String> _parse(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map || decoded['format'] != format) {
      throw const FormatException('secrets.dpapi is not in a known format');
    }
    final entries = decoded['entries'];
    if (entries is! Map) {
      throw const FormatException('secrets.dpapi has no entries');
    }
    return {
      for (final MapEntry(:key, :value) in entries.entries)
        if (key is String && value is String) key: value,
    };
  }

  Future<void> _save(Map<String, String> entries) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'format': format, 'entries': entries}),
      flush: true,
    );
    // Rename replaces on Windows (`MoveFileEx` with REPLACE_EXISTING), so a
    // crash leaves the old file or the new one, never half of either.
    await temporary.rename(target.path);
  }

  /// The entries to write over, setting a damaged file aside first.
  ///
  /// Ciphertext only, so nothing readable is left lying about — and kept
  /// rather than deleted, so a technician can still see that there was
  /// damage. Without this a damaged file is a till that can never save again:
  /// every write would refuse, forever, and only a hard reset would mend it.
  Future<Map<String, String>> _entriesForWrite(String operation) async {
    try {
      return await _entries(operation);
    } on SecretStoreUnavailable catch (error) {
      if (error.cause is! FormatException) rethrow;
      try {
        final file = await _file();
        final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
        await file.rename('${file.path}.damaged-$stamp');
      } on FileSystemException catch (moved) {
        throw _refused(operation, moved);
      }
      return {};
    }
  }

  @override
  Future<String?> read(String key) => _serial('read', () async {
    final sealed = (await _entries('read'))[key];
    if (sealed == null) return null;
    try {
      final plain = _cipher.unprotect(base64Decode(sealed), entropyFor(key));
      return utf8.decode(plain);
    } on FormatException catch (error) {
      throw _refused('read', error);
    } on DpapiFailure catch (error) {
      // Typically ERROR_INVALID_DATA (13): the blob was sealed by another
      // Windows account, or on another machine, or its profile's master key
      // was reset by an administrator changing the password from outside.
      throw _refused('read', error);
    }
  });

  @override
  Future<void> write(String key, String value) => _serial('write', () async {
    final String sealed;
    try {
      sealed = base64Encode(
        _cipher.protect(
          Uint8List.fromList(utf8.encode(value)),
          entropyFor(key),
        ),
      );
    } on DpapiFailure catch (error) {
      throw _refused('write', error);
    }
    final entries = await _entriesForWrite('write');
    entries[key] = sealed;
    try {
      await _save(entries);
    } on FileSystemException catch (error) {
      throw _refused('write', error);
    }
  });

  @override
  Future<void> delete(String key) => _serial('delete', () async {
    final entries = await _entriesForWrite('delete');
    if (entries.remove(key) == null) return;
    try {
      await _save(entries);
    } on FileSystemException catch (error) {
      throw _refused('delete', error);
    }
  });

  @override
  Future<void> deleteAll() => _serial('delete', () async {
    try {
      final file = await _file();
      for (final leftover in [file, File('${file.path}.tmp')]) {
        if (leftover.existsSync()) await leftover.delete();
      }
    } on FileSystemException catch (error) {
      throw _refused('delete', error);
    }
  });
}

/// DPAPI's two calls, behind a seam.
///
/// The seam is what lets the store's file handling — format, damage, the
/// per-key entropy, the serialised writes — be tested on the Linux machine the
/// suite runs on, with a stand-in cipher. The real one is [Win32DpapiCipher],
/// tested only on Windows.
abstract interface class DpapiCipher {
  Uint8List protect(Uint8List plain, Uint8List entropy);
  Uint8List unprotect(Uint8List sealed, Uint8List entropy);
}

/// DPAPI refused. Carries the Win32 error code, never the data.
class DpapiFailure implements Exception {
  const DpapiFailure(this.call, this.code);

  final String call;
  final int code;

  @override
  String toString() => '$call failed (Win32 error $code)';
}

/// `CRYPTPROTECT_UI_FORBIDDEN` (dpapi.h). Not exported by `win32` 6.4.
///
/// Set on every call: a till must never stop at boot on a DPAPI dialog that a
/// cashier cannot answer. Without it, a profile whose master key needs
/// re-entering would raise one; with it, the call fails and the wizard says so.
const _cryptProtectUiForbidden = 0x1;

/// `CryptProtectData` / `CryptUnprotectData` in current-user scope — no
/// `CRYPTPROTECT_LOCAL_MACHINE`, which would let every account on the machine
/// open the blob.
///
/// Synchronous calls behind a synchronous face, like `winspool.dart`: a seal
/// of a password-sized value is microseconds. Every native buffer is freed in
/// a `finally`; the ones DPAPI allocated go back with `LocalFree`, as its
/// documentation requires, and every buffer that held plaintext is zeroed
/// before it is released.
class Win32DpapiCipher implements DpapiCipher {
  const Win32DpapiCipher();

  @override
  Uint8List protect(Uint8List plain, Uint8List entropy) =>
      _transform(plain, entropy, seal: true);

  @override
  Uint8List unprotect(Uint8List sealed, Uint8List entropy) =>
      _transform(sealed, entropy, seal: false);

  static Uint8List _transform(
    Uint8List data,
    Uint8List entropy, {
    required bool seal,
  }) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final salt = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    // calloc of zero bytes is not a buffer; an empty value still needs one.
    final inputBytes = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final saltBytes = calloc<Uint8>(entropy.isEmpty ? 1 : entropy.length);
    final description = 'XOrder POS'.toNativeUtf16();
    try {
      inputBytes.asTypedList(data.length).setAll(0, data);
      saltBytes.asTypedList(entropy.length).setAll(0, entropy);
      input.ref
        ..cbData = data.length
        ..pbData = inputBytes;
      salt.ref
        ..cbData = entropy.length
        ..pbData = saltBytes;

      final result = seal
          ? CryptProtectData(
              input,
              PCWSTR(description),
              salt,
              null,
              _cryptProtectUiForbidden,
              output,
            )
          : CryptUnprotectData(
              input,
              null,
              salt,
              null,
              _cryptProtectUiForbidden,
              output,
            );
      if (!result.value) {
        throw DpapiFailure(
          seal ? 'CryptProtectData' : 'CryptUnprotectData',
          result.error,
        );
      }
      final length = output.ref.cbData;
      return Uint8List.fromList(output.ref.pbData.asTypedList(length));
    } finally {
      final produced = output.ref.pbData;
      if (produced != nullptr) {
        // On unprotect this is the plaintext. Zeroed before it goes back,
        // because LocalFree returns it to a heap the next allocation reads.
        if (!seal) _zero(produced, output.ref.cbData);
        LocalFree(HLOCAL(produced));
      }
      // On protect the input is the plaintext, for the same reason.
      if (seal) _zero(inputBytes, data.length);
      calloc.free(inputBytes);
      calloc.free(saltBytes);
      calloc.free(description);
      calloc.free(input);
      calloc.free(salt);
      calloc.free(output);
    }
  }

  static void _zero(Pointer<Uint8> buffer, int length) =>
      buffer.asTypedList(length).fillRange(0, length, 0);
}
