import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_secret_store.dart';
import 'secret_store.dart';

/// Moves an older build's `secrets.json` into the operating system's store,
/// once, and leaves no plaintext behind.
///
/// **All or nothing, in this order:** read the file; note what the OS store
/// already holds under each key; write every value; read every value back and
/// compare; only then zero the file and delete it. If anything before the wipe
/// fails, the keys this run touched are put back as they were and the file is
/// left exactly as found, so the next launch tries again from the same
/// starting point. The alternative, deleting each entry from the file as it
/// lands, would leave a crash halfway through with secrets split between two
/// places and neither one complete.
///
/// **The file wins a conflict.** If the OS store already holds a different
/// value for a key, the file's value is written over it. Only a build without
/// the OS store writes `secrets.json`, and this build deletes it, so a file
/// that is present is newer than anything the OS store holds — the usual way
/// there is a downgrade to an older build and then an upgrade again.
///
/// **Idempotent.** Once the file is gone there is nothing to do. A crash after
/// the values are verified but before the wipe finishes only means the next
/// launch writes the same values again and wipes again.
class LegacySecretMigration {
  LegacySecretMigration({
    required this.target,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final SecretStore target;
  final Future<Directory> Function() _directory;

  Future<LegacySecretMigrationResult> run() async {
    // The development store *is* secrets.json. "Migrating" it into itself
    // would end with the wipe deleting the only copy.
    if (!target.protectedByOperatingSystem) {
      return const LegacySecretsNotApplicable();
    }

    final File file;
    final File temporary;
    try {
      final directory = await _directory();
      file = File(p.join(directory.path, FileSecretStore.fileName));
      // FileSecretStore's write went through `secrets.json.tmp`. A crash
      // between its write and its rename left the full plaintext there.
      temporary = File('${file.path}.tmp');
      if (!file.existsSync()) {
        if (temporary.existsSync()) await _wipe(temporary);
        return const NoLegacySecrets();
      }
    } on Object catch (error) {
      return LegacySecretsUnreadable(error);
    }

    final Map<String, String> legacy;
    try {
      final bytes = await file.readAsBytes();
      // A file that is all zeros is this migration's own wipe, interrupted
      // between the overwrite and the delete; its secrets were verified in
      // the OS store before the overwrite began. An empty one is
      // FileSecretStore's, interrupted between creating its file and filling
      // it. Neither holds anything, and leaving either would fail as
      // "unreadable" on every launch from now on.
      if (bytes.every((byte) => byte == 0)) {
        await file.delete();
        return const NoLegacySecrets();
      }
      legacy = _parse(utf8.decode(bytes));
    } on Object catch (error) {
      // Damaged, or unreadable for some reason of its own. Left exactly where
      // it is: it may still be the only copy of a password somebody needs, and
      // a technician can open it. The OS store is not at fault, so this does
      // not mark it unavailable.
      return LegacySecretsUnreadable(_withoutContents(error));
    }

    final before = <String, String?>{};
    try {
      for (final key in legacy.keys) {
        before[key] = await target.read(key);
      }
    } on Object catch (error) {
      // Nothing written yet, so there is nothing to put back.
      return LegacySecretsNotMigrated(
        _asRefusal(error, 'read'),
        restoredAfterwards: true,
      );
    }

    final touched = <String>[];
    try {
      for (final MapEntry(:key, :value) in legacy.entries) {
        touched.add(key);
        await target.write(key, value);
      }
      for (final MapEntry(:key, :value) in legacy.entries) {
        final stored = await target.read(key);
        if (stored != value) {
          throw SecretStoreUnavailable(
            store: target.description,
            operation: 'verify',
            // The key, never the value: this lands in a log.
            cause: 'the value read back for $key was not the one written',
          );
        }
      }
    } on Object catch (error) {
      final restored = await _restore(touched, before);
      return LegacySecretsNotMigrated(
        _asRefusal(error, 'write'),
        restoredAfterwards: restored,
      );
    }

    try {
      await _wipe(file);
      if (temporary.existsSync()) await _wipe(temporary);
    } on Object catch (error) {
      // The secrets are safely in the OS store; the plaintext is not yet gone.
      // Not rolled back: undoing a verified copy to keep a file we meant to
      // delete would be the wrong way round. The next launch tries the wipe
      // again.
      return LegacySecretsNotWiped(legacy.keys.toList(), error);
    }
    return LegacySecretsMigrated(legacy.keys.toList());
  }

  /// Every failure as the typed refusal, so `main()` has one thing to report.
  /// `on Object` above, not only [SecretStoreUnavailable]: this runs before the
  /// first frame, and anything that escaped it would be a blank window rather
  /// than a till that opens and says what is wrong.
  SecretStoreUnavailable _asRefusal(Object error, String operation) =>
      error is SecretStoreUnavailable
      ? error
      : SecretStoreUnavailable(
          store: target.description,
          operation: operation,
          cause: error,
        );

  /// [error] without the text it was raised over.
  ///
  /// `jsonDecode` and `utf8.decode` throw a `FormatException` whose `source`
  /// is the whole of what they were reading — here, every password in the
  /// file — and whose `toString` prints a line of it. The result outlives this
  /// method (`main()` reports it), so the copy is dropped here rather than
  /// trusting every reader to remember not to print it. The message and the
  /// offset are the parser's own words and a number; they stay.
  static Object _withoutContents(Object error) => error is FormatException
      ? FormatException(error.message, null, error.offset)
      : error;

  /// Put each key this run wrote back to what it was. True if all went back.
  Future<bool> _restore(
    List<String> touched,
    Map<String, String?> before,
  ) async {
    var clean = true;
    for (final key in touched.reversed) {
      try {
        final previous = before[key];
        if (previous == null) {
          await target.delete(key);
        } else {
          await target.write(key, previous);
        }
      } on Object {
        clean = false;
      }
    }
    return clean;
  }

  /// Exactly the entries `FileSecretStore.read` would have answered with: a
  /// non-empty string under a string key. Anything else in the file was never
  /// a secret a consumer could read, and is deleted with the file.
  static Map<String, String> _parse(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException('secrets.json is not a JSON object');
    }
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String && value is String && value.isNotEmpty) key: value,
    };
  }

  /// Overwrite with zeros, flush, then delete.
  ///
  /// The overwrite is what keeps the plaintext from lingering in the freed
  /// blocks of a spinning disk. It is no promise on an SSD, whose controller
  /// writes the zeros somewhere new; there, deleting is what we can do, and
  /// the drive's own encryption, where it has any, is what protects the rest.
  static Future<void> _wipe(File file) async {
    final length = await file.length();
    final handle = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      // Opened without truncating, which would hand the old blocks back
      // before the zeros reached them; positioned at the start by hand.
      await handle.setPosition(0);
      await handle.writeFrom(Uint8List(length));
      await handle.flush();
    } finally {
      await handle.close();
    }
    await file.delete();
  }
}

