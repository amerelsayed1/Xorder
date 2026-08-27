import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/floor/floor_screen.dart';
import '../features/licensing/presentation/licence_screen.dart';
import '../features/setup/presentation/setup_wizard.dart';
import '../features/lock/lock_screen.dart';
import '../features/sale/sale_screen.dart';
import '../features/start/start_screen.dart';
import 'providers.dart';

abstract final class PosRoutes {
  static const setup = '/setup';
  static const licence = '/licence';
  static const start = '/';
  static const lock = '/lock';
  static const floor = '/floor';
  static const sale = '/sale';
}

/// Top-level navigation.
///
/// Only whole-screen transitions live here. Modifier sheets, payment and the
/// receipt are dialogs over the sale screen — they are steps in one task, and
/// routing them would put the cashier's ticket at the mercy of a back gesture.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: PosRoutes.start,
    // First run sends the terminal to the wizard and keeps it there. Setup is
    // not skippable: a till with no branch, no licence and no cached menu has
    // nothing useful it could do anyway.
    redirect: (context, state) {
      final configured = ref.read(setupCompleteProvider);
      if (!configured && state.matchedLocation != PosRoutes.setup) return PosRoutes.setup;
      if (configured && state.matchedLocation == PosRoutes.setup) return PosRoutes.start;
      return null;
    },
    routes: [
      GoRoute(
        path: PosRoutes.setup,
        builder: (context, state) => SetupWizard(
          onFinished: () => context.go(PosRoutes.start),
        ),
      ),
      GoRoute(
        path: PosRoutes.licence,
        builder: (context, state) => LicenceScreen(
          onClose: () => context.go(PosRoutes.start),
        ),
      ),
      GoRoute(
        path: PosRoutes.start,
        builder: (context, state) => StartScreen(
          onStart: () => context.go(PosRoutes.floor),
          onManageLicence: () => context.go(PosRoutes.licence),
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
            ref.read(ticketProvider.notifier).attachTable(table);
            context.go(PosRoutes.sale);
          },
        ),
      ),
      GoRoute(
        path: PosRoutes.sale,
        builder: (context, state) => SaleScreen(
          onLock: () => context.go(PosRoutes.lock),
          onTables: () => context.go(PosRoutes.floor),
          onCloseShift: () => context.go(PosRoutes.start),
        ),
      ),
    ],
  );
});
