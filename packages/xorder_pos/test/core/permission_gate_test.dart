import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/permission_gate.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/authorization.dart';

/// The three behaviours are a speed-of-service decision, not styling: a cashier
/// has to be able to tell at a glance whether a manager can fix this. Each test
/// below pins one of the properties that distinction rests on.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildPosTheme(PosPalette.light),
    home: Scaffold(body: Center(child: child)),
  );

  Widget button(VoidCallback onPressed) =>
      ElevatedButton(onPressed: onPressed, child: const Text('Discount'));

  group('hidden', () {
    testWidgets('leaves no trace at all', (tester) async {
      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.hidden,
            disabledReason: 'never shown',
            child: button(() {}),
          ),
        ),
      );

      // Not merely invisible: absent. A transparent or zero-opacity control is
      // still in the tree, still tab-reachable and still announced.
      expect(find.text('Discount'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.text('never shown'), findsNothing);
    });
  });

  group('disabled', () {
    testWidgets('is visible but cannot be activated', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.disabled,
            disabledReason: 'Price override is off for cashiers here.',
            child: button(() => fired = true),
          ),
        ),
      );

      expect(find.text('Discount'), findsOneWidget);
      await tester.tap(find.text('Discount'), warnIfMissed: false);
      await tester.pump();

      // The child keeps its own onPressed; the gate has to swallow the gesture
      // before it arrives, or every disabled control is one tap from firing.
      expect(fired, isFalse);
    });

    testWidgets('announces why, so the reason is reachable', (tester) async {
      const reason = 'Price override is off for cashiers at this branch.';
      await tester.pumpWidget(
        host(
          const PermissionGate(
            behaviour: GateBehaviour.disabled,
            disabledReason: reason,
            child: Text('Price override'),
          ),
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, reason);

      final semantics = tester.getSemantics(find.text('Price override'));
      expect(semantics.hint, contains(reason));
    });

    testWidgets('stays in the focus order', (tester) async {
      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.disabled,
            disabledReason: 'off here',
            child: button(() {}),
          ),
        ),
      );

      // Removing it from the Tab order would turn "disabled" into "hidden" for
      // keyboard users — the people least able to work around it.
      final focus = tester.widget<Focus>(
        find.descendant(
          of: find.byType(PermissionGate),
          matching: find.byType(Focus),
        ).first,
      );
      expect(focus.canRequestFocus, isTrue);
    });
  });

  group('approval', () {
    testWidgets('opens the approval flow instead of the act', (tester) async {
      var acted = false;
      var asked = false;

      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.approval,
            onApprovalNeeded: () => asked = true,
            child: button(() => acted = true),
          ),
        ),
      );

      await tester.tap(find.byType(PermissionGate));
      await tester.pump();

      // Instead of, never after. Performing the act and *then* asking would be
      // an approval that arrives too late to withhold anything.
      expect(asked, isTrue);
      expect(acted, isFalse);
    });

    testWidgets('renders the child untouched, so it looks usable', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.approval,
            onApprovalNeeded: () {},
            child: button(() {}),
          ),
        ),
      );

      // A control needing approval must be indistinguishable from one that does
      // not — no dimming, no dashed border. A cashier who reads it as a refusal
      // goes looking for a manager instead of pressing it.
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('Discount'), findsOneWidget);
    });

    testWidgets('with nothing to approve, the child is returned as-is', (
      tester,
    ) async {
      var acted = false;
      await tester.pumpWidget(
        host(
          PermissionGate(
            behaviour: GateBehaviour.approval,
            child: button(() => acted = true),
          ),
        ),
      );

      await tester.tap(find.text('Discount'));
      await tester.pump();
      expect(acted, isTrue);
    });
  });

  group('forDecision', () {
    const cashier = PosStaff(
      id: 1,
      name: 'Nour Adel',
      capabilities: {PosCapability.operate},
    );

    testWidgets('an allowed capability leaves the child alone', (tester) async {
      var acted = false;
      final decision = Authorization.check(cashier, PosCapability.operate);

      await tester.pumpWidget(
        host(
          PermissionGate.forDecision(
            decision,
            deniedBehaviour: GateBehaviour.disabled,
            onApprovalNeeded: () {},
            child: button(() => acted = true),
          ),
        ),
      );

      await tester.tap(find.text('Discount'));
      await tester.pump();

      // `Allowed` must not route through the approval dialog. There is nothing
      // to approve, and a prompt here would be a prompt that can only annoy.
      expect(acted, isTrue);
    });

    testWidgets('an overridable refusal becomes an approval', (tester) async {
      var asked = false;
      final decision = Authorization.check(cashier, PosCapability.orderVoid);
      expect(decision, isA<NeedsOverride>());

      await tester.pumpWidget(
        host(
          PermissionGate.forDecision(
            decision,
            deniedBehaviour: GateBehaviour.hidden,
            onApprovalNeeded: () => asked = true,
            child: button(() {}),
          ),
        ),
      );

      await tester.tap(find.byType(PermissionGate));
      await tester.pump();
      expect(asked, isTrue);
    });

    testWidgets('a flat denial takes the behaviour the caller chose', (
      tester,
    ) async {
      final decision = Authorization.check(cashier, PosCapability.backupManage);
      expect(decision, isA<Denied>());

      await tester.pumpWidget(
        host(
          PermissionGate.forDecision(
            decision,
            deniedBehaviour: GateBehaviour.hidden,
            child: button(() {}),
          ),
        ),
      );

      // `backup.manage` is not overridable — nobody can lend it at the till —
      // so a caller treating it as CRITICAL gets nothing rendered.
      expect(find.text('Discount'), findsNothing);
    });
  });
}
