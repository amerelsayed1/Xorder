import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/management_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/history/presentation/order_history_screen.dart';
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
  static const orders = '/orders';
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
      // A branch that does not seat anybody has no floor. Sending a takeaway
      // counter to a table picker asks a question it has no answer to.
      // "Does anything this branch sells have tables", not "does it sell
      // dine-in". A restaurant that seats catering orders and calls them
      // nothing of the sort still has a floor plan (§31).
      if (at == PosRoutes.floor && !ref.read(orderTypeRulesProvider).hasSeating) {
        return PosRoutes.sale;
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
      // A destination rather than a dialog over the sale screen: somebody
      // arrives here with a receipt in their hand, and routing it means the
      // live ticket is not put at risk by a back gesture. Leaving returns to
      // the till with that ticket exactly as it was.
      GoRoute(
        path: PosRoutes.orders,
        builder: (context, state) =>
            OrderHistoryScreen(onClose: () => context.go(PosRoutes.sale)),
      ),
      // Not nested under the sale screen: Management is a place somebody goes,
      // not a step in ringing up a ticket, and a back gesture out of it must
      // land on the start screen rather than half a dialog.
      GoRoute(
        path: PosRoutes.management,
        builder: (context, state) {
          // `extra` names which pane the caller meant and where they came from.
          // A bare pane is still accepted, and absent means the default, so
          // "Management" opens where it always did.
          final destination = switch (state.extra) {
            final ManagementDestination d => d,
            final ManagementPane p => ManagementDestination(pane: p),
            _ => const ManagementDestination(pane: ManagementPane.staff),
          };
          return ManagementScreen(
            onClose: () =>
                context.go(destination.returnTo ?? PosRoutes.start),
            initialPane: destination.pane,
          );
        },
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
          onClose: () => context.go(PosRoutes.start),
          onSellWithoutTable: () {
            // Nobody is seated, so the ticket must not stay on a type that
            // expects a table — it would price a service charge for one that
            // does not exist. Take the first unseated type the branch sells.
            final rules = ref.read(orderTypeRulesProvider);
            final counter = ref
                .read(branchOrderTypesProvider)
                .where((type) => !rules.requiresTable(type))
                .firstOrNull;
            if (counter != null) {
              ref.read(ticketProvider.notifier).setOrderType(counter);
            }
            context.go(PosRoutes.sale);
          },
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
          onOrders: () => context.go(PosRoutes.orders),
          onCloseShift: () => context.go(PosRoutes.start),
          // Back to the sale screen on close, not to the start screen: the
          // shift is still open and the ticket is still in memory, so a manager
          // who steps out to enter an invoice lands back on it.
          onManage: (pane) => context.go(
            PosRoutes.management,
            extra: ManagementDestination(
              pane: pane,
              returnTo: PosRoutes.sale,
            ),
          ),
        ),
      ),
    ],
  );
});
