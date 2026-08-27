import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';

/// Placeholder data from the design prototype.
///
/// The handoff is explicit that the sample menu, prices, table numbers, the
/// staff name "Rana A." and the tenant "Mahsoub Grill" are **placeholder and
/// must come from the API**. They live here and nowhere else — no widget reads
/// a literal price or a tenant name.
///
/// These fakes exist because every backend contract the POS needs is still
/// `PROPOSED` (see `docs/coordination/BACKEND_TO_POS.md`). They are swapped for
/// `Api…` implementations one at a time as contracts reach `READY`.
Money _egp(int major, [int piastres = 0]) => Money(major * 100 + piastres);

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<Catalog> load({DateTime? since}) async {
    // A real network call has latency; simulating a little of it keeps the
    // loading states honest during development.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _catalog;
  }

  static final _doneness = ModifierGroup(
    id: 1,
    nameEn: 'Doneness',
    nameAr: 'درجة النضج',
    isRequired: true,
    maxSelect: 1,
    modifiers: [
      Modifier(id: 11, groupId: 1, nameEn: 'Medium', nameAr: 'متوسط', priceDelta: Money.zero),
      Modifier(id: 12, groupId: 1, nameEn: 'Well done', nameAr: 'ناضج', priceDelta: Money.zero),
      Modifier(id: 13, groupId: 1, nameEn: 'Rare', nameAr: 'نيء', priceDelta: Money.zero),
    ],
  );

  static final _extras = ModifierGroup(
    id: 2,
    nameEn: 'Extras',
    nameAr: 'إضافات',
    maxSelect: 3,
    modifiers: [
      Modifier(id: 21, groupId: 2, nameEn: 'Tahina', nameAr: 'طحينة', priceDelta: _egp(15)),
      Modifier(id: 22, groupId: 2, nameEn: 'Bread', nameAr: 'عيش', priceDelta: _egp(10)),
      Modifier(id: 23, groupId: 2, nameEn: 'Grilled veg', nameAr: 'خضار مشوي', priceDelta: _egp(35)),
      Modifier(id: 24, groupId: 2, nameEn: 'Rice', nameAr: 'أرز', priceDelta: _egp(25)),
    ],
  );

  static final _burgerAdd = ModifierGroup(
    id: 3,
    nameEn: 'Add',
    nameAr: 'أضف',
    maxSelect: 3,
    modifiers: [
      Modifier(id: 31, groupId: 3, nameEn: 'Cheese', nameAr: 'جبنة', priceDelta: _egp(15)),
      Modifier(id: 32, groupId: 3, nameEn: 'Bacon', nameAr: 'بيكون', priceDelta: _egp(20)),
      Modifier(id: 33, groupId: 3, nameEn: 'Jalapeño', nameAr: 'هالابينو', priceDelta: _egp(10)),
      Modifier(id: 34, groupId: 3, nameEn: 'Double', nameAr: 'دوبل', priceDelta: _egp(60)),
    ],
  );

  static final _burgerRemove = ModifierGroup(
    id: 4,
    nameEn: 'Remove',
    nameAr: 'بدون',
    maxSelect: 4,
    modifiers: [
      Modifier(id: 41, groupId: 4, nameEn: 'No onions', nameAr: 'بدون بصل', priceDelta: Money.zero),
      Modifier(id: 42, groupId: 4, nameEn: 'No pickles', nameAr: 'بدون مخلل', priceDelta: Money.zero),
      Modifier(id: 43, groupId: 4, nameEn: 'No sauce', nameAr: 'بدون صوص', priceDelta: Money.zero),
      Modifier(id: 44, groupId: 4, nameEn: 'No tomato', nameAr: 'بدون طماطم', priceDelta: Money.zero),
    ],
  );

  static final _catalog = Catalog(
    syncedAt: DateTime(2026, 8, 26, 9),
    modifierGroups: [_doneness, _extras, _burgerAdd, _burgerRemove],
    categories: const [
      Category(id: 1, nameEn: 'Grills', nameAr: 'مشويات', slug: 'grills', sortOrder: 1),
      Category(id: 2, nameEn: 'Sandwiches', nameAr: 'ساندويتشات', slug: 'sandwiches', sortOrder: 2),
      Category(id: 3, nameEn: 'Pizza', nameAr: 'بيتزا', slug: 'pizza', sortOrder: 3),
      Category(id: 4, nameEn: 'Sides', nameAr: 'جانبية', slug: 'sides', sortOrder: 4),
      Category(id: 5, nameEn: 'Drinks', nameAr: 'مشروبات', slug: 'drinks', sortOrder: 5),
      Category(id: 6, nameEn: 'Desserts', nameAr: 'حلويات', slug: 'desserts', sortOrder: 6),
      Category(id: 7, nameEn: 'Combos', nameAr: 'وجبات', slug: 'combos', sortOrder: 7),
    ],
    products: [
      Product(id: 101, categoryId: 1, nameEn: 'Mixed Grill Platter', nameAr: 'مشويات مشكلة',
          price: _egp(385), sku: 'GRL-001', barcode: '6221031492801', modifierGroupIds: const [1, 2]),
      Product(id: 102, categoryId: 1, nameEn: 'Kofta Plate', nameAr: 'كفتة',
          price: _egp(245), sku: 'GRL-002', barcode: '6221031492802', modifierGroupIds: const [1, 2]),
      Product(id: 103, categoryId: 1, nameEn: 'Shish Tawook', nameAr: 'شيش طاووق',
          price: _egp(265), sku: 'GRL-003', barcode: '6221031492803', modifierGroupIds: const [1, 2]),
      Product(id: 104, categoryId: 1, nameEn: 'Lamb Chops', nameAr: 'ريش ضاني',
          price: _egp(520), sku: 'GRL-004', modifierGroupIds: const [1, 2], isAvailable: false),
      Product(id: 201, categoryId: 2, nameEn: 'Beef Burger', nameAr: 'برجر لحم',
          price: _egp(180), sku: 'SND-001', barcode: '6221031492811', modifierGroupIds: const [3, 4]),
      Product(id: 202, categoryId: 2, nameEn: 'Chicken Shawarma', nameAr: 'شاورما فراخ',
          price: _egp(150), discountedPrice: _egp(135), sku: 'SND-002', modifierGroupIds: const [4]),
      Product(id: 203, categoryId: 2, nameEn: 'Hawawshi', nameAr: 'حواوشي',
          price: _egp(120), sku: 'SND-003'),
      Product(id: 301, categoryId: 3, nameEn: 'Margherita', nameAr: 'مارجريتا', price: _egp(210), sku: 'PZA-001'),
      Product(id: 302, categoryId: 3, nameEn: 'Pepperoni', nameAr: 'بيبروني', price: _egp(255), sku: 'PZA-002'),
      Product(id: 401, categoryId: 4, nameEn: 'Fries', nameAr: 'بطاطس', price: _egp(55), sku: 'SID-001'),
      Product(id: 402, categoryId: 4, nameEn: 'Tahina', nameAr: 'طحينة', price: _egp(30), sku: 'SID-002'),
      Product(id: 403, categoryId: 4, nameEn: 'Baladi Salad', nameAr: 'سلطة بلدي', price: _egp(45), sku: 'SID-003'),
      Product(id: 501, categoryId: 5, nameEn: 'Soft Drink', nameAr: 'مشروب غازي', price: _egp(25), sku: 'DRK-001'),
      Product(id: 502, categoryId: 5, nameEn: 'Fresh Lemon', nameAr: 'ليمون فريش', price: _egp(45), sku: 'DRK-002'),
      Product(id: 503, categoryId: 5, nameEn: 'Turkish Coffee', nameAr: 'قهوة تركي', price: _egp(35), sku: 'DRK-003'),
      Product(id: 601, categoryId: 6, nameEn: 'Om Ali', nameAr: 'أم علي', price: _egp(85), sku: 'DST-001'),
      Product(id: 602, categoryId: 6, nameEn: 'Rice Pudding', nameAr: 'أرز بلبن', price: _egp(65), sku: 'DST-002'),
      Product(id: 701, categoryId: 7, nameEn: 'Family Combo', nameAr: 'وجبة عائلية', price: _egp(890), sku: 'CMB-001'),
      Product(id: 702, categoryId: 7, nameEn: 'Solo Combo', nameAr: 'وجبة فردي', price: _egp(230), sku: 'CMB-002'),
    ],
  );
}

