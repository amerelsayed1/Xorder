/// How this terminal lets somebody into Admin Mode.
///
/// Per terminal, in `config.json` beside the printer, rather than per
/// business: the till at the counter and the PC in the office can want
/// different timeouts, and neither is a fact about the business.
class AdminModeSettings {
  const AdminModeSettings({
    this.shortcut = AdminShortcut.ctrlShiftS,
    this.timeoutMinutes = defaultTimeoutMinutes,
  });

  static const standard = AdminModeSettings();

  static const defaultTimeoutMinutes = 5;

  /// The timeouts offered. **No "never".** An Admin Mode that does not lock is
  /// a back office left open at a till in a public room, and the plan's own
  /// auto-lock offers "never" only for the till, where the shift stays open
  /// behind it anyway.
  static const timeoutChoices = <int>[1, 2, 5, 10, 15, 30];

  final AdminShortcut shortcut;
  final int timeoutMinutes;

  Duration get timeout => Duration(minutes: timeoutMinutes);

  Map<String, Object?> toJson() => {
    'shortcut': shortcut.wire,
    'timeout_minutes': timeoutMinutes,
  };

  /// Tolerant, as the rest of the config file is: absent on every file written
  /// before Admin Mode existed, which reads as the defaults.
  static AdminModeSettings fromJson(Map<String, Object?> json) {
    final minutes = json['timeout_minutes'];
    return AdminModeSettings(
      shortcut: AdminShortcut.fromWire(json['shortcut'] as String?),
      // A value this build does not offer reads as the default, never as "no
      // timeout": a hand-edited or newer file must not be how Admin Mode stops
      // locking.
      timeoutMinutes: minutes is int && timeoutChoices.contains(minutes)
          ? minutes
          : defaultTimeoutMinutes,
    );
  }

  AdminModeSettings copyWith({AdminShortcut? shortcut, int? timeoutMinutes}) =>
      AdminModeSettings(
        shortcut: shortcut ?? this.shortcut,
        timeoutMinutes: timeoutMinutes ?? this.timeoutMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is AdminModeSettings &&
      other.shortcut == shortcut &&
      other.timeoutMinutes == timeoutMinutes;

  @override
  int get hashCode => Object.hash(shortcut, timeoutMinutes);
}

/// The chords Admin Mode can be opened with.
///
/// A short list rather than any chord somebody records: a free-form binding
/// can collide with the sale screen's F-keys or with the forced reset, and the
/// first person to find out would be a cashier whose F9 opened the back
/// office. Every entry here is checked against those once, in code.
enum AdminShortcut {
  ctrlShiftS('ctrl+shift+s'),
  ctrlShiftA('ctrl+shift+a'),
  ctrlAltS('ctrl+alt+s'),
  ctrlShiftF12('ctrl+shift+f12');

  const AdminShortcut(this.wire);

  /// As stored. Never shown.
  final String wire;

  /// Unknown or absent is the default — a newer build's chord must not leave
  /// this till with no way into Admin Mode at all.
  static AdminShortcut fromWire(String? value) {
    for (final shortcut in values) {
      if (shortcut.wire == value) return shortcut;
    }
    return ctrlShiftS;
  }
}