/// What the migration did, for `main()` to act on and log.
sealed class LegacySecretMigrationResult {
  const LegacySecretMigrationResult();

  /// Whether the OS store itself refused. The setup wizard warns about that
  /// (`keystoreUnavailable`); a damaged legacy file is not the store's fault
  /// and must not raise the same warning.
  bool get storeRefused => false;
}

/// The development store: there is no OS store to migrate into.
class LegacySecretsNotApplicable extends LegacySecretMigrationResult {
  const LegacySecretsNotApplicable();
}

/// No `secrets.json`: a new install, or one already migrated.
class NoLegacySecrets extends LegacySecretMigrationResult {
  const NoLegacySecrets();
}

/// Every value now in the OS store, verified, and the file wiped.
class LegacySecretsMigrated extends LegacySecretMigrationResult {
  const LegacySecretsMigrated(this.keys);

  final List<String> keys;
}

/// Every value in the OS store and verified, but the file could not be wiped.
/// The next launch tries again.
class LegacySecretsNotWiped extends LegacySecretMigrationResult {
  const LegacySecretsNotWiped(this.keys, this.cause);

  final List<String> keys;
  final Object cause;
}

/// `secrets.json` is there but could not be read or parsed. Left untouched.
class LegacySecretsUnreadable extends LegacySecretMigrationResult {
  const LegacySecretsUnreadable(this.cause);

  /// Never the file's contents — see `LegacySecretMigration._withoutContents`.
  final Object cause;

  @override
  String toString() =>
      'LegacySecretsUnreadable(${SecretStoreUnavailable.describe(cause)})';
}

/// The OS store refused part way. The file is untouched; the keys this run
/// wrote were put back as they were, unless [restoredAfterwards] is false, in
/// which case the store refused that too and may hold some of the file's
/// values. Either way the file is still complete, and is what the next launch
/// migrates from.
class LegacySecretsNotMigrated extends LegacySecretMigrationResult {
  const LegacySecretsNotMigrated(
    this.cause, {
    required this.restoredAfterwards,
  });

  final SecretStoreUnavailable cause;
  final bool restoredAfterwards;

  @override
  bool get storeRefused => true;
}
