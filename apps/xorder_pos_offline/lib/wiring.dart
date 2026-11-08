/// "XOrder POS - Offline": what this app binds over the shared till
/// (pos-split-apps, stage 3).
///
/// Two things. The back office: the management screen and the window bar's
/// menus are this app's (`lib/features/admin`), reached by the shared shell
/// through `BackOffice`. And the three authoring repositories only an offline
/// till has — its catalogue, its accounts and its logo — whose shared default
/// is null, the cloud answer (pos-split-apps, stage 4). Nothing is bound for
/// sync, provisioning or seeding: the shared defaults already mean "no
/// platform", which is what an offline till is.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_business_logo_repository.dart';
import 'package:shared_module/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:shared_module/data/postgres/postgres_financial_accounts_admin_repository.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'features/admin/presentation/management_screen.dart';

/// The offline app's overrides, added by `runPos` after the shared bindings.
List<Override> offlineOverrides() => [
  backOfficeProvider.overrideWithValue(const OfflineBackOffice()),
  catalogAdminRepositoryProvider.overrideWith(_catalogAdmin),
  financialAccountsAdminRepositoryProvider.overrideWith(_financialAccountsAdmin),
  businessLogoRepositoryProvider.overrideWith(_businessLogo),
];

// The three authoring repositories below were built in `providers.dart`
// behind `if (config.mode != DeploymentMode.offline) return null;` — a check
// that chose between the two apps, not a rule inside either. They moved here
// verbatim less that line (pos-split-apps, stage 4): in this app the mode is
// always offline, and in the cloud app nothing binds them, so each stays
// null there exactly as the check made it. What is left is "no database yet",
// which is a real state of this app (the wizard runs before one exists).
//
// Each writes on the ADMINISTRATOR connection, like every authoring
// repository; `adminAvailable` is false until Admin Mode has the password.

/// Authoring the menu. Writes only: the catalogue is READ through
/// `catalogRepositoryProvider` on the till's credential, which is what the
/// sale screen already uses.
CatalogAdminRepository? _catalogAdmin(Ref ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresCatalogAdminRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    offline: true,
    businessId: context.businessId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
}

/// Authoring the chart of accounts.
FinancialAccountsAdminRepository? _financialAccountsAdmin(Ref ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresFinancialAccountsAdminRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    offline: true,
    businessId: context.businessId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
}

/// Where the owner changes the logo the receipt prints.
BusinessLogoRepository? _businessLogo(Ref ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresBusinessLogoRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    offline: true,
    businessId: context.businessId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
}

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
