import 'dart:ui' show Brightness;

import 'deployment.dart';
import 'terminal_profile.dart';

/// Everything the setup wizard settled that has to outlive the process.
///
/// One file, one write, at the end of the wizard. Splitting it across several
/// would create states no operator ever chose — a terminal that knows its
/// branch but not its database, or the reverse — and a till that boots half
/// configured is worse than one that boots into setup.
///
/// The database password is **not** here. It goes to the OS keystore through
/// `PosDbSecretStore`; see [DeploymentConfig.toJson], which omits it for the
/// same reason.
/// Distinguishes "argument not passed" from "passed as null".
const Object _unset = Object();

class SavedTerminalConfig {
  const SavedTerminalConfig({
    required this.deployment,
    required this.terminal,
    required this.languageCode,
    this.brightness,
    this.setupComplete = true,
  });

  /// Bumped when a field's meaning changes rather than when one is added.
  /// Adding is handled by the tolerant readers on both halves.
  static const currentVersion = 1;

  final DeploymentConfig deployment;
  final TerminalProfile terminal;

  /// The language the till was set up in — a property of the terminal, not of
  /// the cashier, so it is restored before the first frame rather than after a
  /// sign-in.
  final String languageCode;

  /// Light or dark, or **null** for "follow the machine".
  ///
  /// Nullable rather than defaulted, because "the operator has not chosen" and
  /// "the operator chose light" are different states: the first should track a
  /// till that switches at dusk with the rest of the desk, the second must not.
  final Brightness? brightness;

  /// False would mean a config written by a wizard that did not finish. Nothing
  /// writes that today; it is read so that a future partial save cannot silently
  /// present itself as a configured till.
  final bool setupComplete;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'setup_complete': setupComplete,
    'language': languageCode,
    'brightness': brightness?.name,
    'deployment': deployment.toJson(),
    'terminal': terminal.toJson(),
  };

  static SavedTerminalConfig fromJson(Map<String, Object?> json) =>
      SavedTerminalConfig(
        deployment: DeploymentConfig.fromJson(
          (json['deployment'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        terminal: TerminalProfile.fromJson(
          (json['terminal'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        languageCode: json['language'] as String? ?? 'en',
        // An unknown or absent value reads as "follow the machine" rather than
        // as a failure: a config written by a newer build must not send this
        // terminal back to the wizard over a colour scheme.
        brightness: switch (json['brightness']) {
          'dark' => Brightness.dark,
          'light' => Brightness.light,
          _ => null,
        },
        setupComplete: json['setup_complete'] as bool? ?? false,
      );

  /// True when this config can actually open a till.
  ///
  /// A saved file that names no terminal, or no database to reach, sends the
  /// operator back to the wizard rather than to a start screen whose every
  /// query would fail.
  bool get isUsable =>
      setupComplete && terminal.isSet && deployment.isConfigured;

  /// For the settings a terminal changes AFTER setup — the language and the
  /// brightness. Everything else in here is the wizard's to write.
  ///
  /// [brightness] takes a sentinel rather than a plain null, because null is a
  /// value this field holds ("follow the machine") and not only the absence of
  /// an argument.
  SavedTerminalConfig copyWith({
    String? languageCode,
    Object? brightness = _unset,
  }) => SavedTerminalConfig(
    deployment: deployment,
    terminal: terminal,
    languageCode: languageCode ?? this.languageCode,
    brightness: brightness == _unset
        ? this.brightness
        : brightness as Brightness?,
    setupComplete: setupComplete,
  );
}

/// What this process knew about the terminal before its first frame.
///
/// The configuration file and the database credential are read from two
/// different places — a JSON file and the OS keystore — and a till needs
/// **both** to open. Pairing them in one value keeps that rule in one place
/// instead of leaving every reader to remember it.
class TerminalBoot {
  const TerminalBoot({
    this.config,
    this.hasDatabaseCredential = false,
    this.credentialStoreUnavailable = false,
  });

  /// A fresh install, or one whose configuration would not parse.
  static const none = TerminalBoot();

  final SavedTerminalConfig? config;

  /// Whether the keystore gave back the `pos_till` password.
  ///
  /// False on a fresh install, and false when the keystore refused — a wiped
  /// keychain, a rebuilt machine, an unsigned binary. Both send the operator to
  /// the wizard, which is seeded from [config] so only the password is missing.
  final bool hasDatabaseCredential;

  /// True when the keystore itself refused, rather than simply holding nothing.
  ///
  /// Both send the operator to the wizard, so this changes no routing — it
  /// changes what the wizard is allowed to *say*. Without it the two causes are
  /// indistinguishable at the password field, and the second one is the one
  /// where typing a password again will not help: it will be accepted, setup
  /// will appear to finish, and the wizard will be back tomorrow morning.
  final bool credentialStoreUnavailable;

  /// True when this terminal can actually open: it knows where its database is,
  /// which branch and till it is, **and** holds the credential to connect.
  bool get isConfigured => (config?.isUsable ?? false) && hasDatabaseCredential;
}
