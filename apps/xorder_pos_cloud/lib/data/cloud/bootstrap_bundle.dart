/// The bootstrap bundle — everything a cloud terminal learns from the platform
/// in one document (POS-BE-023, `docs/coordination/BACKEND_TO_POS.md` §023).
///
/// Parsing is **tolerant by rule**: a missing block is an empty block, a wrong
/// type falls back, and nothing here ever throws on server data. A bundle this
/// build half-understands must still seed the half it does understand — the
/// alternative is a till that will not open because the platform learned a new
/// key (client rule 11: never throw on unexpected server data).
///
/// Every money field is an **integer in minor units** and every rate is basis
/// points, per the agreed cross-cutting convention (D1). A price arriving as a
/// JSON float is a contract violation and is dropped, not rounded — a wrong
/// price on a till is worse than a missing product.
library;

import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/financial_account.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/content_languages.dart';

/// One parsed key, or null — never an exception.
int? _asInt(Object? value) => switch (value) {
  final int v => v,
  // A numeric string is tolerated (PostgreSQL bigints serialise that way
  // through some PHP paths); a double is not — see the library comment.
  final String v => int.tryParse(v),
  _ => null,
};

/// The name a catalogue row goes by: English when it has one, otherwise the
/// Arabic one standing in for it.
///
/// The platform lets a business name a category or an item in one language
/// only — the dashboard and the diner's menu both resolve by locale and fall
/// back — and Good Cafe's whole menu is Arabic-only. The till used to require
/// `name_en` and drop every row without one, which dropped every category,
/// then every item under them, and the sale screen opened on "no matching
/// items" over a menu of forty-six (16 Oct 2026). Null only when the row is
/// nameless in both, which is the one case nothing can be sold under.
String? _nameOf(Map<String, Object?> json) =>
    _asString(json['name_en']) ?? _asString(json['name_ar']);

String? _asString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

bool _asBool(Object? value, {required bool orElse}) =>
    value is bool ? value : orElse;

DateTime? _asTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

List<Map<String, Object?>> _asMapList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) item.cast<String, Object?>(),
];

List<String> _asStringList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is String) item,
];

class BootstrapBusiness {
  const BootstrapBusiness({
    required this.id,
    required this.name,
    required this.slug,
    required this.currency,
    required this.exponent,
    this.nameAr,
    this.taxRegistrationNumber,
    this.defaultLanguage,
    this.contentLanguages,
  });

  final int id;
  final String name;
  final String? nameAr;
  final String slug;

  /// The language this business works in, as the dashboard has it — `en` or
  /// `ar` and nothing else.
  ///
  /// Null when the platform sent a language this build cannot render. That is
  /// deliberately not a fallback to English: a till that silently opened in a
  /// third language's name would be unreadable to the people using it, and the
  /// wizard's own default (Arabic, the businesses this ships to) is a better
  /// answer than a word the platform happened to send.
  final String? defaultLanguage;

  /// Which languages the platform says the menu is written in (XORD-005): the
  /// wire value `ar`, `en` or `both`, or null when the platform did not say.
  /// An older platform sends no `bilingual` at all, and null must leave what
  /// the till already has alone rather than reset it to `both`.
  final String? contentLanguages;

  /// Mandatory on the wire (A7). Defaulted here only so a malformed bundle
  /// still parses — the seeder refuses to seed money-bearing rows without them.
  final String currency;
  final int exponent;
  final String? taxRegistrationNumber;

  static BootstrapBusiness? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final id = _asInt(json['id']);
    final name = _asString(json['name']);
    final slug = _asString(json['slug']);
    if (id == null || name == null || slug == null) return null;
    return BootstrapBusiness(
      id: id,
      name: name,
      nameAr: _asString(json['name_ar']),
      slug: slug,
      currency: _asString(json['currency']) ?? 'EGP',
      exponent: _asInt(json['exponent']) ?? 2,
      taxRegistrationNumber: _asString(json['tax_registration_number']),
      defaultLanguage: switch (_asString(json['default_language'])) {
        'en' => 'en',
        'ar' => 'ar',
        _ => null,
      },
      contentLanguages: ContentLanguages.fromPlatform(
        bilingual: json['bilingual'] is bool ? json['bilingual'] as bool : null,
        defaultLanguage: _asString(json['default_language']),
      )?.wire,
    );
  }
}

