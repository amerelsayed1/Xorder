import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/deployment.dart';
import '../core/ui/widgets/pos_widgets.dart' show posToast;
import '../features/admin/presentation/cloud_back_office_screen.dart';
import '../features/admin/presentation/management_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/history/presentation/order_history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/licensing/presentation/licence_screen.dart';
import '../features/setup/presentation/setup_wizard.dart';
import '../features/setup/presentation/welcome_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/sale/sale_screen.dart';
import '../features/start/start_screen.dart';
import '../domain/models/ticket.dart' show OrderType;
import 'providers.dart';

abstract final class PosRoutes {
  static const welcome = '/welcome';
  static const setup = '/setup';
  static const licence = '/licence';
  static const start = '/';
  static const lock = '/lock';
  static const home = '/home';
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
/// — Start's sign-in is what asks who is there.
///
/// **Resuming after a restart no longer comes through here.** Start signs the
/// person in first (pos-signin-first-home), so the lock screen is only reached
/// by Lock, Switch user and the idle lock. Home is not in the set: with nobody
/// signed in it goes to Start.
bool needsSignIn({
  required String at,
  required bool signedIn,
  required bool shiftOpen,
}) =>
    // Home is not here: it is the screen a person lands on after signing in,
    // shift or no shift, so with nobody signed in it goes to Start instead
    // (the redirect below), never to a lock screen that would unlock into it.
    (at == PosRoutes.sale || at == PosRoutes.floor) && !signedIn && shiftOpen;

/// The lock screen, remembering which selling screen sent the till to it.
///
/// A till restarted mid-service has its shift open and nobody signed in, so
/// Resume goes to Home (or the floor, or the sale) and the guard above turns it
/// round to the lock screen. Unlocking used to land on the sale screen whatever
/// the till had been heading for, which skipped the home screen for the most
/// ordinary way a shift is resumed (pos-home-screen). The destination travels
/// in the location, where a redirect can put it.
String lockLocationFrom(String at) =>
    Uri(path: PosRoutes.lock, queryParameters: {'next': at}).toString();

/// Where unlocking goes: the selling screen the till was heading for, or the
/// sale screen — where a cashier who pressed Lock was, and the answer for
/// anything this does not name (a `next` is a string in a URL, never trusted
/// to be a route).
String unlockTarget(String? next) =>
    const {PosRoutes.sale, PosRoutes.floor, PosRoutes.home}.contains(next)
    ? next!
    : PosRoutes.sale;

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
  // ── Where a shift goes, and where an order type goes (pos-home-screen) ────
  //
  // **One place for both**, so Start, the home screen and the floor's way back
  // cannot disagree. A type that needs a table opens the floor to pick one;
  // any other starts a sale of that type, through the same `setOrderType` the
  // sale screen's own switch uses, so every rule of switching type applies.
  void openType(BuildContext context, OrderType type) {
    if (ref.read(orderTypeRulesProvider).requiresTable(type)) {
      context.go(PosRoutes.floor);
      return;
    }
    ref.read(ticketProvider.notifier).setOrderType(type);
    context.go(PosRoutes.sale);
  }

  // The home screen is for a branch that sells more than one way. With one, it
  // is a screen with a single button, and a café, a food truck or a
  // delivery-only kitchen would pay a tap for nothing: they go where Start sent
  // them before.
  bool hasChoice() => ref.read(branchOrderTypesProvider).length > 1;

  /// Escape on the sale screen or the floor goes back to Home — only for a
  /// branch that has one. A seated ticket with lines is parked on its table on
  /// the way out, exactly as leaving for the floor does, so a dine-in bill is
  /// never converted into another type or lost by the next button pressed on
  /// Home; an unseated ticket stays in the cart (the sale screen's own rule).
  Future<void> leaveSaleTo(BuildContext context, String location) async {
    // Leaving a seated, non-empty ticket parks it on its table — the floor
    // then shows the table busy with its running total, and the live ticket
    // clears so the next table starts fresh.
    //
    // **Seated only, still.** An unseated ticket on the way to the floor is a
    // ticket somebody is going to seat: parking it as a held ticket and
    // clearing the screen would take the order away from the cashier at the
    // exact moment they were choosing its table. Putting an unseated ticket
    // down is what Park is for, and it is one key away.
    final ticket = ref.read(ticketProvider);
    if (ticket.isSeated && ticket.lines.isNotEmpty) {
      final saved = await ref.read(openTicketsProvider.notifier).park(ticket);
      if (!saved || !context.mounted) return;
      ref.read(ticketProvider.notifier).reset();
    }
    if (context.mounted) context.go(location);
  }

