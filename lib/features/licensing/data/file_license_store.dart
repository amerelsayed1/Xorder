import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/license_verifier.dart';
import 'license_store.dart';

/// The installed licence, on disk.
///
/// A file rather than a preference because it has to survive an app update, and
/// not in the keychain because a licence is not a secret: it is signed,
/// publicly verifiable, and says nothing an operator could not read off the
/// licence screen.
///
/// A damaged or truncated file reads as **no licence**, not as a crash. The
/// operator's route out is the same either way — reinstall the `.xlic` — and a
/// till that will not boot because a file got half-written is a support call
/// that did not need to happen.
class FileLicenseStore implements LicenseStore {
  FileLicenseStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'licence.xlic';

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  @override
  Future<LicenseFile?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      return LicenseFile.tryParse(await file.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  /// Written to a temporary file and renamed into place.
  ///
  /// A rename is atomic on both platforms the till runs on, so a power cut
  /// during activation leaves either the old licence or the new one — never
  /// half of one. Losing power mid-activation is exactly the sort of thing that
  /// happens in a restaurant.
  @override
  Future<void> write(LicenseFile file) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(file.serialize(), flush: true);
    await temporary.rename(target.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}

/// A stable, non-identifying fingerprint for this machine.
///
/// Derived from the terminal id — generated once on this device at setup and
/// never reissued — rather than from anything about the person using it. Hashed
/// so that what leaves the device is opaque: the licence issuer has no business
/// knowing a machine's name, serial or user.
///
/// Reinstalling the app keeps the terminal id and therefore the fingerprint. A
/// different machine gets a different one, which is what pinning a licence to a
/// terminal is for.
class TerminalIdFingerprint implements TerminalFingerprint {
  const TerminalIdFingerprint(this._terminalId);

  final String? _terminalId;

  @override
  Future<String> value() async {
    final id = _terminalId;
    if (id == null || id.isEmpty) return '';

    // Salted with a constant so the fingerprint cannot be recomputed from a
    // terminal id alone by anyone who happens to see one in a database.
    return sha256.convert(utf8.encode('xorder-pos-terminal:$id')).toString();
  }
}