/// The bundle's `branding` block (XORD-021). Only the logo is read: the display
/// name and accent colour the block also carries are not used by this build.
///
/// **A null [logoUrl] means "the business has no logo", but only when the
/// block was sent at all.** A platform that predates the key sends no block, and
/// [BootstrapBundle.branding] is then null, which leaves whatever logo the till
/// holds exactly as it is. The two must not be confused: one removes a logo,
/// the other says nothing about it.
class BootstrapBranding {
  const BootstrapBranding({this.logoUrl});

  /// Where the platform serves the logo, as it baked the address (an absolute
  /// URL), or null when the business has none.
  final String? logoUrl;

  static BootstrapBranding? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    return BootstrapBranding(logoUrl: _asString(json['logo_url']));
  }
}

class BootstrapTerminal {
  const BootstrapTerminal({
    required this.id,
    required this.name,
    required this.branchId,
    this.syncPolicy,
  });

  final String id;
  final String name;
  final int branchId;
  final String? syncPolicy;

  static BootstrapTerminal? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final id = _asString(json['id']);
    final branchId = _asInt(json['branch_id']);
    if (id == null || branchId == null) return null;
    return BootstrapTerminal(
      id: id,
      name: _asString(json['name']) ?? 'Terminal',
      branchId: branchId,
      syncPolicy: _asString(json['sync_policy']),
    );
  }
}

class BootstrapBranch {
  const BootstrapBranch({
    required this.id,
    required this.name,
    this.code,
    this.supportedOrderTypes = const [],
  });

  final int id;
  final String name;
  final String? code;
  final List<String> supportedOrderTypes;

  static BootstrapBranch? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _asString(json['name']);
    if (id == null || name == null) return null;
    return BootstrapBranch(
      id: id,
      name: name,
      code: _asString(json['code']),
      supportedOrderTypes: _asStringList(json['supported_order_types']),
    );
  }
}

class BootstrapCategory {
  const BootstrapCategory({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.slug,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final String? slug;
  final int sortOrder;
  final bool isActive;

  static BootstrapCategory? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _nameOf(json);
    if (id == null || name == null) return null;
    return BootstrapCategory(
      id: id,
      nameEn: name,
      nameAr: _asString(json['name_ar']),
      slug: _asString(json['slug']),
      sortOrder: _asInt(json['sort_order']) ?? 0,
      isActive: _asBool(json['is_active'], orElse: true),
    );
  }
}

class BootstrapProduct {
  const BootstrapProduct({
    required this.id,
    required this.categoryId,
    required this.nameEn,
    required this.priceMinor,
    this.nameAr,
    this.discountedPriceMinor,
    this.sku,
    this.barcode,
    this.isAvailable = true,
    this.sortOrder = 0,
    this.optionGroupIds = const [],
  });

  final int id;
  final int categoryId;
  final String nameEn;
  final String? nameAr;
  final int priceMinor;
  final int? discountedPriceMinor;
  final String? sku;
  final String? barcode;
  final bool isAvailable;
  final int sortOrder;
  final List<int> optionGroupIds;

  static BootstrapProduct? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final categoryId = _asInt(json['category_id']);
    final name = _nameOf(json);
    // A product whose price cannot be read as an integer is dropped whole. A
    // float here is the exact bug class D1 exists to prevent.
    final price = _asInt(json['price_minor']);
    if (id == null || categoryId == null || name == null || price == null) {
      return null;
    }
    return BootstrapProduct(
      id: id,
      categoryId: categoryId,
      nameEn: name,
      nameAr: _asString(json['name_ar']),
      priceMinor: price,
      discountedPriceMinor: _asInt(json['discounted_price_minor']),
      sku: _asString(json['sku']),
      barcode: _asString(json['barcode']),
      isAvailable: _asBool(json['is_available'], orElse: true),
      sortOrder: _asInt(json['sort_order']) ?? 0,
      optionGroupIds: [
        if (json['option_group_ids'] is List)
          for (final id in json['option_group_ids'] as List) ?_asInt(id),
      ],
    );
  }
}

