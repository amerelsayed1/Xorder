import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which build this is. **Fixed at compile time by the entry point**
/// (`main_cloud.dart` · `main_offline.dart`), never chosen by the waiter:
/// the two flavors are two apps on the store, each opening on its own
/// sign-in screen (owner decision, 2026-11-09).
enum WaiterMode {
  /// "XOrder Waiter – Cloud": signs in to xorder.io with the restaurant's
  /// slug, a name and a PIN. The platform serves the waiter wire (POS-BE-033).
  cloud,

  /// "XOrder Waiter – Offline": signs in to the till on the restaurant LAN
  /// with its address, a name and a PIN.
  offline,
}

/// The mode the running app was built with. Bound by the entry point; a
/// screen reading it unbound is a bug in the build, not a state to handle.
final waiterModeProvider = Provider<WaiterMode>(
  (_) => throw StateError('waiterModeProvider is bound by main_cloud.dart / main_offline.dart'),
);

/// The platform's host in the cloud flavor: `demo` signs in at
/// `https://xorder.io/api/pos/waiter/demo` (the restaurant is the slug in the
/// path, POS-BE-033). A staging build overrides the host at compile time.
const cloudDomain = String.fromEnvironment('XORDER_CLOUD_DOMAIN', defaultValue: 'xorder.io');

/// The mode, for widgets that only have a [BuildContext] (the strings).
class WaiterModeScope extends InheritedWidget {
  const WaiterModeScope({super.key, required this.mode, required super.child});

  final WaiterMode mode;

  static WaiterMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WaiterModeScope>()?.mode ?? WaiterMode.offline;

  @override
  bool updateShouldNotify(WaiterModeScope oldWidget) => mode != oldWidget.mode;
}
