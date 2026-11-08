import '../../core/money/quantity.dart';
import '../../core/security/pin_hash.dart' show PasswordProblem;
import '../models/backup.dart';
import '../models/catalog.dart';
import '../models/combo_draft.dart';
import '../services/stock_costing.dart' show OpeningCostProblem;
import '../models/option_group.dart';
import '../models/purchase_order.dart';
import '../models/tax.dart';
import '../models/order_type_config.dart';
import '../services/menu_import.dart';
import '../models/dining_table.dart';
import '../models/held_sync.dart';
import '../models/permissions.dart';
import '../models/receipt_profile.dart';
import '../models/shift.dart';
import '../models/tender_method.dart';
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

/// A restaurant has one owner, and it already has one.
///
/// Counted among ACTIVE staff, which is what keeps ownership transferable:
/// disable the current owner, then appoint the new one. Counting every row
/// would have made the first owner the owner forever — nobody is ever deleted
/// here — and the only way to sell the restaurant would be a psql prompt.
///
/// Named, like [RoleStillHeld], because "there is already an owner" sends a
/// manager looking for them and the name is the row they are looking for.
/// Migration 42 refuses the same thing in the database, for the writers that
/// do not come through here.
class OwnerAlreadyExists extends AdminRefusal {
  const OwnerAlreadyExists(this.ownerName);

  final String ownerName;
}

/// The owner's own role and permissions are not editable.
///
/// Extra roles and ALLOW overrides on somebody who already holds everything
/// mean nothing, and a DENY override on them is how a restaurant locks itself
/// out of the screen that would take it off. Moving the active owner to
/// another role is refused for the second reason: it is ownership given away
/// in a dropdown. Handing over is two deliberate acts — disable, appoint —
/// and neither of them is this one.
class OwnerIsFixed extends AdminRefusal {
  const OwnerIsFixed();
}

/// Owner is somebody's job, never an extra role on top of another one.
///
/// Refused even when there is no owner at the moment. An extra role is a way
/// of *adding* permissions, and owning the restaurant is not an addition —
/// a manager-who-is-also-owner would count as the owner for the one-owner
/// rule while the staff list said "Manager". Choosing Owner as their role says
/// what it means.
class OwnerIsNotAnExtraRole extends AdminRefusal {
  const OwnerIsNotAnExtraRole();
}

/// Only the owner sets the owner's PIN.
///
/// Whoever holds that PIN holds the restaurant: it opens Admin Mode, and every
/// permission the owner has comes with it. A manager able to reset it could
/// set one, sign in as the owner, and act under their name — so `staff.manage`
/// reaches everybody's PIN but this one. Applies to anybody on the owner role,
/// active or not: otherwise disable, reset, re-enable would be the way round.
///
/// Held in the repository, not a trigger, because the database cannot tell
/// who is asking. The installer and the cloud seeder write the owner's PIN
/// legitimately, and neither is a person.
class OwnerPinIsTheirs extends AdminRefusal {
  const OwnerPinIsTheirs();
}

/// Nobody clears the owner's Admin Mode password from Management — not a
/// manager, not the owner.
///
/// Clearing a password puts the account back on its PIN for one Admin Mode
/// entry, and whoever types that PIN first chooses the new password. For the
/// owner that is the restaurant: a manager who knew the owner's PIN (it is
/// four digits, typed at the counter all day) could clear, sign in, and own
/// the back office under the owner's name. And the owner has no need — they
/// are signed in with the password they would be clearing. A forgotten one
/// is a technician's job, with the back-office database password typed at
/// the door; see `AdminSessionController.technicianClearPassword`.
class OwnerPasswordIsTheirs extends AdminRefusal {
  const OwnerPasswordIsTheirs();
}

/// The password breaks `PasswordPolicy`'s rule, for [problem]. Asked by the
/// form and again by the write, so a second writer cannot skip it.
class PasswordRejected extends AdminRefusal {
  const PasswordRejected(this.problem);

  final PasswordProblem problem;
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
/// is kept in the operating system's secret store (`adminDbSecretStoreProvider`)
/// and loaded only when Admin Mode opens — asked for at the door when it is not
/// there, or no longer works. The till's own credential holds SELECT and
/// nothing more, deliberately.
/// The values do not make sense, in a way the database cannot see.
///
/// Carries the sentence to show rather than a code to look up — which is why
/// items, categories and option groups no longer use it: see
/// [CatalogRefused] and [OptionGroupRefused].
class CatalogInvalid extends AdminRefusal {
  const CatalogInvalid(this.reason);

