import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/management_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/licensing/presentation/licence_screen.dart';
import '../features/setup/presentation/setup_wizard.dart';
import '../features/setup/presentation/welcome_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/sale/sale_screen.dart';
import '../features/start/start_screen.dart';
import 'providers.dart';

abstract final class PosRoutes {
  static const welcome = '/welcome';
  static const setup = '/setup';
  static const licence = '/licence';
  static const start = '/';
  static const lock = '/lock';
  static const floor = '/floor';
  static const sale = '/sale';
  static const management = '/management';
}

/// Top-level navigation.
///
/// Only whole-screen transitions live here. Modifier sheets, payment and the
/// receipt are dialogs over the sale screen — they are steps in one task, and
/// routing them would put the cashier's ticket at the mercy of a back gesture.
/// The root navigator, exposed so the app-level Cmd/Ctrl+Shift+S binding can
/// show its dialog. That shortcut is registered ABOVE the router (it must work
/// on every screen), and a context from up there has no Navigator in it — the
/// first attempt threw "Navigator operation requested with a context that does
/// not include a Navigator" and the dialog never appeared.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: PosRoutes.start,
    // First run shows the mark and waits: an unconfigured terminal sits on
    // the welcome screen until someone who knows the chord (Ctrl+Shift+S)
    // opens the wizard. Setup is still not skippable — the only two places an
    // unconfigured till may be are the welcome screen and the wizard itself.
    redirect: (context, state) {
      final configured = ref.read(setupCompleteProvider);
      final at = state.matchedLocation;
      if (!configured && at != PosRoutes.setup && at != PosRoutes.welcome) {
        return PosRoutes.welcome;
      }
      if (configured && (at == PosRoutes.setup || at == PosRoutes.welcome)) {
        return PosRoutes.start;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: PosRoutes.welcome,
        builder: (context, state) =>
            WelcomeScreen(onOpenSetup: () => context.go(PosRoutes.setup)),
      ),
      GoRoute(
        path: PosRoutes.setup,
        builder: (context, state) =>
            SetupWizard(onFinished: () => context.go(PosRoutes.start)),
      ),
      // Not nested under the sale screen: Management is a place somebody goes,
      // not a step in ringing up a ticket, and a back gesture out of it must
      // land on the start screen rather than half a dialog.
      GoRoute(
        path: PosRoutes.management,
        builder: (context, state) =>
            ManagementScreen(onClose: () => context.go(PosRoutes.start)),
      ),
      GoRoute(
        path: PosRoutes.licence,
        builder: (context, state) =>
            LicenceScreen(onClose: () => context.go(PosRoutes.start)),
      ),
      GoRoute(
        path: PosRoutes.start,
        builder: (context, state) => StartScreen(
          onStart: () => context.go(PosRoutes.floor),
          onManageLicence: () => context.go(PosRoutes.licence),
          onReconfigure: () => context.go(PosRoutes.setup),
          onManage: () => context.go(PosRoutes.management),
        ),
      ),
      GoRoute(
        path: PosRoutes.lock,
        builder: (context, state) => LockScreen(
          // Unlocking returns to the sale screen: the shift stayed open and the
          // ticket is still in memory, so the cashier lands where they left off.
          onUnlocked: () => context.go(PosRoutes.sale),
        ),
      ),
      GoRoute(
        path: PosRoutes.floor,
        builder: (context, state) => FloorScreen(
          onTablePicked: (table) {
            // A busy table resumes its parked ticket — same transaction id,
            // same lines. A free one seats the live ticket.
            final parked = ref.read(openTicketsProvider.notifier).at(table.id);
            if (parked != null) {
              ref.read(ticketProvider.notifier).adopt(parked);
            } else {
              ref.read(ticketProvider.notifier).attachTable(table);
            }
            context.go(PosRoutes.sale);
          },
        ),
      ),
      GoRoute(
        path: PosRoutes.sale,
        builder: (context, state) => SaleScreen(
          onLock: () => context.go(PosRoutes.lock),
          onTables: () {
            // Leaving a seated, non-empty ticket parks it on its table — the
            // floor then shows the table busy with its running total, and the
            // live ticket clears so the next table starts fresh.
            final ticket = ref.read(ticketProvider);
            if (ticket.isSeated && ticket.lines.isNotEmpty) {
              ref.read(openTicketsProvider.notifier).park(ticket);
              ref.read(ticketProvider.notifier).reset();
            }
            context.go(PosRoutes.floor);
          },
          onCloseShift: () => context.go(PosRoutes.start),
        ),
      ),
    ],
  );
});