class FakeTablesRepository implements TablesRepository {
  @override
  Future<List<DiningTable>> liveFloor() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Seeded open tables from the prototype: T3, T4, T5(bill), T7, T12, T14(bill).
    return [
      const DiningTable(id: 1, label: 'T1', seats: 2),
      const DiningTable(id: 2, label: 'T2', seats: 4),
      DiningTable(id: 3, label: 'T3', seats: 4, state: TableState.open, openLineCount: 3, openTotal: _egp(742, 50)),
      DiningTable(id: 4, label: 'T4', seats: 6, state: TableState.open, openLineCount: 7, openTotal: _egp(1338, 68)),
      DiningTable(id: 5, label: 'T5', seats: 2, state: TableState.billAsked, openLineCount: 4, openTotal: _egp(1120)),
      const DiningTable(id: 6, label: 'T6', seats: 4),
      DiningTable(id: 7, label: 'T7', seats: 8, state: TableState.open, openLineCount: 5, openTotal: _egp(2105, 25)),
      const DiningTable(id: 8, label: 'T8', seats: 2),
      const DiningTable(id: 9, label: 'T9', seats: 4),
      const DiningTable(id: 10, label: 'T10', seats: 4),
      const DiningTable(id: 11, label: 'T11', seats: 2),
      DiningTable(id: 12, label: 'T12', seats: 4, state: TableState.open, openLineCount: 2, openTotal: _egp(430)),
      const DiningTable(id: 13, label: 'T13', seats: 6),
      DiningTable(id: 14, label: 'T14', seats: 4, state: TableState.billAsked, openLineCount: 6, openTotal: _egp(1655, 40)),
      const DiningTable(id: 15, label: 'T15', seats: 2),
      const DiningTable(id: 16, label: 'T16', seats: 4),
    ];
  }
}