  final String reason;
}

/// An item or a category broke one of the rules the editor checks before the
/// database is asked — [CatalogProblem] says which.
///
/// `price_minor >= 0` is a CHECK constraint; "the offer price is above the
/// normal price" is not, and could not usefully be — so it is refused here,
/// as a code the screen words in its own language.
class CatalogRefused extends AdminRefusal {
  const CatalogRefused(this.problem);

  final CatalogProblem problem;
}

/// An opening cost cannot be set — [OpeningCostProblem] says why.
///
/// Its own refusal, like [ComboRefused], so each language words it and a reason
/// added to the enum is a compile error in the message table.
class OpeningCostRefused extends AdminRefusal {
  const OpeningCostRefused(this.problem);

  final OpeningCostProblem problem;
}

/// A combo broke one of [ComboRules] — [ComboProblem] says which.
///
/// Its own refusal, like [OptionGroupRefused], so each language words it and a
/// problem added to the enum is a compile error in the message table.
class ComboRefused extends AdminRefusal {
  const ComboRefused(this.problem);

  final ComboProblem problem;
}

/// A size or extra, or an item's list of them, broke one of the option-group
/// rules — [OptionGroupProblem] says which.
///
/// Its own refusal rather than a [CatalogInvalid] with a sentence in it: that
/// one carries finished English, which an Arabic back office then showed as
/// it was. [names] are what the sentence has to name — the group, the item,
/// or every set of sizes an item would end up with — kept apart from the
/// wording so each language can put them where its grammar wants them.
class OptionGroupRefused extends AdminRefusal {
  const OptionGroupRefused(this.problem, {this.names = const []});

  final OptionGroupProblem problem;
  final List<String> names;
}

class AdministratorCredentialRequired extends AdminRefusal {
  const AdministratorCredentialRequired();
}

class NoDatabaseConfigured extends AdminRefusal {
  const NoDatabaseConfigured();
}

/// The platform owns this record, so editing it here would not last.
///
/// **A refusal rather than a silent overwrite.** On a cloud till the bootstrap
/// bundle is authoritative for some rows and not others, and the difference is
/// invisible from the screen: `BootstrapSeeder` upserts `pos_staff` and
/// deactivates anyone the bundle does not name, so a cashier added in the back
/// office is switched off by the next sync — with no error and nothing to
/// read. It does **not** touch `pos_roles`, `pos_staff.role_id`, or Wave C's
/// grant tables, so assigning somebody a role locally is permanent and correct.
///
/// [what] is the thing that is owned elsewhere, so the message can say where to
/// go rather than only that the door is shut.
class ManagedByPlatform extends AdminRefusal {
  const ManagedByPlatform(this.what);

  /// One of [staffRecords], [theCatalogue], [theFloor], [moneyRules].
  final String what;

  static const staffRecords = 'staff';
  static const theCatalogue = 'catalogue';
  static const theFloor = 'floor';
  static const moneyRules = 'money';
}

/// The purchase order cannot move the way it was asked to, for one of
/// `PurchaseEngine`'s reasons.
///
/// A wrapper, like [RoleNotAllowed], rather than a second copy of the reasons:
/// the engine decides, the repository asks it again against the row it has
/// just locked, and one set of reasons means one set of sentences. Asking the
/// screen's copy of the order instead is what let a part-received order be
/// cancelled — the Cancel button was drawn before the goods arrived.
class PurchaseRefused extends AdminRefusal {
  const PurchaseRefused(this.reason);

  final PurchaseRefusal reason;
}

/// Stock of this item is held in one unit, and this would count it in another.
///
/// **Refused, never converted.** Nothing in this product knows how many kilos
/// are in a box, and before this existed receiving added 5 kg to 10 boxes and
/// stored 15 kg — a stock figure and an average cost that are both wrong, and
/// wrong in a way no screen shows. Said by receiving, of a delivery in the
/// other unit, and by both item editors, of a unit change while stock is held.
/// Migration 44 refuses both in the database, for the writers that do not come
/// through here.
class StockHeldInAnotherUnit extends AdminRefusal {
  const StockHeldInAnotherUnit({
    required this.item,
    required this.held,
    required this.asked,
  });

