import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/deployment.dart';
import '../core/ui/widgets/pos_widgets.dart' show posToast;
import '../features/admin/presentation/cloud_back_office_screen.dart';
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

/// Whether a screen that SELLS is about to be shown with nobody signed in.
///
/// A till restarted mid-service comes back with its shift still open — the
/// shift is a row in PostgreSQL and the drawer never closed — but with nobody
/// signed in, because a PIN is deliberately not remembered across a restart.
/// Nothing then asked for one: resuming an open shift went straight to the
/// till. So sales were rung up under no name at all, and the cash-up refused
/// with "sign in before closing a shift" behind a door that did not exist —
/// `_start()` skips the PIN when a shift is already open, and the lock screen
/// only checked PINs rather than acting on them.
///
/// Both halves are fixed: the lock screen signs in whoever's PIN it is, and
/// this sends an unattended till to it.
///
/// Only when a shift is OPEN. A terminal sitting on the start screen before
/// trading has nobody signed in either, and that is the ordinary morning state
/// — opening the shift is what asks who is there.
bool needsSignIn({
  required String at,
  required bool signedIn,
  required bool shiftOpen,
}) =>
    (at == PosRoutes.sale || at == PosRoutes.floor) && !signedIn && shiftOpen;

/// Top-level navigation.
///
/// Only whole-screen transitions live here. Modifier sheets, payment and the
/// receipt are dialogs over the sale screen — they are steps in one task, and
/// routing them would put the cashier's ticket at the mercy of a back gesture.
/// The root navigator, exposed so the app-level chords (the forced reset's
/// Cmd/Ctrl+Shift+R) can show their dialogs. They are registered ABOVE the
/// router (they must work on every screen), and a context from up there has no
/// Navigator in it — the
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
      if (needsSignIn(
        at: at,
        signedIn: ref.read(signedInStaffProvider) != null,
        shiftOpen: ref.read(shiftProvider).valueOrNull != null,
      )) {
        return PosRoutes.lock;
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
        // Back to where it was opened from — the Settings menu can open it
        // from any screen — and to the till when nobody said.
        builder: (context, state) => OrderHistoryScreen(
          onClose: () => context.go(
            state.extra is String ? state.extra! as String : PosRoutes.sale,
          ),
        ),
      ),
      // Not nested under the sale screen: Management is a place somebody goes,
      // not a step in ringing up a ticket, and a back gesture out of it must
      // land on the start screen rather than half a dialog.
      GoRoute(
        path: PosRoutes.management,
        builder: (context, state) {
          // `extra` names which pane the caller meant and where they came from.
          // A bare pane is still accepted, and absent means the door's own
          // landing — the first tab that holds a pane (BO-1).
          final destination = switch (state.extra) {
            final ManagementDestination d => d,
            final ManagementPane p => ManagementDestination(pane: p),
            _ => const ManagementDestination(),
          };
          // **CB-07 (owner decision, 27 Sep 2026).** Enforced at the ROUTE and
          // not on the door that opens it: Management is reached from the
          // start screen, from Ctrl+Shift+S, from the status bar and from
          // deep links that name a pane, and a guard on any one of those is a
          // guard somebody adds a fifth way around. A cloud till has no back
          // office of its own — see [CloudBackOfficeScreen] for why editing a
          // row the platform authors is worse than not offering to.
          //
          // A CLAIMED cloud tenant, not merely `mode == cloud`:
          // `DeploymentConfig.unconfigured` is cloud, so guarding on the mode
          // alone locked a machine out of its own back office before it had a
          // restaurant — including the Terminal pane, which is how a till is
          // reconfigured. A tenant slug is the signal that a platform actually
          // authors this till's rows.
          final deployment = ref.read(deploymentProvider);
          if (deployment.mode == DeploymentMode.cloud &&
              (deployment.tenantSlug ?? '').isNotEmpty) {
            return CloudBackOfficeScreen(
              onClose: () => context.go(destination.returnTo ?? PosRoutes.start),
            );
          }
          return ManagementScreen(
            onClose: () =>
                context.go(destination.returnTo ?? PosRoutes.start),
            onReconfigure: () => context.go(PosRoutes.setup),
            initialPane: destination.pane,
            purchasingTab: destination.purchasingTab,
            create: destination.create,
            request: destination.request,
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
          onManage: (pane) =>
              context.go(PosRoutes.management, extra: pane),
        ),
      ),
      GoRoute(
        path: PosRoutes.lock,
        builder: (context, state) => LockScreen(
          // Unlocking returns to the sale screen: the shift stayed open and the
          // ticket is still in memory, so the cashier lands where they left off.
          onUnlocked: () => context.go(PosRoutes.sale),
          // The screen signs out first, so resuming the shift from the start
          // screen is sent straight back here for a name and a PIN.
          onBack: () => context.go(PosRoutes.start),
        ),
      ),
      GoRoute(
        path: PosRoutes.floor,
        builder: (context, state) => FloorScreen(
          onClose: () => context.go(PosRoutes.start),
          // Carried back to the sale screen whichever way the floor resolves,
          // so a collect that came here for a table goes on into payment.
          onSellWithoutTable: () async {
            // A ticket being moved off its table leaves it behind.
            if (state.extra == SaleIntent.moveTable) {
              await ref
                  .read(openTicketsProvider.notifier)
                  .release(ref.read(ticketProvider));
              if (!context.mounted) return;
            }
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
            context.go(PosRoutes.sale, extra: state.extra);
          },
          onTablePicked: (table) async {
            // Changing table: the ticket on screen moves, rather than a new
            // one starting here or a parked one being adopted over it.
            if (state.extra == SaleIntent.moveTable) {
              final moved = await ref
                  .read(ticketProvider.notifier)
                  .moveTo(table);
              if (!context.mounted) return;
              if (!moved) {
                posToast(
                  context,
                  ref.read(stringsProvider).tableTaken(table.label),
                );
                return;
              }
              context.go(PosRoutes.sale);
              return;
            }
            // A busy table resumes its parked ticket — same transaction id,
            // same lines. A free one seats the live ticket.
            final parked = ref.read(openTicketsProvider.notifier).at(table.id);
            if (parked != null) {
              ref.read(ticketProvider.notifier).adopt(parked);
            } else {
              ref.read(ticketProvider.notifier).attachTable(table);
            }
            context.go(PosRoutes.sale, extra: state.extra);
          },
        ),
      ),
      GoRoute(
        path: PosRoutes.sale,
        builder: (context, state) => SaleScreen(
          collectOnOpen: state.extra == SaleIntent.collect,
          onLock: () => context.go(PosRoutes.lock),
          onTablesToCollect: () =>
              context.go(PosRoutes.floor, extra: SaleIntent.collect),
          onChangeTable: () =>
              context.go(PosRoutes.floor, extra: SaleIntent.moveTable),
          onTables: () async {
            // Leaving a seated, non-empty ticket parks it on its table — the
            // floor then shows the table busy with its running total, and the
            // live ticket clears so the next table starts fresh.
            //
            // **Seated only, still.** An unseated ticket on the way to the floor
            // is a ticket somebody is going to seat: parking it as a held ticket
            // and clearing the screen would take the order away from the cashier
            // at the exact moment they were choosing its table. Putting an
            // unseated ticket down is what Park is for, and it is one key away.
            final ticket = ref.read(ticketProvider);
            if (ticket.isSeated && ticket.lines.isNotEmpty) {
              final saved = await ref
                  .read(openTicketsProvider.notifier)
                  .park(ticket);
              if (!saved || !context.mounted) return;
              ref.read(ticketProvider.notifier).reset();
            }
            context.go(PosRoutes.floor);
          },
          onOrders: () => context.go(PosRoutes.orders),
          onCloseShift: () => context.go(PosRoutes.start),
        ),
      ),
    ],
  );
});
