import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/terminal_config.dart';

/// Where a finished setup is kept between launches.
///
/// Behind an interface for the same reason [PosDbCredentials] is: a widget test
/// must not touch the operator's real Application Support directory, and a test
/// that had to would be a test nobody runs twice.
abstract interface class TerminalConfigStore {
  Future<SavedTerminalConfig?> read();
  Future<void> write(SavedTerminalConfig config);
  Future<void> clear();
}

/// The terminal's configuration, on disk beside its licence.
///
/// A plain JSON file, deliberately: an engineer standing at a till that will
/// not connect needs to be able to read what it thinks its database address is
/// without a debugger. Nothing secret is in it — the database password lives in
/// the OS keystore, and [SavedTerminalConfig.toJson] has no field for one.
///
/// A damaged or truncated file reads as **no configuration**, so the terminal
/// boots into the wizard rather than refusing to start. That is the same
/// bargain [FileLicenseStore] makes: a till that will not open because a file
/// got half-written is a lost service, and setup takes two minutes.
class FileTerminalConfigStore implements TerminalConfigStore {
  FileTerminalConfigStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'config.json';

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  @override
  Future<SavedTerminalConfig?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;

      final config = SavedTerminalConfig.fromJson(
        decoded.cast<String, Object?>(),
      );
      // A half-written config is not a configured terminal. Better the wizard
      // than a start screen whose every query fails.
      return config.isUsable ? config : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Written to a temporary file and renamed into place.
  ///
  /// A rename is atomic on both platforms the till runs on, so a power cut
  /// while setup is being saved leaves either the old configuration or the new
  /// one — never half of one.
  @override
  Future<void> write(SavedTerminalConfig config) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    await temporary.rename(target.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}