  final String item;

  /// How much is held, in the unit it is held in — which is the unit it has to
  /// stay in until none is left.
  final Quantity held;

  final QuantityUnit asked;
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

  /// Somebody chose their Admin Mode password — the first time, after their
  /// PIN let them through the door once. Never the value, nor its hash.
  static const staffPasswordSet = 'staff.password_set';

  /// An Admin Mode password taken away, so the next entry is by PIN and asks
  /// for a new one. By a manager from Management, or by a technician at the
  /// door with the database password — the row's actor says which, and a
  /// technician's row has no staff id because no member of staff did it.
  static const staffPasswordCleared = 'staff.password_cleared';

  /// The actor name on a row nobody on the staff wrote: the technician reset.
  /// Not an action (no dot), so the labels test does not mistake it for one.
  static const technicianActor = 'technician';
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

  /// Which size and extras groups an item offers, or their order, changed.
  /// Its own action because the first size group prices the item, so moving
  /// one above another can change what the tile says.
  static const productOptionsChanged = 'product.options_changed';

  /// A size or extras group created or edited — in the library, or on the one
  /// item it was typed on.
  static const optionGroupSaved = 'option_group.saved';

  /// An option that already existed now costs something else. Called out for
  /// a product reprice's reason: a size's price IS the item's price, and "who
  /// changed what a Large costs" is the question a disputed receipt asks.
  static const optionGroupRepriced = 'option_group.repriced';

  /// Taken out of the library, or off the one item it was typed on. The row
  /// carries what the group offered, because afterwards nothing else does.
  static const optionGroupDeleted = 'option_group.deleted';

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
  static const entityOptionGroup = 'option_group';
  static const entityMoney = 'money_config';
  static const entityTenderType = 'tender_type';
  static const entityOrderType = 'order_type';
  static const entityTaxGroup = 'tax_group';
  static const entityCombo = 'combo';
  static const entityServiceCharge = 'service_charge';
  static const entityUnit = 'unit';
  static const entitySupplier = 'supplier';
  static const entityPurchaseOrder = 'purchase_order';
  static const entitySupplierInvoice = 'supplier_invoice';
  static const entitySupplierPayment = 'supplier_payment';

  /// A purchase order sent, cancelled or closed. Its own action because it is
  /// a commitment to spend money, and "who sent this and when" is what a
  /// disputed delivery asks.
  static const purchaseOrderStatusChanged = 'purchase_order.status_changed';

  /// Goods booked in. Its own action because it is the moment a cost price
  /// changes, and every margin afterwards is measured against it.
  static const stockReceived = 'stock.received';

  /// An item's first cost set by hand. Its own action for the reason receiving
  /// is one: it is the moment a cost price appears, and every margin measured
  /// against it afterwards asks who said so.
  static const stockCostSet = 'stock.cost_set';

  /// An invoice entered, corrected or voided. Its own action because it is the
  /// moment a debt comes into existence, and a voided invoice is the shape a
  /// purchasing fraud takes: enter twice, pay once, keep the difference.
  static const supplierInvoiceSaved = 'supplier_invoice.saved';
  static const supplierInvoiceVoided = 'supplier_invoice.voided';

  /// Money paid out. The single most audited act in the back office — "who
  /// authorised this and against what" is the whole question — so a payment and
  /// its reversal are separate actions rather than one with a flag.
  static const supplierPaid = 'supplier.paid';
  static const supplierPaymentVoided = 'supplier_payment.voided';

  /// A supplier added, edited or retired. Its own action because a supplier is
  /// where money leaves the business, and "who added this account" is the
  /// first question a fraud review asks.
  static const supplierSaved = 'supplier.saved';

  /// A service charge added, retired or repriced (§38). Its own action for the
  /// same reason a product reprice has one: it changes what every future
  /// customer pays, and "who added 12% and when" is what a complaint asks.
  static const serviceChargeSaved = 'service_charge.saved';
  static const unitSaved = 'unit.saved';
  static const stockItemSaved = 'stock_item.saved';

  /// A payment method created, renamed, retired or reclassified (§40).
  /// Its own action because changing `counts_as_cash` changes what every
  /// future cash-up expects to find in the drawer.
  static const tenderTypeSaved = 'tender_type.saved';

