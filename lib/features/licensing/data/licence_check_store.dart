import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/online_verdict.dart';

/// Where the till keeps its last online licence verdict (POS-BE-031).
///
/// **Its own file, beside `config.json` and `licence.xlic`,** for the reason
/// `docs/pos/10-setup-architecture.md` §6 gives `bootstrap.json` one: a server
/// answer refreshed on its own cadence must never rewrite the file that gates
/// boot, and a corrupt cache must read as "nothing cached", never as a till
/// that cannot start. The agreed contract names `bootstrap.json`; that bundle
/// cache is not built yet, so the verdict lives in this narrower file until it
/// is, and moves there with it.
abstract interface class LicenceCheckStore {
  Future<LicenceCheckRecord?> read();
  Future<void> write(LicenceCheckRecord record);

  /// Forget the cached verdict (hard reset). A missing file is not an error.
  Future<void> clear();
}

class FileLicenceCheckStore implements LicenceCheckStore {
  FileLicenceCheckStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'licence_check.json';

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  /// Every IO and parse failure is null — see the class comment.
  @override
  Future<LicenceCheckRecord?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map ? LicenceCheckRecord.tryParse(json.cast()) : null;
    } on Object {
      return null;
    }
  }

  /// Atomic: `.tmp` then rename, as the licence and config files are written.
  @override
  Future<void> write(LicenceCheckRecord record) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    await temporary.rename(target.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

class InMemoryLicenceCheckStore implements LicenceCheckStore {
  InMemoryLicenceCheckStore([this._record]);

  LicenceCheckRecord? _record;

  @override
  Future<LicenceCheckRecord?> read() async => _record;

  @override
  Future<void> write(LicenceCheckRecord record) async => _record = record;

  @override
  Future<void> clear() async => _record = null;
}
