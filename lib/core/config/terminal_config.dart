import 'dart:ui' show Brightness;

import 'admin_mode_settings.dart';
import 'deployment.dart';
import 'printer_config.dart';
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
    this.printer = PrinterConfig.none,
    this.brightness,
    this.setupComplete = true,
    this.adminMode = AdminModeSettings.standard,
    this.lastUsername,
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

  /// Which printer this till prints on, and how wide its paper is.
  ///
  /// **This was chosen in the wizard and then dropped on the floor.** The
  /// hardware step has offered a printer list since setup existed, and nothing
  /// wrote the choice anywhere — so a till that had been pointed at a printer
  /// during installation came up the next morning knowing nothing about it, and
  /// there was no address for a receipt to be sent to. It is saved here for the
  /// same reason the branch is: it is a fact about this machine, not about
  /// whoever is signed into it.
  final PrinterConfig printer;

  /// False would mean a config written by a wizard that did not finish. Nothing
  /// writes that today; it is read so that a future partial save cannot silently
  /// present itself as a configured till.
  final bool setupComplete;

  /// Which chord opens Admin Mode on this till, and how long it stays open
  /// with nobody touching it.
  final AdminModeSettings adminMode;

  /// The username of the last person to sign in at this till, or null when
  /// nobody has yet.
  ///
  /// A fact about the machine, like the language: the same cashier comes back
  /// to the same till lock after lock, and typing their name on a keypad
  /// screen every time was the thing the audit (S3-2) watched them do. The
  /// lock screen offers it as a prefill the next person can change — never as
  /// an identity, which is still the PIN's to prove.
  final String? lastUsername;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'setup_complete': setupComplete,
    'language': languageCode,
    'brightness': brightness?.name,
    'deployment': deployment.toJson(),
    'terminal': terminal.toJson(),
    'printer': printer.toJson(),
    'admin_mode': adminMode.toJson(),
    'last_username': lastUsername,
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
        // Absent on every config file written before printing existed, which is
        // all of them: that reads as "no printer set up", and the till says so
        // at settlement rather than claiming to have printed.
        printer: PrinterConfig.fromJson(
          (json['printer'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        // An unknown or absent value reads as "follow the machine" rather than
        // as a failure: a config written by a newer build must not send this
        // terminal back to the wizard over a colour scheme.
        brightness: switch (json['brightness']) {
          'dark' => Brightness.dark,
          'light' => Brightness.light,
          _ => null,
        },
        setupComplete: json['setup_complete'] as bool? ?? false,
        adminMode: AdminModeSettings.fromJson(
          (json['admin_mode'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        // Absent on every file written before the lock screen remembered
        // anybody, and an empty name is no name.
        lastUsername: switch (json['last_username']) {
          final String name when name.trim().isNotEmpty => name.trim(),
          _ => null,
        },
      );

  /// True when this config can actually open a till.
  ///
  /// A saved file that names no terminal, or no database to reach, sends the
  /// operator back to the wizard rather than to a start screen whose every
  /// query would fail.
  bool get isUsable =>
      setupComplete && terminal.isSet && deployment.isConfigured;

  /// For the settings a terminal changes AFTER setup — the language, the
  /// brightness, who signed in last. Everything else in here is the wizard's
  /// to write.
  ///
  /// [brightness] and [lastUsername] take a sentinel rather than a plain
  /// null, because null is a value each field holds ("follow the machine",
  /// "nobody yet") and not only the absence of an argument.
  ///
  /// [deployment] is the one exception to "the wizard's to write": a
  /// technician changing this till's LAN encryption in Management › Devices
  /// rewrites only its transport fields, through here.
  SavedTerminalConfig copyWith({
    String? languageCode,
    Object? brightness = _unset,
    PrinterConfig? printer,
    AdminModeSettings? adminMode,
    Object? lastUsername = _unset,
    DeploymentConfig? deployment,
  }) => SavedTerminalConfig(
    deployment: deployment ?? this.deployment,
    terminal: terminal,
    languageCode: languageCode ?? this.languageCode,
    printer: printer ?? this.printer,
    brightness: brightness == _unset
        ? this.brightness
        : brightness as Brightness?,
    setupComplete: setupComplete,
    adminMode: adminMode ?? this.adminMode,
    lastUsername: lastUsername == _unset
        ? this.lastUsername
        : lastUsername as String?,
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
