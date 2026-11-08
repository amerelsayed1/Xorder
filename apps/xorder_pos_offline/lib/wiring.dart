/// "XOrder POS - Offline": what this app binds over the shared till
/// (pos-split-apps, stage 3).
///
/// One thing: the back office. The management screen and the window bar's
/// menus are this app's (`lib/features/admin`), reached by the shared shell
/// through `BackOffice`. Nothing is bound for sync, provisioning or seeding —
/// the shared defaults already mean "no platform", which is what an offline
/// till is.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/domain/models/shift.dart';

import 'features/admin/presentation/management_screen.dart';

/// The offline app's overrides, added by `runPos` after the shared bindings.
List<Override> offlineOverrides() => [
  backOfficeProvider.overrideWithValue(const OfflineBackOffice()),
];

/// The full back office on the till (D2).
final class OfflineBackOffice implements BackOffice {
  const OfflineBackOffice();

  @override
  Widget screen(
    BuildContext context, {
    required ManagementDestination destination,
    required VoidCallback onClose,
    required VoidCallback onReconfigure,
  }) => ManagementScreen(
    onClose: onClose,
    onReconfigure: onReconfigure,
    initialPane: destination.pane,
    purchasingTab: destination.purchasingTab,
    create: destination.create,
    request: destination.request,
  );

  @override
  List<ManagementBarMenu> barMenus(
    AppStrings s, {
    required PosStaff admin,
    required bool authorsItsOwnCatalogue,
  }) => managementBarFor(
    s,
    admin: admin,
    authorsItsOwnCatalogue: authorsItsOwnCatalogue,
  );
}