  /// A named rate added, repriced or retired (§17). Its own action because
  /// changing a rate changes what every product in that group costs, and a
  /// filing is reconciled against the rate that was charged on the day.
  static const taxGroupSaved = 'tax_group.saved';

  /// A combo made, edited, repriced or retired. Its own action for the reason
  /// a product reprice has one: its price is what every future meal costs, and
  /// "who made the meal deal 85" is what a margin review asks.
  static const comboSaved = 'combo.saved';

  /// An order type renamed, retired, or its requirements changed (§31). Its own
  /// action because turning off *requires a table* changes what the floor plan
  /// is for, and turning off the type itself removes a way of selling.
  static const orderTypeSaved = 'order_type.saved';

  /// A copy of the database taken — or attempted. `backup.manage` is
  /// critical-risk, so both halves of it are on the ledger: this one is written
  /// for a failure as well as a success, because "we have been taking backups
  /// every night" and "we have been failing to take one every night" look
  /// identical from anywhere except here.
  static const backupTaken = 'backup.taken';

  /// The database replaced from a copy. The most destructive act the product
  /// offers, and the row for it necessarily lands in the *restored* database —
  /// see `BackupService.restore`, which explains why and what that costs.
  static const backupRestored = 'backup.restored';

  /// Admin Mode entered, left, locked by the inactivity timer, or refused.
  ///
  /// All four, because Admin Mode is a door, and a door's log that recorded
  /// only the openings could not say who tried it or who walked away from it
  /// open. A refusal is written only when the username and PIN were right and
  /// the person lacks `admin.enter` — a wrong PIN names nobody to write it
  /// against.
  static const adminEntered = 'admin.entered';
  static const adminExited = 'admin.exited';
  static const adminTimedOut = 'admin.timed_out';
  static const adminRefused = 'admin.refused';

  /// The door shut after too many wrong PINs in a row at one terminal. Written
  /// against the member of staff whose username was being tried, when it
  /// names one: a guessed-at account is what an owner reading this wants to
  /// know about.
  static const adminLockedOut = 'admin.locked_out';

  /// A held sync record put back in the queue (DATABASE_AND_SYNC D1/D2/D13).
  /// Its own action because it is a decision that a sale or a refund the
  /// platform refused should be offered to it again — and when the second
  /// refusal comes, "who pressed Retry, on what, and what did it say the first
  /// time" is the question. The row keeps the code and the error it cleared.
  static const syncRecordReleased = 'sync_record.released';

  /// This till's LAN encryption turned off, or back on by pairing with a
  /// certificate (ADR-006 slice C). Its own action because "who let this till
  /// send the database password in the clear, and when" is exactly what a
  /// leaked password asks, and the override has no other record. Written on
  /// the connection as it was *before* the change, and the change is refused
  /// when the row cannot be written. `before`/`after` carry the transport and
  /// the pinned fingerprint — never a password, never key material.
  static const lanEncryptionChanged = 'terminal.lan_encryption_changed';

  static const entityAdminSession = 'admin_session';

  /// This till. The entity id is its terminal id.
  static const entityTerminal = 'terminal';

  /// An outbox row; the entity id is `<table>:<id>`, because the two outbox
  /// tables number their rows independently.
  static const entitySyncRecord = 'sync_record';
  static const entityTable = 'table';
  static const entityReceiptProfile = 'receipt_profile';
  static const entityBackup = 'backup';
}

/// The records the drain has held for a person, and putting one back.
///
/// **Release, never delete, never edit.** A held sale is money that changed
/// hands; the only thing a person can usefully decide from the till is "try it
/// again" — after the product came back on the platform, the tender was
/// synced, the customer was created. Anything that edits the record itself
/// would be a till rewriting a sale after the fact, which is what the outbox's
/// no-DELETE grant exists to stop. The cure for a record that is wrong is on
/// the platform, or with support.
///
/// Releasing clears `quarantined_at`, `quarantine_code` and `last_error` in the
/// same transaction as the audit row; the caller then kicks the drain. If the
/// platform refuses again it is held again, with the new answer — so the worst
/// a mistaken Retry costs is one conversation with the platform, and a §007
/// idempotency key makes even an accepted resend safe.
///
/// Gated on `terminal.manage`: the queue is this till's, like its printer and
/// its setup. Asked here as well as on the button, as every write is.
abstract interface class SyncQueueRepository {
  /// Every held record, newest first.
  Future<List<HeldSyncItem>> listHeldSync();

