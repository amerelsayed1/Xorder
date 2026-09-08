import '../models/catalog.dart';
import '../services/menu_import.dart';
import '../models/dining_table.dart';
import '../models/permissions.dart';
import '../models/receipt_profile.dart';
import '../models/shift.dart';
import '../models/ticket.dart';
import '../services/authorization.dart';

/// Contracts for the Management section: who works here, what they may do, and
/// the ledger of what they did.
///
/// Kept apart from `repositories.dart` because the till and the back office are
/// answerable to different rules. Everything a cashier touches is in that file
/// and reads the branch database through the till's credential; everything in
/// this one is an act somebody is *named on*, so every method takes the member
/// of staff performing it and every write lands beside an audit row in the same
/// transaction. A change that made it into the catalogue but not the ledger
/// would be a change nobody can be asked about.

/// Why an administrative write did not happen.
///
/// Data, not exceptions — the same reasoning as `TicketRefusal`. Every one of
/// these is a normal thing for a manager to attempt on a Tuesday, and a screen
/// that has to catch an exception to say "you cannot delete a role somebody is
/// on" will eventually catch it in the wrong place.
sealed class AdminRefusal {
  const AdminRefusal();
}

/// The person is not allowed, and no supervisor can lend it either.
class NotPermitted extends AdminRefusal {
  const NotPermitted(this.capability);

  final String capability;
}

/// The role still has people on it. Named, not counted: "3 people" sends a
/// manager hunting, and the list is one join away.
class RoleStillHeld extends AdminRefusal {
  const RoleStillHeld(this.staffNames);

  final List<String> staffNames;
}

/// A system role cannot be deleted, only edited.
class RoleIsSystemDefined extends AdminRefusal {
  const RoleIsSystemDefined(this.code);

  final String code;
}

/// The role as written breaks one of the two rules in
/// [Authorization.validateRole].
class RoleNotAllowed extends AdminRefusal {
  const RoleNotAllowed(this.reason);

  final RoleRefusal reason;
}

/// The licence covers this many user accounts and they are all in use.
///
/// Enforceable here in a way the terminal count is not: a till cannot see its
/// sibling machines, but every staff row is in the one database it is already
/// reading. Counted against ACTIVE staff, so somebody who left does not go on
/// occupying a seat the restaurant is paying for.
class UserSeatsExhausted extends AdminRefusal {
  const UserSeatsExhausted(this.maxUsers);

  final int maxUsers;
}

/// Usernames are unique per restaurant — that is what makes a PIN resolvable to
/// a person.
class UsernameTaken extends AdminRefusal {
  const UsernameTaken(this.username);

  final String username;
}

/// Disabling this person, or moving them off the owner role, would leave the
/// restaurant with nobody who can grant permissions.
///
/// Refused rather than warned about: the screen that would put it back is the
/// screen this would make unreachable, and the fix at that point is a psql
/// prompt at a restaurant on a Sunday.
class WouldLockEveryoneOut extends AdminRefusal {
  const WouldLockEveryoneOut(this.capability);

  final String capability;
}

/// Somebody else saved this record first.
///
/// Two managers editing over the LAN is the normal case in a branch, not an
/// exotic one. The current row comes back with the refusal so the screen can
/// show what changed underneath rather than just refusing.
class EditedElsewhere extends AdminRefusal {
  const EditedElsewhere(this.currentRevision);

  final int currentRevision;
}

/// This terminal has no branch database, so there is nothing to administer.
///
/// A refusal rather than a thrown error, because the Management screen is
/// reachable from a till that is mid-setup and the honest answer there is a
/// panel explaining what is missing — not a crash, and certainly not an empty
/// staff list that looks like a restaurant with nobody in it.
/// No administrator database password has been supplied this session.
///
/// Distinct from [NotPermitted], and the distinction is the whole point: the
/// person may well hold the capability, and the till may well be configured.
/// What is missing is the *database* credential the back office runs on, which
/// is asked for when Management opens and is never written to disk — the till's
/// own credential holds SELECT and nothing more, deliberately.
/// The values do not make sense, in a way the database cannot see.
///
/// `price_minor >= 0` is a CHECK constraint; "the offer price is above the
/// normal price" is not, and could not usefully be — so it is refused here,
/// carrying the sentence to show rather than a code to look up.
class CatalogInvalid extends AdminRefusal {
  const CatalogInvalid(this.reason);