class FakeSessionRepository implements SessionRepository {
  @override
  Future<PosSession> current() async => const PosSession(
        userName: 'Rana A.',
        tenantName: 'Mahsoub Grill',
        branchName: 'DOWNTOWN',
        terminalCode: 'T-02',
        shiftReference: 'SHIFT #419',
        capabilities: {
          'pos.operate',
          'pos.discount',
          'pos.shift_open',
          'pos.shift_close',
          'pos.cash_movement',
          'pos.reprint',
        },
      );

  /// The real implementation compares against a cached PIN hash so the lock
  /// screen works offline. This fake accepts one PIN.
  @override
  Future<bool> verifyPin(String pin) async => pin == '1234';

  @override
  Future<PosStaff?> signIn(String pin) async => pin == '1234'
      ? const PosStaff(id: 1, name: 'Rana A.', capabilities: {'pos.operate'})
      : null;
}

/// Holds one shift in memory. Enough for a widget test to walk open → close
/// without a database, and deliberately not enough for anything else.
class FakeShiftRepository implements ShiftRepository {
  PosShift? _open;

  @override
  Future<PosShift?> current() async => _open;

  @override
  Future<PosShift> open({required PosStaff by, required Money openingFloat}) async =>
      _open ??= PosShift(
        id: 1,
        openedAt: DateTime(2026),
        openingFloat: openingFloat,
        openedByName: by.name,
      );

  @override
  Future<ShiftSummary> summarise(PosShift shift) async => ShiftSummary(
        shift: shift,
        saleCount: 0,
        gross: Money.zero,
        tenders: const [],
      );

  @override
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
  }) async {
    final summary = await summarise(shift);
    _open = null;
    return ShiftClose(
      summary: summary,
      countedCash: countedCash,
      variance: summary.varianceAgainst(countedCash),
      closedAt: DateTime(2026),
    );
  }
}