  /// How many there are — the number the Sync pane shows next to the unsent
  /// count, and that is *not* in it.
  Future<int> heldSyncCount();

  /// Put [item] back in the queue. Refused with [EditedElsewhere] when it is no
  /// longer held — somebody on another till pressed Retry first, or the drain
  /// already had it back.
  Future<AdminResult<HeldSyncItem>> releaseHeldSync(
    HeldSyncItem item, {
    required PosStaff by,
  });
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
  /// Author a payment method (§40).
  ///
  /// `id == 0` creates. There is no delete: a method is retired with
  /// `isActive`, because a settled payment names it and a receipt reprinted
  /// next year still has to say what the customer paid with.
  Future<AdminResult<TenderMethod>> saveTenderType(
    TenderMethod method, {
    required PosStaff by,
  });

  /// A named rate (§17).
  ///
  /// `id == 0` creates. No delete: a group a product points at cannot be removed
  /// without silently reclassifying that product, so it is retired with
  /// `isActive` — and the default one cannot even be retired.
  Future<AdminResult<TaxGroup>> saveTaxGroup(
    TaxGroup group, {
    required PosStaff by,
  });

  /// What a kind of order requires (§31).
  ///
  /// **No create and no delete**, unlike almost everything else here. The codes
  /// are an `OrderType` enum and the four of them are seeded: a fifth would have
  /// no name to render, because every place that shows an order type reads it off
  /// the enum. So this edits the four — their names, what they require, and
  /// whether the branch offers them at all.
  Future<AdminResult<OrderTypeConfig>> saveOrderType(
    OrderTypeConfig config, {
    required PosStaff by,
  });

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

  /// Lay the floor out in this order. Tables not named keep their place.
  ///
  /// The floor screen draws tiles in `sort_order`, so this is how a manager
  /// puts the window tables first and the terrace after the bar. Ids are
  /// given in the order wanted; the repository numbers them.
  Future<AdminResult<void>> reorderTables(
    List<int> tableIdsInOrder, {
    required PosStaff by,
  });

  /// Which modifier groups a product offers, in the order shown, by id.
  ///
  /// The ids form of [setProductOptionGroups], and kept for its callers: a
  /// library group's id is linked, the product's own groups are kept as they
  /// are, and anything else is refused with that method's reasons — including
  /// a group typed on another item, which linking would have quietly made
  /// shared.
  Future<AdminResult<void>> attachModifierGroups(
    int productId,
    List<int> groupIds, {
    required PosStaff by,
  });

  // ── sizes and extras ──────────────────────────────────────────────────────
  //
  // Authored the way the platform authors them (`OptionGroupController`,
  // `MenuItemController::syncOptionGroups`), with two of its behaviours
  // deliberately not copied: options keep their ids across a save, and an
  // item is never given two sets of sizes. Both are explained where they are
  // held, in `PostgresCatalogAdminRepository`.

  /// The restaurant's library — every shared group, with its options, its
  /// scope and how many items it reaches. By name, as the platform lists it.
  Future<List<LibraryGroup>> optionLibrary();

  /// The groups an item carries itself, in its order: library groups linked
  /// to it, by id, and the ones typed on it, whole.
  ///
  /// Not the groups that reach it by category or everywhere — those are not
  /// the item's to arrange, and [optionLibrary] says which they are.
  Future<List<OptionGroupRef>> productOptionGroups(int productId);

  /// Create or update a library group. Id `0` is a new one.
  ///
  /// The platform's rules, normalised first (see
  /// [OptionGroupDraft.normalized]) and then checked
  /// ([OptionGroupRules.refusal]); the repository adds what only the database
  /// knows — that the categories are this restaurant's, that the options are
  /// this group's, that nobody saved it since it was read, and that no item
  /// ends up with two sets of sizes. Changing the scope away from chosen items
  /// removes its item links, and away from categories its category links.
  ///
  /// Options are matched by id: updated in place, added, or removed — never
  /// recreated. A group typed on one item is refused here; it is saved with
  /// its item through [setProductOptionGroups].
  Future<AdminResult<OptionGroupDraft>> saveOptionGroup(
    OptionGroupDraft group, {
    required PosStaff by,
  });

