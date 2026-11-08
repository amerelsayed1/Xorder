import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/postgres/postgres_tender_types_repository.dart';
import 'package:shared_module/domain/models/financial_account.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/admin_pane_bits.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_accounts_pane.dart';

/// Finance › Accounts on screen (XORD-015, stage 1).
///
/// What matters: an offline till authors accounts and the account each payment
/// method pays into; a cloud till is told they are the platform's and is given
/// nothing to press; a refusal is worded, in the language of the screen; and the
/// pane never claims money is booked to an account.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Mona',
    capabilities: {PosCapability.financeAccounts},
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  late _Ledger ledger;

  Future<void> pump(
    WidgetTester tester, {
    required bool authors,
    List<FinancialAccount> accounts = const [],
    List<TenderAccountDefault> defaults = const [],
    List<PosBranch> branches = const [],
    String locale = 'en',
  }) async {
    ledger = _Ledger(
      accounts: accounts,
      defaults: defaults,
      branches: branches,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financialAccountsRepositoryProvider.overrideWithValue(ledger),
          financialAccountsAdminRepositoryProvider.overrideWithValue(
            authors ? ledger : null,
          ),
          tenderTypesRepositoryProvider.overrideWithValue(
            const UnconfiguredTenderTypesRepository(),
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ManagementAccountsPane(admin: owner)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const bank = FinancialAccount(
    id: 1,
    name: 'Company bank',
    kind: AccountKind.bank,
    referenceLabel: 'CIB 4521',
  );
  const drawer = FinancialAccount(
    id: 2,
    name: 'Maadi drawer',
    kind: AccountKind.cash,
    branchId: 10,
  );
  const maadi = PosBranch(id: 10, name: 'Maadi');
  const zamalek = PosBranch(id: 11, name: 'Zamalek');

  group('an offline till', () {
    testWidgets('lists the accounts and offers to add one', (tester) async {
      await pump(
        tester,
        authors: true,
        accounts: [bank, drawer],
        branches: [maadi],
      );

      // Each account is listed once; its name also appears as a choice under
      // every payment method, so the list row is found by its own key.
      for (final (id, name) in [(1, 'Company bank'), (2, 'Maadi drawer')]) {
        expect(
          find.descendant(
            of: find.byKey(Key('account-$id')),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }
      expect(find.textContaining('Bank · All branches'), findsOneWidget);
      expect(find.textContaining('Cash · Maadi'), findsOneWidget);
      expect(find.text('CIB 4521'), findsOneWidget);
      expect(find.byKey(const Key('account-new')), findsOneWidget);
      expect(find.byType(PlatformOwnedNotice), findsNothing);
    });

    testWidgets('says plainly that nothing is booked to an account yet', (
      tester,
    ) async {
      await pump(tester, authors: true);

      // The thing an owner will otherwise assume. It is in the blurb under the
      // title, not buried.
      expect(
        find.textContaining('Nothing is booked to an account yet'),
        findsOneWidget,
      );
    });

    testWidgets('with none yet, says so and says what to do', (tester) async {
      await pump(tester, authors: true);

      expect(find.byKey(const Key('accounts-none')), findsOneWidget);
      expect(find.text('No accounts yet'), findsOneWidget);
    });

    testWidgets('adds one through the dialog', (tester) async {
      await pump(tester, authors: true, branches: [maadi, zamalek]);

      await tester.tap(find.byKey(const Key('account-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-name')),
        '  Petty cash  ',
      );
      await tester.tap(find.byKey(const Key('account-kind-cash')));
      await tester.tap(find.byKey(const Key('account-branch-10')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();

      final saved = ledger.saved.single;
      expect(saved.id, 0, reason: 'a new one');
      expect(saved.name, 'Petty cash', reason: 'trimmed by the repository');
      expect(saved.kind, AccountKind.cash);
      expect(saved.branchId, 10);
      expect(
        find.descendant(
          of: find.byKey(const Key('account-100')),
          matching: find.text('Petty cash'),
        ),
        findsOneWidget,
        reason: 'the list reloads',
      );
    });

    testWidgets('with one branch there is no branch to tie an account to', (
      tester,
    ) async {
      // A branch account could never be a payment method's default there, so
      // the choice is not offered. See FinancialAccountDialog.
      await pump(tester, authors: true, branches: [maadi]);

      await tester.tap(find.byKey(const Key('account-new')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-branch-all')), findsNothing);
      expect(find.byKey(const Key('account-kind-bank')), findsOneWidget);
    });

    testWidgets('but an account already tied to a branch can be re-tied', (
      tester,
    ) async {
      await pump(tester, authors: true, accounts: [drawer], branches: [maadi]);

      await tester.tap(find.byKey(const Key('account-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-branch-all')), findsOneWidget);
      expect(find.byKey(const Key('account-branch-10')), findsOneWidget);
    });

    testWidgets('a broken rule keeps the dialog open on what was typed', (
      tester,
    ) async {
      await pump(tester, authors: true, accounts: [bank]);
      ledger.refuse = const AccountRefused(AccountProblem.nameTaken);

      await tester.tap(find.byKey(const Key('account-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Company bank',
      );
      await tester.enterText(
        find.byKey(const Key('account-reference')),
        'CIB 4521',
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();

      // Still open, still holding what the person typed, with the reason inside.
      expect(
        tester.widget<Text>(find.byKey(const Key('account-notice'))).data,
        contains('already have an account'),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('account-name')))
            .controller!
            .text,
        'Company bank',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('account-reference')))
            .controller!
            .text,
        'CIB 4521',
      );
      expect(ledger.saved, isEmpty, reason: 'nothing was stored');

      // Fixed and sent again, it goes through and the dialog closes.
      ledger.refuse = null;
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Company bank 2',
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-notice')), findsNothing);
      expect(ledger.saved.single.name, 'Company bank 2');
      expect(ledger.saved.single.referenceLabel, 'CIB 4521');
    });

    testWidgets('a refusal that is not a broken rule is said on the pane', (
      tester,
    ) async {
      await pump(tester, authors: true);
      ledger.refuse = const NotPermitted(PosCapability.financeAccounts);

      await tester.tap(find.byKey(const Key('account-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Petty cash',
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-notice')), findsNothing);
      expect(find.byKey(const Key('accounts-note')), findsOneWidget);
    });

    testWidgets('sets where a payment method pays in, and clears it', (
      tester,
    ) async {
      await pump(tester, authors: true, accounts: [bank, drawer]);

      // Card is method 2 in the seeded four. Only the shared account is
      // offered for the whole business: the drawer belongs to a branch.
      expect(find.byKey(const Key('default-2-all-1')), findsOneWidget);
      expect(find.byKey(const Key('default-2-all-2')), findsNothing);

      await tester.tap(find.byKey(const Key('default-2-all-1')));
      await tester.pumpAndSettle();
      expect(ledger.defaultsSet, [(2, null, 1)]);

      await tester.tap(find.byKey(const Key('default-2-all-none')));
      await tester.pumpAndSettle();
      expect(ledger.defaultsSet.last, (2, null, null));
    });

    testWidgets('with several branches, each can have its own', (tester) async {
      await pump(
        tester,
        authors: true,
        accounts: [bank, drawer],
        branches: [maadi, zamalek],
      );

      // Cash (1) pays into a cash account: Maadi its own drawer, Zamalek none
      // (the drawer is Maadi's). Card (2) pays into a bank: the shared bank at
      // either branch, and never a drawer.
      expect(find.byKey(const Key('default-1-10-2')), findsOneWidget);
      expect(find.byKey(const Key('default-1-10-1')), findsNothing);
      expect(find.byKey(const Key('default-1-11-2')), findsNothing);
      expect(find.byKey(const Key('default-1-11-1')), findsNothing);
      expect(find.byKey(const Key('default-2-10-1')), findsOneWidget);
      expect(find.byKey(const Key('default-2-11-1')), findsOneWidget);
      expect(find.byKey(const Key('default-2-10-2')), findsNothing);

      await tester.tap(find.byKey(const Key('default-1-10-2')));
      await tester.pumpAndSettle();
      expect(ledger.defaultsSet, [(1, 10, 2)]);
    });

    testWidgets(
      'a choice already made is the highlighted one and is not re-sent',
      (tester) async {
        await pump(
          tester,
          authors: true,
          accounts: [bank],
          defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 1)],
        );

        await tester.tap(find.byKey(const Key('default-2-all-1')));
        await tester.pumpAndSettle();

        expect(ledger.defaultsSet, isEmpty);
      },
    );
  });

  group('a cloud till', () {
    testWidgets(
      'is told these are the platform\'s, and given nothing to press',
      (tester) async {
        await pump(tester, authors: false, accounts: [bank, drawer]);

        expect(find.byType(PlatformOwnedNotice), findsOneWidget);
        expect(find.textContaining('dashboard'), findsOneWidget);
        expect(
          find.byKey(const Key('account-new')),
          findsNothing,
          reason: 'a button that cannot save is a lie',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('account-1')),
            matching: find.text('Company bank'),
          ),
          findsOneWidget,
        );

        final row = tester.widget<InkWell>(find.byKey(const Key('account-1')));
        expect(row.onTap, isNull, reason: 'listed, and not operable');
      },
    );

    testWidgets('shows where each method pays in, in words', (tester) async {
      await pump(
        tester,
        authors: false,
        accounts: [bank],
        defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 1)],
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('default-text-2-all'))).data,
        contains('Company bank'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('default-text-1-all'))).data,
        contains('No account'),
        reason: 'a method with none says so',
      );
      expect(find.byKey(const Key('default-2-all-1')), findsNothing);
    });

    testWidgets('a switched-off default still shows by name', (tester) async {
      await pump(
        tester,
        authors: false,
        accounts: [bank.copyWith(isActive: false)],
        defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 1)],
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('default-text-2-all'))).data,
        contains('Company bank'),
      );
    });
  });

  group('in Arabic', () {
    testWidgets('the screen is worded, mirrored and lays out', (tester) async {
      await pump(
        tester,
        authors: true,
        accounts: [bank, drawer],
        branches: [maadi, zamalek],
        locale: 'ar',
      );

      expect(find.text('الحسابات'), findsWidgets);
      expect(find.text('إضافة حساب'), findsOneWidget);
      expect(find.textContaining('بنكي'), findsWidgets);
      expect(
        Directionality.of(tester.element(find.byType(ManagementAccountsPane))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('each payment method offers only accounts of its own kind', () {
    const safe = FinancialAccount(id: 3, name: 'Safe', kind: AccountKind.cash);
    const wallet = FinancialAccount(
      id: 4,
      name: 'Wallet',
      kind: AccountKind.wallet,
    );

    testWidgets('cash → cash, card → bank, wallet → wallet; no natural type → '
        'every account', (tester) async {
      await pump(tester, authors: true, accounts: [bank, safe, wallet]);

      Finder choice(int method, int account) =>
          find.byKey(Key('default-$method-all-$account'));

      // Cash (1).
      expect(choice(1, 3), findsOneWidget);
      expect(choice(1, 1), findsNothing);
      expect(choice(1, 4), findsNothing);
      // Card (2).
      expect(choice(2, 1), findsOneWidget);
      expect(choice(2, 3), findsNothing);
      expect(choice(2, 4), findsNothing);
      // Wallet (3).
      expect(choice(3, 4), findsOneWidget);
      expect(choice(3, 1), findsNothing);
      expect(choice(3, 3), findsNothing);
      // "No account" is always there.
      for (final method in [1, 2, 3]) {
        expect(
          find.byKey(Key('default-$method-all-none')),
          findsOneWidget,
          reason: 'method $method',
        );
      }
    });

    testWidgets('a pairing saved before the rule is kept and marked, and the '
        'choices are the fitting ones', (tester) async {
      await pump(
        tester,
        authors: true,
        accounts: [bank, safe],
        defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 3)],
      );

      final marker = find.byKey(const Key('default-mismatch-2-all'));
      expect(marker, findsOneWidget);
      expect(
        find.descendant(of: marker, matching: find.textContaining('Safe')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: marker,
          matching: find.textContaining('Does not match'),
        ),
        findsOneWidget,
      );
      // Not cleared, and not offered again: the bank is.
      expect(ledger.defaultsSet, isEmpty);
      expect(find.byKey(const Key('default-2-all-3')), findsNothing);
      expect(find.byKey(const Key('default-2-all-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('default-2-all-1')));
      await tester.pumpAndSettle();
      expect(ledger.defaultsSet, [(2, null, 1)]);
    });

    testWidgets('a cloud till shows the same marker, read-only',
        (tester) async {
      await pump(
        tester,
        authors: false,
        accounts: [bank, safe],
        defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 3)],
      );

      expect(find.byKey(const Key('default-mismatch-2-all')), findsOneWidget);
      expect(find.byKey(const Key('default-2-all-1')), findsNothing);
    });

    testWidgets('no account of the needed kind: says which one to add',
        (tester) async {
      await pump(tester, authors: true, accounts: [bank]);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('default-none-fit-1-all')))
            .data,
        contains('Cash'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('default-none-fit-3-all')))
            .data,
        contains('Wallet'),
      );
      expect(find.byKey(const Key('default-none-fit-2-all')), findsNothing);
    });

    testWidgets('in Arabic the marker and the hint are Arabic', (tester) async {
      await pump(
        tester,
        authors: true,
        accounts: [bank, safe],
        defaults: [const TenderAccountDefault(tenderTypeId: 2, accountId: 3)],
        locale: 'ar',
      );

      expect(find.textContaining('لا يناسب وسيلة الدفع'), findsOneWidget);
      expect(find.textContaining('لا يوجد حساب'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

/// In-memory stand-in for both the till's read and Management's write, so the
/// pane reloads what it saved.
class _Ledger
    implements FinancialAccountsRepository, FinancialAccountsAdminRepository {
  _Ledger({
    required List<FinancialAccount> accounts,
    required List<TenderAccountDefault> defaults,
    required this._branches,
  }) : _accounts = [...accounts],
       _defaults = [...defaults];

  final List<FinancialAccount> _accounts;
  final List<TenderAccountDefault> _defaults;
  final List<PosBranch> _branches;

  final saved = <FinancialAccount>[];
  final defaultsSet = <(int, int?, int?)>[];
  AdminRefusal? refuse;

  @override
  Future<List<FinancialAccount>> accounts({
    bool includeInactive = false,
  }) async => [
    for (final a in _accounts)
      if (includeInactive || a.isActive) a,
  ];

  @override
  Future<List<TenderAccountDefault>> defaults() async => [..._defaults];

  @override
  Future<List<PosBranch>> branches() async => _branches;

  @override
  Future<AdminResult<FinancialAccount>> saveAccount(
    FinancialAccount account, {
    required PosStaff by,
  }) async {
    if (refuse != null) return AdminResult.refused(refuse!);
    final stored = FinancialAccount(
      id: account.id == 0 ? _accounts.length + 100 : account.id,
      name: account.name.trim(),
      kind: account.kind,
      branchId: account.branchId,
      referenceLabel: account.referenceLabel,
      isActive: account.isActive,
      sortOrder: account.sortOrder,
    );
    saved.add(account);
    _accounts
      ..removeWhere((a) => a.id == stored.id)
      ..add(stored);
    return AdminResult.done(stored);
  }

  @override
  Future<AdminResult<TenderAccountDefault?>> setDefault({
    required int tenderTypeId,
    required int? branchId,
    required int? accountId,
    required PosStaff by,
  }) async {
    if (refuse != null) return AdminResult.refused(refuse!);
    defaultsSet.add((tenderTypeId, branchId, accountId));
    _defaults.removeWhere(
      (d) => d.tenderTypeId == tenderTypeId && d.branchId == branchId,
    );
    if (accountId == null) return const AdminResult.done(null);
    final row = TenderAccountDefault(
      tenderTypeId: tenderTypeId,
      branchId: branchId,
      accountId: accountId,
    );
    _defaults.add(row);
    return AdminResult.done(row);
  }
}