class BootstrapOptionGroup {
  const BootstrapOptionGroup({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.isRequired = false,
    this.maxSelect = 1,
    this.isVariant = false,
    this.sortOrder = 0,
    this.options = const [],
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final bool isRequired;
  final int maxSelect;
  final bool isVariant;
  final int sortOrder;
  final List<BootstrapOption> options;

  static BootstrapOptionGroup? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _nameOf(json);
    if (id == null || name == null) return null;
    return BootstrapOptionGroup(
      id: id,
      nameEn: name,
      nameAr: _asString(json['name_ar']),
      isRequired: _asBool(json['is_required'], orElse: false),
      maxSelect: _asInt(json['max_select']) ?? 1,
      isVariant: _asBool(json['is_variant'], orElse: false),
      sortOrder: _asInt(json['sort_order']) ?? 0,
      options: [
        for (final option in _asMapList(json['options']))
          ?BootstrapOption.fromJson(option),
      ],
    );
  }
}

class BootstrapOption {
  const BootstrapOption({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.priceDeltaMinor = 0,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final int priceDeltaMinor;
  final bool isAvailable;
  final int sortOrder;

  static BootstrapOption? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _nameOf(json);
    if (id == null || name == null) return null;
    return BootstrapOption(
      id: id,
      nameEn: name,
      nameAr: _asString(json['name_ar']),
      priceDeltaMinor: _asInt(json['price_delta_minor']) ?? 0,
      isAvailable: _asBool(json['is_available'], orElse: true),
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }
}

class BootstrapTable {
  const BootstrapTable({
    required this.id,
    required this.branchId,
    required this.label,
    this.seats,
    this.areaName,
    this.isActive = true,
  });

  final int id;
  final int branchId;
  final String label;
  final int? seats;
  final String? areaName;
  final bool isActive;

  static BootstrapTable? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final branchId = _asInt(json['branch_id']);
    final label = _asString(json['label']);
    if (id == null || branchId == null || label == null) return null;
    return BootstrapTable(
      id: id,
      branchId: branchId,
      label: label,
      // Zero seats would trip the local CHECK constraint, so a non-positive
      // number is "not stated" rather than a crash — and not stated stays
      // null: the platform allows it, and a table is not a two-top by default.
      seats: switch (_asInt(json['seats'])) {
        final s? when s > 0 => s,
        _ => null,
      },
      areaName: _asString(json['area_name']),
      isActive: _asBool(json['is_active'], orElse: true),
    );
  }
}

/// One `receipt_profiles[]` row — who the receipt says sold the food, for one
/// branch (§023, "Amendment 2026-09-22 (A3)").
///
/// **Parsed straight into the domain's [ReceiptProfile], with no wire class in
/// between.** The platform copied the field names off `pos_receipt_profiles`
/// one for one precisely so this would be a mapping and not a translation
/// table, and every field lines up: `additional_info` is the till's column name
/// rather than ETA's `additionalInformation`, `governate` is their spelling on
/// both sides, and `revision` means the same thing in both places. A
/// `BootstrapReceiptProfile` beside it would be nineteen fields written out
/// twice — and the second copy is where the two drift.
///
/// A function rather than the file's usual `Bootstrap*.fromJson` statics,
/// because there is no class of ours to hang a static on. Kept private: the
/// bundle's `receiptProfiles` is the only reader.
///
/// Null means the row named no branch, which is the one thing nothing can be
/// keyed on — the same rule [BootstrapTable] applies. Everything else is
/// tolerated: the contract promises empty strings on every text field but the
/// two notes, and this build does not rely on that promise.
ReceiptProfile? _receiptProfile(Map<String, Object?> json) {
  final branchId = _asInt(json['branch_id']);
  if (branchId == null) return null;

  return ReceiptProfile(
    branchId: branchId,
    tradeName: _asString(json['trade_name']) ?? '',
    registrationNumber: _asString(json['registration_number']) ?? '',
    activityCode: _asString(json['activity_code']) ?? '',
    // ETA's branch code, NOT `branches.code` — that one is the invoice prefix
    // and arrives in the `branches` block. They are allowed to differ and
    // usually do.
    branchCode: _asString(json['branch_code']) ?? '',
    address: BranchAddress(
      // 'EG' rather than '' when the platform sends nothing: the column
      // defaults to it, a blank country is never the right answer, and the
      // contract says this is never blank anyway.
      country: _asString(json['country']) ?? 'EG',
      governate: _asString(json['governate']) ?? '',
      regionCity: _asString(json['region_city']) ?? '',
      street: _asString(json['street']) ?? '',
      buildingNumber: _asString(json['building_number']) ?? '',
      postalCode: _asString(json['postal_code']),
      floor: _asString(json['floor']),
      room: _asString(json['room']),
      landmark: _asString(json['landmark']),
      additionalInformation: _asString(json['additional_info']),
    ),
    phone: _asString(json['phone']),
    headerNote: _asString(json['header_note']),
    footerNote: _asString(json['footer_note']),
    // The platform's counter, taken verbatim rather than counted here. It is
    // the same number the dashboard's stale-save guard checks, and 0 carries
    // real news — "nobody has authored this branch yet, you are looking at a
    // projection of the business". A locally incremented copy would make the
    // two sides disagree about which save was first.
    revision: _asInt(json['revision']) ?? 0,
  );
}

/// A cashier PIN verifier, as agreed in the POS-BE-024 amendment: PBKDF2-HMAC-
/// SHA256, base64 salt and hash, iterations stated on the wire. Never the PIN.
class BootstrapPin {
  const BootstrapPin({
    required this.salt,
    required this.hash,
    this.iterations = 120000,
  });