  final String reason;
}

class AdministratorCredentialRequired extends AdminRefusal {
  const AdministratorCredentialRequired();
}

class NoDatabaseConfigured extends AdminRefusal {
  const NoDatabaseConfigured();
}

/// The outcome of an administrative write.
class AdminResult<T> {
  const AdminResult.done(T this.value) : refusal = null;
  const AdminResult.refused(AdminRefusal this.refusal) : value = null;

  final T? value;
  final AdminRefusal? refusal;

  bool get succeeded => refusal == null;
}

/// What the audit ledger records, as it is read back.
///
/// Names as well as ids, because the row has to still make sense when the
/// person has been renamed or the product deleted — which is exactly when
/// somebody goes looking.
class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.entityType,
    required this.actorName,
    required this.occurredAt,
    this.id,
    this.actorId,
    this.approvedByName,
    this.approvedById,
    this.entityId,
    this.before,
    this.after,
    this.reason,
  });

  final int? id;

  /// `staff.created`, `role.capabilities_changed`, `receipt.reprinted` — see
  /// [AuditAction].
  final String action;

  final String entityType;
  final String? entityId;

  final int? actorId;
  final String actorName;

  /// The supervisor who lent a permission for this one action, if any.
  final int? approvedById;
  final String? approvedByName;

  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final String? reason;
  final DateTime occurredAt;

  bool get wasOverridden => approvedById != null;
}

/// The action names, so a report can group by them.
///
/// Strings rather than an enum: an audit row written by a newer build must be
/// readable by an older one, and an enum would make an unrecognised action a
/// crash instead of a row that reads a little opaquely.
abstract final class AuditAction {
  static const staffCreated = 'staff.created';
  static const staffUpdated = 'staff.updated';
  static const staffDisabled = 'staff.disabled';
  static const staffReactivated = 'staff.reactivated';
  static const staffPinReset = 'staff.pin_reset';
  static const staffRoleChanged = 'staff.role_changed';

  /// Extra roles, per-person exceptions or a ceiling changed (§105, §16).
  /// Its own action rather than a generic update, because "who gave this
  /// person the right to refund" is the question an investigation asks.
  static const staffGrantsChanged = 'staff.grants_changed';

  static const roleCreated = 'role.created';
  static const roleUpdated = 'role.updated';
  static const roleDeleted = 'role.deleted';

  static const permissionOverridden = 'permission.overridden';

  static const shiftOpened = 'shift.opened';
  static const shiftClosed = 'shift.closed';
  static const receiptReprinted = 'receipt.reprinted';

  // Authoring the menu. Only an offline till writes these: on a cloud terminal
  // the platform is the author and the local catalogue is a cache the
  // bootstrap seeder overwrites.
  static const categoryCreated = 'category.created';
  static const categoryUpdated = 'category.updated';
  static const categoryArchived = 'category.archived';
  static const categoryRestored = 'category.restored';

  static const productCreated = 'product.created';
  static const productUpdated = 'product.updated';
  static const productArchived = 'product.archived';
  static const productRestored = 'product.restored';

  /// A price change is called out from an ordinary edit, because "who changed
  /// what this costs, and when" is the question a disputed receipt asks.
  static const productRepriced = 'product.repriced';

  /// Changing the service charge or the tax rate. Its own action for the same
  /// reason a reprice is: it changes what every future customer pays.
  static const moneyConfigChanged = 'money_config.changed';

  /// Who the receipt says sold the food — trade name, registration number,
  /// branch address. Its own action because it changes what a legal document
  /// claims, and the registration number is the field a receipt is judged on.
  static const receiptProfileChanged = 'receipt_profile.changed';

  static const tableCreated = 'table.created';
  static const tableUpdated = 'table.updated';
  static const tableArchived = 'table.archived';
  static const tableRestored = 'table.restored';