  /// Take a group out of the library. Every item it was on loses it.
  Future<AdminResult<void>> deleteOptionGroup(
    OptionGroupDraft group, {
    required PosStaff by,
  });

  /// Replace the groups an item carries with [groups], in that order.
  ///
  /// A shared entry must be a library group that reaches items by link. An
  /// inline entry is written as this item's own; one the item had and the
  /// list no longer names is deleted. Returns the list as stored, with the
  /// ids of anything new.
  Future<AdminResult<List<OptionGroupRef>>> setProductOptionGroups(
    int productId,
    List<OptionGroupRef> groups, {
    required PosStaff by,
  });

  // ── combos ────────────────────────────────────────────────────────────────

  /// Every combo, retired ones included, as the editor holds them.
  ///
  /// Not the till's list: [CatalogRepository.load] feeds a cashier's grid and
  /// a manager needs to find the combo they switched off last month.
  Future<List<ComboDraft>> combos();

  /// Create or update a combo with its groups and options. Id `0` is new.
  ///
  /// **One transaction, and the whole tree.** Groups and options are matched
  /// by id: updated in place, added, or removed — never recreated, so a group
  /// keeps its id across a save. A product that is not this restaurant's is
  /// refused rather than written.
  ///
  /// There is no delete: retire it with `isAvailable`. An order line names the
  /// combo and a reprint must still say what was sold.
  ///
  /// Gated on `catalog.manage`, like the menu it appears on, and offline only
  /// for the same reason: on a cloud till the bootstrap seeder rewrites the
  /// catalogue.
  Future<AdminResult<ComboDraft>> saveCombo(
    ComboDraft combo, {
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

  /// Who has an Admin Mode password, by staff id (ADR-006b slice D).
  ///
  /// Read on the till's connection, like [all]. **Empty, not an error, on a
  /// database migration 55 has not reached** — the column does not exist yet,
  /// which is exactly "nobody has one", and the upgrade that adds it runs at
  /// the same door that asks.
  Future<Set<int>> withPassword();

  /// [by] chooses their own Admin Mode password. Only ever their own: nobody
  /// sets a password for somebody else, so nobody knows another person's.
  ///
  /// Checked against `PasswordPolicy` here as well as on the form, hashed
  /// with `PasswordHash` (600 000 iterations), written on the administrator
  /// connection and audited as [AuditAction.staffPasswordSet] — the row says
  /// that it was set, never what to. Not refused on a cloud till: the column
  /// is local and the bootstrap seeder never writes it, so unlike a PIN it is
  /// not overwritten by the next bundle.
  Future<AdminResult<void>> setOwnPassword({
    required PosStaff by,
    required String password,
  });

  /// Takes [staffId]'s Admin Mode password away (`staff.manage`). Their next
  /// entry is by PIN, and they must choose a new password before it opens.
  /// Refused for the owner — see [OwnerPasswordIsTheirs].
  Future<AdminResult<void>> clearPassword({
    required PosStaff by,
    required int staffId,
  });

  /// The technician's reset: clears the password of the active member of
  /// staff called [username], owner included, with no member of staff
  /// signed in.
  ///
  /// Only on a repository built on the administrator credential the
  /// technician has just typed — the authority here is knowing the database
  /// password, not holding a role. The value is the name of whose password
  /// was cleared, or null when [username] names nobody active with one.
  Future<AdminResult<String?>> clearPasswordAsTechnician({
    required String username,
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

/// The list of copies taken of this database.
///
/// **Append-only, like the audit ledger, and for the same reason.** A backup
/// that failed verification is a record that the restaurant did not have a
/// backup that night, and a row somebody can quietly correct is not a record.
/// The database holds that too — see migration 37 — so this interface having no
/// update and no delete is the second line rather than the only one.
///
/// Deliberately **not** gated on `backup.manage` inside the repository. The
/// automatic copy at day close is written by a till on which nobody has signed
/// into the back office, and refusing it there would mean the only nights with
/// a record are the nights a manager happened to be standing at the machine.
/// The screen that *takes* one on demand is gated, which is where the decision
/// is actually being made.
abstract interface class BackupRepository {
  /// Newest first.
  Future<List<BackupRecord>> recent({int limit = 50});

  /// Write the attempt down. Returns the stored row, with its id.
  Future<BackupRecord> record(BackupRecord entry, {required PosStaff by});
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