  final String salt;
  final String hash;
  final int iterations;

  static BootstrapPin? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final salt = _asString(json['salt']);
    final hash = _asString(json['hash']);
    if (salt == null || hash == null) return null;
    return BootstrapPin(
      salt: salt,
      hash: hash,
      iterations: _asInt(json['iterations']) ?? 120000,
    );
  }
}

/// One row of the platform's customer directory.
class BootstrapCustomer {
  const BootstrapCustomer({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
  });

  /// The **platform customer id**, kept as `platform_id` so a sale uploaded
  /// later names the person the dashboard already knows.
  final int id;
  final String name;
  final String phone;
  final String? email;
  final String? address;

  /// Null for a row this build cannot use. A customer with no number cannot
  /// be found again by the only key the directory has, so it is dropped
  /// rather than seeded into a table whose unique index would reject it.
  static BootstrapCustomer? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final phone = '${json['phone'] ?? ''}'.trim();
    if (id is! int || phone.isEmpty) return null;

    return BootstrapCustomer(
      id: id,
      name: '${json['name'] ?? ''}'.trim(),
      phone: phone,
      email: json['email'] as String?,
      address: json['address'] as String?,
    );
  }
}

class BootstrapStaff {
  const BootstrapStaff({
    required this.id,
    required this.name,
    required this.username,
    this.capabilities = const [],
    this.isActive = true,
    this.pin,
  });

  /// The **platform user id**. Seeded verbatim so the rows this till writes
  /// attribute to the same person the dashboard knows.
  final int id;
  final String name;
  final String username;
  final List<String> capabilities;
  final bool isActive;

  /// Null means this person cannot sign in offline — stated in the contract,
  /// not invented here.
  final BootstrapPin? pin;

  static BootstrapStaff? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _asString(json['name']);
    if (id == null || name == null) return null;
    return BootstrapStaff(
      id: id,
      name: name,
      username: _asString(json['username']) ?? 'user-$id',
      capabilities: _asStringList(json['capabilities']),
      isActive: _asBool(json['is_active'], orElse: true),
      pin: BootstrapPin.fromJson(
        json['pin'] is Map
            ? (json['pin'] as Map).cast<String, Object?>()
            : null,
      ),
    );
  }
}