  static const entityStaff = 'staff';
  static const entityRole = 'role';
  static const entityShift = 'shift';
  static const entityOrder = 'order';
  static const entityCategory = 'category';
  static const entityProduct = 'product';
  static const entityMoney = 'money_config';
  static const entityTable = 'table';
  static const entityReceiptProfile = 'receipt_profile';
}

/// Authoring the menu on the till itself.
///
/// **Offline only, and the gate is not a preference.**
/// `BootstrapSeeder._seedCatalog` DELETEs the whole catalogue and re-inserts
/// the platform's rows, so anything authored locally on a CLOUD till is
/// destroyed by its next bundle. The platform is the single author there, and
/// the coordination docs say so in as many words — including "do not build a
/// merge path for data with one author". An offline restaurant has no platform
/// to be that author, which is the only reason this exists.
///
/// Nothing here deletes. Categories and products are archived, because
/// `pos_products.category_id` is `ON DELETE RESTRICT` and because a row that
/// ever appeared on a receipt is a record of what somebody bought.
/// Reading and writing who the receipt says sold the food.
///
/// Separate from [CatalogAdminRepository] because every till reads it — the
/// slip is printed at the counter — while only Management writes it. Folding
/// it into the catalogue repository would have meant a cloud till, which has
/// no catalogue authoring at all, losing the ability to print its own address.
abstract interface class ReceiptProfileRepository {
  Future<ReceiptProfile> load();

  Future<AdminResult<ReceiptProfile>> save(
    ReceiptProfile profile, {
    required PosStaff by,
  });
}

abstract interface class CatalogAdminRepository {
  /// Create or update a category. Id `0` is a new one.
  Future<AdminResult<Category>> saveCategory(
    Category category, {
    required PosStaff by,
  });

  /// Take a category off the rail without touching its products or their
  /// history. [restore] puts it back.
  Future<AdminResult<Category>> archiveCategory(
    Category category, {
    required PosStaff by,
    bool restore = false,
  });

  /// Create or update a product. Id `0` is a new one.
  ///
  /// A changed price is audited as [AuditAction.productRepriced] rather than a
  /// plain update, and the audit row carries the old and new minor amounts.
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  });

  /// Stop selling it. The tile disappears; every past sale still names it.
  Future<AdminResult<Product>> archiveProduct(
    Product product, {
    required PosStaff by,
    bool restore = false,
  });

  /// Apply a whole spreadsheet at once.
  ///
  /// **One transaction, or nothing.** Half a menu is worse than none: the
  /// operator cannot tell which half landed, and re-running the file would
  /// double what did.
  ///
  /// Categories named in the plan that do not exist are created first, because
  /// a product cannot be written without one.
  ///
  /// Nothing is ever deleted. A product missing from the file is one the
  /// restaurant did not mention, not one it wants gone.
  ///
  /// Gated on `catalog.manage`, like every other menu write, and audited: a
  /// bulk import that changed four hundred prices with no record of who ran it
  /// is the single largest unattributed change this product can make.
  Future<AdminResult<MenuImportOutcome>> importMenu(
    MenuImportPlan plan, {
    required PosStaff by,
  });

  /// What the restaurant charges on top of the food.
  ///
  /// Offline only, and for the same reason as the menu: on a cloud till the
  /// platform authors tax (POS-BE-013) and the bootstrap seeder overwrites
  /// this row. An offline till that never writes it silently prices from a
  /// hardcoded 12% / 14% and discloses `deviceConfig` on every receipt — which
  /// is honest, and wrong for almost every restaurant.
  ///
  /// Gated on `settings.manage`, not `catalog.manage`: what a plate costs and
  /// what the government takes are different jobs.
  Future<AdminResult<TaxConfig>> saveMoneyConfig(
    TaxConfig config, {
    required PosStaff by,
  });

  /// A table on the floor. Id `0` is a new one.
  ///
  /// Labels are unique per branch — `(branch_id, label)` — because the label is
  /// what a waiter says out loud, and two tables called 6 is an argument at the
  /// pass. Seats must be positive; the database checks that too.
  ///
  /// Gated on `settings.manage`: the floor plan is the room, not the menu.
  Future<AdminResult<DiningTable>> saveTable(
    DiningTable table, {
    required PosStaff by,
  });

  /// Take a table out of service. Never deleted — parked tickets and past
  /// orders name the row.
  Future<AdminResult<DiningTable>> archiveTable(
    DiningTable table, {
    required PosStaff by,
    bool restore = false,
  });

  /// Which modifier groups a product offers, in the order shown.
  ///
  /// Replaces the whole set rather than diffing it: the caller holds the list
  /// the operator just arranged, and a partial update would need the previous
  /// one to be correct.
  Future<AdminResult<void>> attachModifierGroups(
    int productId,
    List<int> groupIds, {
    required PosStaff by,
  });
}

