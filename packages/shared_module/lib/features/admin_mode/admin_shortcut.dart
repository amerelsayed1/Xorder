import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/config/admin_mode_settings.dart';

/// The key presses that open Admin Mode for [shortcut].
///
/// Control and Command both, as every other chord in this app is: Control for
/// the Windows tills this ships to, Command for macOS. None of them is
/// Ctrl+Shift+R, which is the forced reset, and none is a bare F-key, which are
/// the sale screen's.
List<SingleActivator> adminShortcutActivators(AdminShortcut shortcut) {
  final (key, alt) = switch (shortcut) {
    AdminShortcut.ctrlShiftS => (LogicalKeyboardKey.keyS, false),
    AdminShortcut.ctrlShiftA => (LogicalKeyboardKey.keyA, false),
    AdminShortcut.ctrlAltS => (LogicalKeyboardKey.keyS, true),
    AdminShortcut.ctrlShiftF12 => (LogicalKeyboardKey.f12, false),
  };
  return [
    SingleActivator(key, control: true, shift: !alt, alt: alt),
    SingleActivator(key, meta: true, shift: !alt, alt: alt),
  ];
}

/// How [shortcut] is written. Not translated: these are the names printed on
/// the keys, in Windows' spelling and then the Mac's.
String adminShortcutLabel(AdminShortcut shortcut) => switch (shortcut) {
  AdminShortcut.ctrlShiftS => 'Ctrl+Shift+S · ⇧⌘S',
  AdminShortcut.ctrlShiftA => 'Ctrl+Shift+A · ⇧⌘A',
  AdminShortcut.ctrlAltS => 'Ctrl+Alt+S · ⌥⌘S',
  AdminShortcut.ctrlShiftF12 => 'Ctrl+Shift+F12 · ⇧⌘F12',
};