/// One payment method, as POS-BE-013 delivers it inside `money.tender_types`:
/// `{id, name, kind, is_active, sort_order}` and nothing else. The flags the
/// till needs beyond these are derived by the seeder, not read from here.
class BootstrapTenderType {
  const BootstrapTenderType({
    required this.id,
    required this.name,
    this.kind,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// The **platform** tender id — what the drain must send.
  final int id;
  final String name;

  /// Null when the platform sent a kind this build does not know.
  final PlatformTenderKind? kind;
  final bool isActive;
  final int sortOrder;

  static BootstrapTenderType? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    if (id == null) return null;
    return BootstrapTenderType(
      id: id,
      // A nameless tender is still one the owner created and may be taking
      // money on. Dropping it would retire the row on the next seed; a plain
      // label keeps it takeable and makes the gap obvious on the button.
      name: _asString(json['name']) ?? 'Payment method $id',
      kind: PlatformTenderKind.fromWire(_asString(json['kind'])),
      isActive: _asBool(json['is_active'], orElse: true),
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }
}

/// One financial account, as XORD-015 delivers it inside
/// `money.financial_accounts`:
/// `{id, name, kind, currency, branch_id, reference_label, is_active, sort_order}`.
///
/// **A proposed contract until the ledger says READY** (`BACKEND_TO_POS.md`);
/// an older platform sends no such key and the seeder then leaves the table
/// alone.
class BootstrapFinancialAccount {
  const BootstrapFinancialAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.branchId,
    this.currency,
    this.referenceLabel,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// The **platform** account id, kept as the local primary key.
  final int id;
  final String name;
  final AccountKind kind;

  /// The branch this account belongs to, or null for one the whole business
  /// shares. Branch ids are the platform's, kept verbatim as `pos_branches.id`.
  final int? branchId;
  final String? currency;
  final String? referenceLabel;
  final bool isActive;
  final int sortOrder;

  /// Null for a row this build cannot hold: no id, no name, or a kind it does
  /// not know. Skipped, never guessed — an account shown as the wrong sort of
  /// place is worse than one not shown yet.
  static BootstrapFinancialAccount? fromJson(Map<String, Object?> json) {
    final id = _asInt(json['id']);
    final name = _asString(json['name']);
    final kind = AccountKind.fromWire(_asString(json['kind']));
    if (id == null || name == null || name.trim().isEmpty || kind == null) {
      return null;
    }
    return BootstrapFinancialAccount(
      id: id,
      name: name.trim(),
      kind: kind,
      branchId: _asInt(json['branch_id']),
      currency: _asString(json['currency']),
      referenceLabel: _asString(json['reference_label']),
      isActive: _asBool(json['is_active'], orElse: true),
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }
}

/// One entry of `money.tender_account_defaults`:
/// `{tender_type_id, branch_id, financial_account_id}`, all PLATFORM ids.
/// `branch_id` null is the business-wide fallback.
class BootstrapTenderAccountDefault {
  const BootstrapTenderAccountDefault({
    required this.tenderTypeId,
    required this.accountId,
    this.branchId,
  });

  final int tenderTypeId;
  final int? branchId;
  final int accountId;

  static BootstrapTenderAccountDefault? fromJson(Map<String, Object?> json) {
    final tender = _asInt(json['tender_type_id']);
    final account = _asInt(json['financial_account_id']);
    if (tender == null || account == null) return null;
    return BootstrapTenderAccountDefault(
      tenderTypeId: tender,
      accountId: account,
      branchId: _asInt(json['branch_id']),
    );
  }
}

/// The whole document.
class BootstrapBundle {
  const BootstrapBundle({
    required this.configVersion,
    this.syncedAt,
    this.serverTime,
    this.business,
    this.terminal,
    this.branches = const [],
    this.categories = const [],
    this.products = const [],
    this.optionGroups = const [],
    this.tables = const [],
    this.staff = const [],
    this.customers = const [],
    this.receiptProfiles = const [],
    this.money = const {},
    this.invoice = const {},
    this.licence,
    this.branding,
  });

  /// The client's sole precedence signal (§025): accept iff newer than cached.
  final int configVersion;
  final DateTime? syncedAt;
  final DateTime? serverTime;
  final BootstrapBusiness? business;
  final BootstrapTerminal? terminal;
  final List<BootstrapBranch> branches;
  final List<BootstrapCategory> categories;
  final List<BootstrapProduct> products;
  final List<BootstrapOptionGroup> optionGroups;
  final List<BootstrapTable> tables;
  final List<BootstrapStaff> staff;

  /// The customer directory, so a cashier can find a regular with no internet
  /// (POS-BE-014, owner decision 27 Sep 2026).
  ///
  /// **Capped by the platform, newest first**, because a directory is
  /// unbounded and a bootstrap is downloaded on every config change. Anyone
  /// older is still reachable by entering them again: the number is the
  /// identity, so the platform resolves it back to the same person rather
  /// than creating a second.
  ///
  /// **Empty is "this platform predates the key", not "no customers"** — the
  /// same reading `receiptProfiles` takes, and for the same reason: blanking a
  /// directory a till has already been given would lose customers it created
  /// at the counter and has not yet uploaded.
  final List<BootstrapCustomer> customers;

  /// Who the receipt says sold the food, one row per active branch (A3).
  ///
  /// **Empty is not "no profiles", it is "this platform predates A3".** Older
  /// deployments send no such key, and the seeder leaves the table alone on an
  /// empty list for that reason: blanking what a till already prints with would
  /// reintroduce the exact bug this key closes.
  final List<ReceiptProfile> receiptProfiles;

  /// Tax rules, charges and tender types (§013). Kept as raw JSON until the
  /// till computes tax from server rules — persisting them unparsed means a
  /// rule shape this build predates still round-trips intact.
  final Map<String, Object?> money;
  final Map<String, Object?> invoice;

  /// `{payload, signature, key_id}` when the tenant holds one (POS-BE-015).
  final Map<String, Object?>? licence;

  /// The business's branding, or null when this platform sends none (XORD-021).
  final BootstrapBranding? branding;

  /// The payment methods in [money], parsed.
  ///
  /// A reading of [money] rather than a field beside it: [money] stays the
  /// verbatim payload `pos_money_config` stores, and there is one copy of the
  /// truth rather than two that a hand-built bundle could make disagree.
  List<BootstrapTenderType> get tenderTypes => [
    for (final tender in _asMapList(money['tender_types']))
      ?BootstrapTenderType.fromJson(tender),
  ];

  /// Does this platform send financial accounts at all? **Absent is "this
  /// platform predates them", not "there are none"**: an older deployment sends
  /// no key, and the seeder then leaves what the till holds alone. A present
  /// but empty list is the platform saying the business has none.
  bool get sendsFinancialAccounts => money['financial_accounts'] is List;

  /// Same rule for the defaults.
  bool get sendsTenderAccountDefaults =>
      money['tender_account_defaults'] is List;

  /// The accounts in [money], parsed (XORD-015).
  List<BootstrapFinancialAccount> get financialAccounts => [
    for (final account in _asMapList(money['financial_accounts']))
      ?BootstrapFinancialAccount.fromJson(account),
  ];

  /// The default accounts in [money], parsed (XORD-015).
  List<BootstrapTenderAccountDefault> get tenderAccountDefaults => [
    for (final row in _asMapList(money['tender_account_defaults']))
      ?BootstrapTenderAccountDefault.fromJson(row),
  ];

  /// Can this bundle seed a database at all? The identity block is the floor:
  /// without knowing *which business this is*, seeding anything would write
  /// rows no query could ever scope.
  bool get seedable => business != null && terminal != null;

  static BootstrapBundle? tryParse(Object? body) {
    if (body is! Map) return null;
    final json = body.cast<String, Object?>();

    Map<String, Object?>? block(String key) =>
        json[key] is Map ? (json[key] as Map).cast<String, Object?>() : null;

    final catalog = block('catalog') ?? const <String, Object?>{};
    List<Map<String, Object?>> collection(String key) {
      final value = catalog[key];
      // Both the delta-sync envelope `{data: [...]}` and a bare list parse, so
      // the bundle and the standalone catalog endpoints can share one reader.
      if (value is Map) return _asMapList(value['data']);
      return _asMapList(value);
    }

    return BootstrapBundle(
      configVersion: _asInt(json['config_version']) ?? 0,
      syncedAt: _asTime(json['synced_at']),
      serverTime: _asTime(json['server_time']),
      business: BootstrapBusiness.fromJson(block('restaurant')),
      terminal: BootstrapTerminal.fromJson(block('terminal')),
      branches: [
        for (final branch in _asMapList(json['branches']))
          ?BootstrapBranch.fromJson(branch),
      ],
      categories: [
        for (final category in collection('categories'))
          ?BootstrapCategory.fromJson(category),
      ],
      products: [
        for (final product in collection('items'))
          ?BootstrapProduct.fromJson(product),
      ],
      optionGroups: [
        for (final group in collection('option_groups'))
          ?BootstrapOptionGroup.fromJson(group),
      ],
      tables: [
        for (final table in _asMapList(json['tables']))
          ?BootstrapTable.fromJson(table),
      ],
      customers: [
        for (final row in _asMapList(json['customers']))
          ?BootstrapCustomer.fromJson(row),
      ],
      staff: [
        for (final member in _asMapList(json['staff']))
          ?BootstrapStaff.fromJson(member),
      ],
      receiptProfiles: [
        for (final profile in _asMapList(json['receipt_profiles']))
          ?_receiptProfile(profile),
      ],
      money: block('money') ?? const {},
      invoice: block('invoice') ?? const {},
      licence: block('licence'),
      branding: BootstrapBranding.fromJson(block('branding')),
    );
  }
}
