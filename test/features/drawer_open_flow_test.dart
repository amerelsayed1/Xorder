import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/features/cash/presentation/cash_dialogs.dart';

/// Opening the drawer with no sale behind it (§23), and who is asked.
///
/// The audit (S3-1) watched the owner — signed in on a cloud till, holding
/// every capability the platform knows — being asked for a supervisor's PIN to
/// open their own drawer, on a keypad whose 0 key was half off the screen.
/// The platform's vocabulary has one drawer key, `pos.cash_movement`, and the
/// till splits it in two; a person the platform trusts with the drawer has to
/// arrive holding both halves, or the prompt asks for a permission nobody the
/// platform sent can give.
void main() {
  /// The standard desktop viewport the widget tests use.
  const desktop = Size(1440, 900);

  /// The owner as the bootstrap seeds them: the platform's `pos.*` strings,
  /// translated once on the way in, with no local role behind them.
  final owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    capabilities: PosCapability.canonicalAll(const [
      'pos.operate',
      'pos.shift_open',
      'pos.shift_close',
      'pos.cash_movement',
    ]),
  );

  /// Sells, and nothing about the drawer.
  const cashier = PosStaff(
    id: 2,
    name: 'Nour Adel',
    username: 'nour',
    capabilities: {PosCapability.operate, PosCapability.shiftOpen},
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = desktop;
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<_FakeCash> open(WidgetTester tester, {required PosStaff as}) async {
    final cash = _FakeCash();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashMovementsRepositoryProvider.overrideWithValue(cash),
          signedInStaffProvider.overrideWith(() => _SignedIn(as)),
          shiftProvider.overrideWith((ref) async => _openShift),
          businessDayProvider.overrideWith((ref) async => null),
          staffDirectoryRepositoryProvider.overrideWithValue(
            const _NobodyByPin(),
          ),
          auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
          hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => DrawerOpenFlow.run(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return cash;
  }

  group('who is asked', () {
    testWidgets('the owner is not asked for anybody\'s PIN', (tester) async {
      final cash = await open(tester, as: owner);

      // Straight to the confirmation that says the opening is recorded —
      // no supervisor prompt in between, because there is nothing to lend
      // to somebody who already holds it.
      expect(find.text('Supervisor approval'), findsNothing);
      expect(find.text('APPROVAL REQUIRED'), findsNothing);
      expect(find.text('Open the drawer?'), findsOneWidget);

      await tester.tap(find.text('Open drawer'));
      await tester.pumpAndSettle();

      expect(cash.recorded, hasLength(1));
      expect(cash.recorded.single.kind, CashMovementKind.drawerOpen);
      expect(cash.recorded.single.approval, isNull);
    });

    testWidgets('a cashier still brings a supervisor over', (tester) async {
      final cash = await open(tester, as: cashier);

      expect(find.text('Supervisor approval'), findsOneWidget);
      expect(find.text('APPROVAL REQUIRED'), findsOneWidget);
      // The act is named on the prompt, in the cashier's words — and the
      // confirmation that would record it has not been reached.
      expect(find.text('Open the drawer?'), findsOneWidget);
      expect(find.text('MANAGER PIN'), findsOneWidget);
      expect(cash.recorded, isEmpty);
    });
  });

  group('the keypad', () {
    testWidgets('is on screen whole at the desktop size', (tester) async {
      await open(tester, as: cashier);

      // The 0 key is the lowest one. Hit-testable means its centre is inside
      // the viewport and nothing is drawn over it — the footer included.
      final zero = find.widgetWithText(InkWell, '0');
      expect(zero.hitTestable(), findsOneWidget);

      final key = tester.getRect(zero.first);
      final dialog = tester.getRect(find.byType(Dialog));
      expect(key.bottom, lessThanOrEqualTo(dialog.bottom));
      expect(dialog.bottom, lessThanOrEqualTo(desktop.height));

      // And the keys are the design's size, not stretched to the dialog.
      expect(key.height, closeTo(PosSize.pinKey, 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('and every key takes a tap', (tester) async {
      await open(tester, as: cashier);

      for (final digit in ['7', '8', '9', '0']) {
        await tester.tap(find.widgetWithText(InkWell, digit).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Four digits in, so the approve button has come alive. It would not
      // have if the 0 had been under the footer.
      final approve = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Open drawer'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(approve.onTap, isNotNull);
    });
  });
}

final _openShift = PosShift(
  id: 3,
  openedAt: DateTime(2026, 10, 16, 9),
  openingFloat: const Money(20000),
  openedByName: 'Amer M.',
  openedById: 1,
);

class _SignedIn extends SignedInStaffController {
  _SignedIn(this.staff);

  final PosStaff staff;

  @override
  PosStaff? build() => staff;
}

class _FakeCash implements CashMovementsRepository {
  final recorded = <({CashMovementKind kind, Approval? approval})>[];

  @override
  Future<List<CashMovement>> forShift(int shiftId) async => const [];

  @override
  Future<List<CashMovement>> between(
    ReportFilter filter, {
    Set<CashMovementKind> kinds = const {CashMovementKind.payOut},
  }) async => const [];

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    Approval? approval,
    int? businessDayId,
  }) async {
    // The same question the real repository asks before it writes, so a
    // flow that skipped the prompt for somebody who may not skip it would
    // fail here rather than pass on a double that asks nothing.
    Authorization.require(
      by,
      kind == CashMovementKind.drawerOpen
          ? PosCapability.cashOpenWithoutSale
          : PosCapability.cashMovement,
      approval: approval,
    );
    recorded.add((kind: kind, approval: approval));
    return CashMovement(
      id: recorded.length,
      kind: kind,
      amount: amount,
      occurredAt: DateTime.utc(2026, 10, 16),
    );
  }
}

/// A directory nobody's PIN is in: the prompt is what is under test, not the
/// approval behind it.
class _NobodyByPin implements StaffDirectoryRepository {
  const _NobodyByPin();

  @override
  Future<PosStaff?> byPin(String pin) async => null;

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