/// Records submissions in memory and reports them as queued.
///
/// Deliberately never throws away a submission: "never silently discard an
/// unsynchronised transaction" is the rule the whole offline design serves.
class FakeOrdersRepository implements OrdersRepository {
  final List<Ticket> submitted = [];
  var _sequence = 1041;

  @override
  Future<SubmitOrderResult> submit(Ticket ticket) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Idempotent on the ticket id, exactly as the server contract requires: a
    // replay returns the original result rather than creating a second order.
    final existing = submitted.indexWhere((t) => t.id == ticket.id);
    if (existing >= 0) {
      return SubmitOrderResult(
        clientTransactionId: ticket.id,
        queued: true,
        invoiceNumber: 'POS-${_sequence - submitted.length + existing + 1}',
      );
    }

    submitted.add(ticket);
    _sequence++;
    return SubmitOrderResult(
      clientTransactionId: ticket.id,
      queued: true,
      invoiceNumber: 'POS-$_sequence',
    );
  }
}

class FakeBranchRepository implements BranchRepository {
  @override
  Future<List<PosBranch>> forTenant() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));

    return const [
      PosBranch(
        id: 12,
        name: 'Downtown',
        code: 'DWTN',
        supportedOrderTypes: ['dine_in', 'takeaway', 'delivery'],
      ),
      PosBranch(
        id: 13,
        name: 'Maadi',
        code: 'MAADI',
        supportedOrderTypes: ['dine_in', 'takeaway'],
      ),
      PosBranch(
        id: 14,
        name: 'Zamalek',
        code: 'ZMLK',
        supportedOrderTypes: ['dine_in', 'takeaway', 'delivery', 'drive_thru'],
      ),
    ];
  }
}


/// Stands in for POS-BE-023 until the claim endpoint exists.
///
/// Deliberately fails on some inputs rather than always succeeding: a wizard
/// whose fake never refuses is a wizard whose error path ships untested. The
/// codes match the vocabulary asked for in POS-BE-019.
class FakeProvisioningRepository implements ProvisioningRepository {
  /// The one code this fake accepts. Real codes are issued by the dashboard,
  /// single-use and short-lived.
  static const demoCode = 'MAADI-7Q42';

  final Set<String> _spent = <String>{};

  @override
  Future<ClaimResult> claimByCode({required String tenantSlug, required String code}) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));

    final normalised = code.trim().toUpperCase();
    if (normalised != demoCode) {
      return const ClaimResult(
        code: 'PAIRING_CODE_INVALID',
        message: 'That setup code was not recognised. Check it with whoever '
            'added this till in the dashboard.',
      );
    }
    if (!_spent.add(normalised)) {
      // A used code is a different problem from a wrong one, and saying so is
      // the difference between the operator retyping and asking for a new code.
      return const ClaimResult(
        code: 'PAIRING_CODE_SPENT',
        message: 'That setup code has already been used. Issue a new one from '
            'the dashboard.',
      );
    }

    return const ClaimResult(
      claim: TerminalClaim(
        terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
        terminalName: 'Counter 1',
        branchId: 13,
        branchName: 'Maadi',
        syncPolicy: SyncPolicy.automatic,
        restaurantId: 1,
        branchCode: 'MAADI',
      ),
    );
  }

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));

    if (username.trim().isEmpty || password.isEmpty) {
      return const ClaimResult(
        code: 'VALIDATION_FAILED',
        message: 'Enter the username and password of a staff account that may '
            'add a terminal.',
      );
    }

    return ClaimResult(
      claim: TerminalClaim(
        terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
        terminalName: terminalName,
        branchId: branchId,
        branchName: 'Maadi',
        syncPolicy: SyncPolicy.automatic,
        restaurantId: 1,
        branchCode: 'MAADI',
      ),
    );
  }
}

class FakeHardwarePorts implements HardwarePorts {
  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    return const [
      DiscoveredPrinter(name: 'EPSON TM-T20III', transport: 'usb'),
      DiscoveredPrinter(name: 'Kitchen — TM-U220 (192.168.1.44)', transport: 'network'),
    ];
  }

  @override
  Future<bool> testPrint(String printerName) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return true;
  }
}
