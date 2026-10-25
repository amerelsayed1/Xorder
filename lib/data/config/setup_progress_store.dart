import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/deployment.dart';

/// What a cloud claim answered, kept until the wizard finishes.
///
/// A pairing code is single-use, and the device token it earned is written the
/// moment the platform hands it over — so a restart between the claim and
/// "Open the till" used to strand the machine: the wizard reopened blank at the
/// licence step, the code was spent, and the account step demanded a claim that
/// had already happened. The only route out was "sign in instead", which the
/// installer standing there had never been told about.
///
/// This is the claim on disk, so `SetupController` can carry on at the
/// connecting step instead. Nothing secret is in it: the device token has its
/// own store, the database password its keystore, and the licence here is the
/// signed file the bundle embedded — public by construction and verified again
/// on the way back in.
///
/// Offline and child tills keep one too, for the seat rather than the code: a
/// registration on the branch database is an upsert keyed on [installationId],
/// and the installation id of a machine that has not finished setup lives only
/// in memory until `config.json` is written. A wizard killed after registering
/// and re-run under a freshly minted id would spend a second seat of the
/// licence's `max_terminals`. So that id is written down *before* the
/// registration is sent, with [claimed] false, and again after it with the
/// terminal the database answered.
///
/// Written after a claim, deleted when setup completes or the till is reset.
/// A damaged file reads as **no progress**, for the same reason a damaged
/// `config.json` reads as no configuration: the wizard from the top is a
/// two-minute cost, a wizard that will not open is a support call.
class SetupProgress {
  const SetupProgress({
    required this.deployment,
    required this.terminalId,
    required this.terminalName,
    this.locale,
    this.branchId,
    this.branchLabel,
    this.restaurantId,
    this.branchCode,
    this.licence,
    this.installationId,
    this.claimed = true,
    this.bootstrapped = false,
  });

  final DeploymentConfig deployment;
  final String terminalId;
  final String terminalName;

  /// The restaurant's language, from the claim. Null leaves the wizard in the
  /// language it opened in.
  final String? locale;
  final int? branchId;
  final String? branchLabel;
  final int? restaurantId;
  final String? branchCode;

  /// The licence file as serialised, or null when the wizard was carrying none
  /// — one restored from disk is already there and is read back the same way.
  final String? licence;

  /// `TerminalProfile.installationId` of the machine that wrote this. Not a
  /// secret — `config.json` holds it in the clear, and the licence only ever
  /// sees its hash — but the identity the registration upsert is keyed on.
  final String? installationId;

  /// Whether [terminalId] is a terminal the platform or the branch database
  /// actually issued. False for the record an offline till writes just before
  /// registering, when the id in the draft is only this machine's guess.
  /// Defaults to true because every record written before this field existed
  /// was a cloud claim, and was written only once the claim had succeeded.
  final bool claimed;

  /// The offline wizard built the database and its first administrator.
  final bool bootstrapped;

  Map<String, Object?> toJson() => {
    'deployment': deployment.toJson(),
    'terminal_id': terminalId,
    'terminal_name': terminalName,
    'locale': locale,
    'branch_id': branchId,
    'branch_label': branchLabel,
    'restaurant_id': restaurantId,
    'branch_code': branchCode,
    'licence': licence,
    'installation_id': installationId,
    'claimed': claimed,
    'bootstrapped': bootstrapped,
  };

  /// Null for a file this build cannot carry on from — no terminal, or no
  /// deployment to reach the platform with.
  static SetupProgress? fromJson(Map<String, Object?> json) {
    final deployment = json['deployment'];
    final terminalId = json['terminal_id'];
    if (deployment is! Map || terminalId is! String || terminalId.isEmpty) {
      return null;
    }

    return SetupProgress(
      deployment: DeploymentConfig.fromJson(deployment.cast<String, Object?>()),
      terminalId: terminalId,
      terminalName: json['terminal_name'] as String? ?? '',
      locale: json['locale'] as String?,
      branchId: json['branch_id'] as int?,
      branchLabel: json['branch_label'] as String?,
      restaurantId: json['restaurant_id'] as int?,
      branchCode: json['branch_code'] as String?,
      licence: json['licence'] as String?,
      installationId: json['installation_id'] as String?,
      claimed: json['claimed'] as bool? ?? true,
      bootstrapped: json['bootstrapped'] as bool? ?? false,
    );
  }
}

/// Where an unfinished setup is kept between launches.
///
/// Behind an interface for the reason [TerminalConfigStore] is: a widget test
/// must not touch the operator's Application Support directory.
abstract interface class SetupProgressStore {
  Future<SetupProgress?> read();
  Future<void> write(SetupProgress progress);
  Future<void> clear();
}

/// The claim, in a JSON file beside `config.json`.
class FileSetupProgressStore implements SetupProgressStore {
  FileSetupProgressStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'setup-progress.json';

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  @override
  Future<SetupProgress?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;

      return SetupProgress.fromJson(decoded.cast<String, Object?>());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Written to a temporary file and renamed into place, like the config: a
  /// power cut mid-write leaves the old progress or the new, never half.
  @override
  Future<void> write(SetupProgress progress) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(progress.toJson()),
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