  Future<void> afterShift(BuildContext context) async {
    // **Decided on the restaurant's answer, not on the fallback.** Nothing has
    // asked for the order-type configuration or the branch's supported types
    // by the time Start is pressed, so a bare read would see the seeded four
    // and send a one-way branch to a home screen it then has to leave. Start
    // warms both while the shift opens; this waits for whatever is left, and
    // falls back to what the till already believes if either cannot be read.
    try {
      await ref.read(orderTypeConfigProvider.future);
      await ref.read(branchesProvider.future);
    } on Object {
      // The providers' own fallbacks apply.
    }
    if (!context.mounted) return;
    if (hasChoice()) {
      context.go(PosRoutes.home);
      return;
    }
    openType(context, ref.read(branchOrderTypesProvider).single);
  }

  /// Where somebody goes once they have signed in at Start
  /// (pos-signin-first-home).
  ///
  /// Home, unless a shift is already open and the branch sells one way: then
  /// there is nothing to choose and nothing to start, so they go where Start
  /// sent them before. A one-type branch with **no** shift open sees Home, which
  /// is where Start shift is.
  Future<void> afterSignIn(BuildContext context) async {
    try {
      await ref.read(orderTypeConfigProvider.future);
      await ref.read(branchesProvider.future);
      await ref.read(shiftProvider.future);
    } on Object {
      // The providers' own fallbacks apply.
    }
    if (!context.mounted) return;
    final shiftOpen = ref.read(shiftProvider).valueOrNull != null;
    if (shiftOpen && !hasChoice()) {
      openType(context, ref.read(branchOrderTypesProvider).single);
      return;
    }
    context.go(PosRoutes.home);
  }

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
      // Home is for somebody who has signed in; with nobody, the way in is Start.
      if (at == PosRoutes.home && ref.read(signedInStaffProvider) == null) {
        return PosRoutes.start;
      }
      if (needsSignIn(
        at: at,
        signedIn: ref.read(signedInStaffProvider) != null,
        shiftOpen: ref.read(shiftProvider).valueOrNull != null,
      )) {
        return lockLocationFrom(at);
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
          onStart: () => afterSignIn(context),
          onManageLicence: () => context.go(PosRoutes.licence),
          onManage: (pane) =>
              context.go(PosRoutes.management, extra: pane),
        ),
      ),
      GoRoute(
        path: PosRoutes.lock,
        builder: (context, state) => LockScreen(
          // The idle lock says why it came here; Lock and the redirect above
          // carry nothing, and the screen says nothing extra.
          afterInactivity: state.extra == LockReason.inactivity,
          // Unlocking returns to where the till was: the shift stayed open and
          // the ticket is still in memory, so the cashier lands where they
          // left off — the sale screen after Lock, and the screen a restarted
          // till was heading for (Home, the floor) after a resume.
          //
          // **With no shift open it is Home, whatever was asked for.** Somebody
          // can now be signed in without a shift (pos-signin-first-home), and
          // Lock or Switch user from Home would otherwise unlock onto the sale
          // screen and take cash against no drawer (`shift_id` NULL).
          onUnlocked: () => context.go(
            ref.read(shiftProvider).valueOrNull == null
                ? PosRoutes.home
                : unlockTarget(state.uri.queryParameters['next']),
          ),
          // The screen signs out first, so resuming the shift from the start
          // screen is sent straight back here for a name and a PIN.
          onBack: () => context.go(PosRoutes.start),
        ),
      ),
      GoRoute(
        path: PosRoutes.home,
        builder: (context, state) => HomeScreen(
          onPick: (type) => openType(context, type),
          // A shift was just opened here: a one-way branch goes selling,
          // one with a choice stays on Home, now with its buttons live.
          onShiftOpened: () => afterShift(context),
          // Escape and Sign out: the person signs out (Home does that),
          // and Start is the signed-out door.
          onBack: () => context.go(PosRoutes.start),
        ),
      ),
      GoRoute(
        path: PosRoutes.floor,
        builder: (context, state) => FloorScreen(
          // Home carries what the header's two buttons did (pos-home-screen).
          hasHome: hasChoice(),
          // Back to the screen it was reached from: Home when there is one.
          onClose: () =>
              context.go(hasChoice() ? PosRoutes.home : PosRoutes.start),
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
          onTables: () => leaveSaleTo(context, PosRoutes.floor),
          // Escape, one step back along the way here: the floor for an order
          // that is seated, otherwise Home. A branch with neither (one way of
          // selling, no tables) has nothing before the sale but Start, and
          // leaving a selling screen for it is Close shift's deliberate act,
          // not a key (pos-home-screen).
          onBack: () {
            final type = ref.read(ticketProvider).orderType;
            if (ref.read(orderTypeRulesProvider).requiresTable(type) &&
                ref.read(orderTypeRulesProvider).hasSeating) {
              leaveSaleTo(context, PosRoutes.floor);
            } else if (hasChoice()) {
              leaveSaleTo(context, PosRoutes.home);
            }
          },
          onOrders: () => context.go(PosRoutes.orders),
        ),
      ),
    ],
  );
});
