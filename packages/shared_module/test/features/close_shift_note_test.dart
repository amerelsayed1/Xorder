import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/pos_settings.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/shift/presentation/shift_dialogs.dart';

/// The note on a shift close.
///
/// The platform wants a reason with any close whose count differs from the
/// expected cash it worked out (audit, 17 Oct 2026), and the till had nowhere to
/// take one: `ShiftRepository.close` has long accepted a `note`, and nothing
/// ever passed it. The note is optional — most closes balance, and a field that
/// must be filled teaches everybody to type a full stop — but it is always
/// there, including for a cashier counting blind, who is exactly the person who
/// cannot see a variance and may still know why the drawer is short.
void main() {
  final shift = PosShift(
    id: 7,
    openedAt: DateTime(2026, 10, 16, 9),
    openingFloat: const Money(20000),
    openedByName: 'Amer M.',
    openedById: 1,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  late _RecordingShifts shifts;

  Future<void> open(
    WidgetTester tester, {
    String locale = 'en',
    CashPolicy policy = CashPolicy.defaults,
    bool cashier = false,
  }) async {
    shifts = _RecordingShifts();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shiftRepositoryProvider.overrideWithValue(shifts),
          auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
          cashPolicyProvider.overrideWithValue(policy),
          signedInStaffProvider.overrideWith(cashier ? _Cashier.new : _Owner.new),
          openTicketsProvider.overrideWith(_NothingParked.new),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CloseShiftDialog.show(context, shift: shift),
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
  }

  final noteField = find.byKey(const Key('close-shift-note'));

  /// Count the drawer and press the button. [closeLabel] is the button's text.
  Future<void> countAndClose(
    WidgetTester tester, {
    String counted = '200.00',
    String closeLabel = 'Close shift',
  }) async {
    await tester.enterText(find.byType(TextField).first, counted);
    await tester.pump();
    await tester.tap(find.text(closeLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog offers an optional note, labelled as such', (
    tester,
  ) async {
    await open(tester);

    expect(noteField, findsOneWidget);
    // MicroLabel sets English in capitals.
    expect(find.text('NOTE (OPTIONAL)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('what the cashier types goes to close() as the note, trimmed', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(noteField, '  Short 5 — change given twice  ');
    await countAndClose(tester);

    expect(shifts.closes, hasLength(1));
    expect(shifts.closes.single.note, 'Short 5 — change given twice');
    expect(shifts.closes.single.counted, const Money(20000));
  });

  testWidgets('left alone, no note goes through: a close does not need one', (
    tester,
  ) async {
    await open(tester);

    await countAndClose(tester);

    expect(shifts.closes, hasLength(1));
    expect(shifts.closes.single.note, isNull);
  });

  testWidgets('spaces alone are no note', (tester) async {
    await open(tester);

    await tester.enterText(noteField, '     ');
    await countAndClose(tester);

    expect(shifts.closes.single.note, isNull);
  });

  testWidgets('stops at the 255 characters the platform accepts', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(noteField, 'x' * 400);
    await countAndClose(tester);

    expect(shifts.closes.single.note, 'x' * 255);
  });

  testWidgets('a cashier counting blind can still leave a note', (tester) async {
    await open(
      tester,
      cashier: true,
      policy: const CashPolicy(blindClose: true),
    );

    expect(noteField, findsOneWidget);
    await tester.enterText(noteField, 'Counted twice');
    await countAndClose(tester);

    expect(shifts.closes.single.note, 'Counted twice');
  });

  testWidgets('and in Arabic, without overflowing', (tester) async {
    await open(tester, locale: 'ar');

    expect(noteField, findsOneWidget);
    expect(find.text('ملاحظة (اختياري)'), findsOneWidget);
    expect(find.text('NOTE (OPTIONAL)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// A close, as the dialog made it.
typedef _Close = ({Money counted, String? note});

/// The fake, remembering what the dialog asked of it — the fake itself takes
/// the note and drops it.
class _RecordingShifts extends FakeShiftRepository {
  final closes = <_Close>[];

  @override
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
    Approval? approval,
  }) {
    closes.add((counted: countedCash, note: note));
    return super.close(
      shift: shift,
      by: by,
      countedCash: countedCash,
      note: note,
      approval: approval,
    );
  }
}

class _Owner extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 1,
    name: 'Amer M.',
    capabilities: {
      PosCapability.operate,
      PosCapability.shiftClose,
      PosCapability.shiftViewExpectedCash,
      PosCapability.cashVarianceView,
    },
  );
}

/// Opened this drawer, may close it, and may see neither the expected figure
/// nor the variance.
class _Cashier extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 1,
    name: 'Amer M.',
    capabilities: {PosCapability.operate, PosCapability.shiftClose},
  );
}

class _NothingParked extends OpenTicketsController {
  @override
  OpenTickets build() => const OpenTickets();
}
