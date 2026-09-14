import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/supervisor_override.dart';
import 'package:xorder_pos/features/payment/payment_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

const _cashier = PosStaff(
  id: 2,
  name: 'Rana A.',
  username: 'rana',
  role: FakeSessionRepository.cashier,
);

const _supervisor = PosStaff(
  id: 3,
  name: 'Sara M.',
  username: 'sara',
  role: PosRole(
    id: 3,
    code: SystemRoles.supervisorCode,
    nameEn: 'Supervisor',
    capabilities: SystemRoles.supervisor,
  ),
);

/// Taking a payment back off a bill that has not been settled.
///
/// It was a tap with nothing behind it — the "×" beside a tender — and it is
/// the act a card-for-cash swap is made of: tender by card, take it off, keep
/// the cash. The screen asks now, and a supervisor answers; the engine asks
/// again underneath, which `ticket_engine_test.dart` covers.
void main() {
  /// The till, with a takeaway drink on it, at the payment screen, with 10.00
  /// already tendered by card.
  Future<WidgetRef> paying(WidgetTester tester, PosStaff atTheTill) async {
    late WidgetRef captured;
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeRepositoryOverrides(),
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return SaleScreen(
                onLock: () {},
                onTables: () {},
                onOrders: () {},
                onCloseShift: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    captured.read(signedInStaffProvider.notifier).signIn(atTheTill);
    captured.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
    await tester.tap(find.text('Soft Drink'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentScreen), findsOneWidget);

    captured
        .read(ticketProvider.notifier)
        .addTender(typeId: 2, label: 'Card', amount: const Money(1000));
    await tester.pumpAndSettle();
    return captured;
  }

  int tenders(WidgetRef ref) => ref.read(ticketProvider).tenders.length;

  testWidgets('a cashier\'s × brings a supervisor over, and nothing comes off '
      'without one', (tester) async {
    final ref = await paying(tester, _cashier);

    await tester.tap(find.text('×'));
    await tester.pumpAndSettle();
    expect(find.byType(SupervisorOverrideDialog), findsOneWidget);
    expect(tenders(ref), 1, reason: 'not while the question is open');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tenders(ref), 1, reason: 'nobody said yes');
  });

  testWidgets('a supervisor takes it off without being asked', (tester) async {
    final ref = await paying(tester, _supervisor);

    await tester.tap(find.text('×'));
    await tester.pumpAndSettle();

    expect(find.byType(SupervisorOverrideDialog), findsNothing);
    expect(tenders(ref), 0);
  });

  testWidgets('on a supervisor\'s PIN it comes off, and the approval is written '
      'down', (tester) async {
    final ref = await paying(tester, _cashier);

    await tester.tap(find.text('×'));
    await tester.pumpAndSettle();

    // Inside the supervisor's dialog. The payment screen has a keypad of its
    // own underneath, and the first "1" in the tree is that one — a tap on it
    // lands on the dialog's barrier and types nothing.
    Finder inDialog(Finder finder) => find.descendant(
      of: find.byType(SupervisorOverrideDialog),
      matching: finder,
    );

    // Amer, the owner: PIN 1234 in the fake staff directory.
    for (final digit in '1234'.split('')) {
      await tester.tap(inDialog(find.widgetWithText(InkWell, digit)).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Take it off')).last);
    await tester.pumpAndSettle();
    if (inDialog(find.text('Done')).evaluate().isNotEmpty) {
      await tester.tap(inDialog(find.text('Done')));
      await tester.pumpAndSettle();
    }

    expect(tenders(ref), 0);
    final ledger =
        (ref.read(auditRepositoryProvider) as FakeAuditRepository).entries;
    final row = ledger.firstWhere(
      (e) => e.action == AuditAction.permissionOverridden,
    );
    expect(row.after?['for'], 'payment.removed');
    expect(row.after?['capability'], PosCapability.paymentRemove);
    expect(row.actorName, 'Rana A.');
    expect(row.approvedByName, 'Amer M.');
  });
}