/// The roles a restaurant defines, and what each may do.
abstract interface class RolesRepository {
  Future<List<PosRole>> all();

  /// Create or update. [by] must hold `staff.manage`.
  ///
  /// A role with id `0` is a new one; anything else is an edit, checked against
  /// [PosRole.id].
  Future<AdminResult<PosRole>> save(PosRole role, {required PosStaff by});

  /// Refused while anybody still holds it, and always for a system role.
  Future<AdminResult<void>> delete(PosRole role, {required PosStaff by});
}

/// Everyone who works here, as the Management section edits them.
///
/// Distinct from `SessionRepository`, which answers *who is at this till right
/// now* and is readable by the selling credential. This one writes, and is
/// reachable only through the administrator credential.
abstract interface class StaffDirectoryRepository {
  Future<List<PosStaff>> all({bool includeInactive = true});

  /// The person holding [pin], or null. Used by the override prompt, so it must
  /// work with no network and must not say *which* PIN was wrong.
  Future<PosStaff?> byPin(String pin);

  Future<AdminResult<PosStaff>> create({
    required PosStaff by,
    required String name,
    required String username,
    required String pin,
    required int roleId,
    int? branchId,
    Set<String> directGrants = const {},
  });

  Future<AdminResult<PosStaff>> update({
    required PosStaff by,
    required int staffId,
    String? name,
    String? username,
    int? roleId,
    Set<String>? directGrants,
    int? branchId,
  });

  /// Disabled, never deleted. A member of staff who left is still the person
  /// named on last March's shifts.
  Future<AdminResult<PosStaff>> setActive({
    required PosStaff by,
    required int staffId,
    required bool isActive,
  });

  /// The new PIN is never returned or logged — only that it was reset, by whom,
  /// and for whom.
  Future<AdminResult<void>> resetPin({
    required PosStaff by,
    required int staffId,
    required String pin,
  });

  /// One person's exceptions to their roles, and their ceilings (§105, §16).
  ///
  /// **Replaces, rather than merging.** The editor holds the whole picture —
  /// every extra role, every override, every ceiling — so a partial write would
  /// mean the screen and the table could disagree about what was intended by an
  /// absence. Passing an empty set is how something is removed, and that has to
  /// be expressible.
  ///
  /// The three travel together for the same reason: a manager granting somebody
  /// a refund permission and a refund ceiling in one sitting must not be able to
  /// end up with the first written and the second not.
  Future<AdminResult<PosStaff>> setGrants({
    required PosStaff by,
    required int staffId,
    required Set<int> extraRoleIds,
    required List<PermissionOverride> overrides,
    required Map<String, PermissionLimit> limits,
  });
}

/// The ledger. Append-only, enforced by the database as well as by this
/// interface having no update or delete on it.
abstract interface class AuditRepository {
  Future<void> record({
    required PosStaff by,
    required String action,
    required String entityType,
    PosStaff? approvedBy,
    String? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
  });

  /// Newest first. [entityType] and [entityId] together answer "everything that
  /// happened to this product"; [staffId] answers "everything this person did".
  Future<List<AuditEntry>> recent({
    int limit = 100,
    String? entityType,
    String? entityId,
    int? staffId,
  });
}


/// What an import actually did.
class MenuImportOutcome {
  const MenuImportOutcome({
    required this.categoriesCreated,
    required this.productsCreated,
    required this.productsUpdated,
  });

  final int categoriesCreated;
  final int productsCreated;
  final int productsUpdated;

  int get total => productsCreated + productsUpdated;
}
