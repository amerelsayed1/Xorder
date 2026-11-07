import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/failure_card.dart';

/// The rule this widget exists to hold: **an offline till is a healthy till.**
/// `danger` is for a stopped till or a refused act; everything a business
/// trades through every day is `warn`. Colouring a normal offline stretch red
/// is how cashiers learn to ignore red, and red has to keep meaning stop.
void main() {
  Widget host(Widget child, {PosPalette palette = PosPalette.light}) =>
      MaterialApp(
        theme: buildPosTheme(palette),
        home: Scaffold(body: Center(child: SizedBox(width: 520, child: child))),
      );

  /// The card's own border colour — the tone, as actually rendered.
  Color borderOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FailureCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final border = (container.decoration! as BoxDecoration).border!;
    return border.top.color;
  }

  testWidgets('a stopped till is danger', (tester) async {
    await tester.pumpWidget(
      host(
        const FailureCard(
          tone: FailureTone.danger,
          kicker: 'BLOCKED',
          title: 'Database unreachable',
          detail:
              'The till cannot reach the branch database. Selling is paused '
              'until it answers — nothing entered is lost.',
        ),
      ),
    );

    expect(borderOf(tester), PosPalette.light.danger);
  });

  testWidgets('working offline is warn, never danger', (tester) async {
    await tester.pumpWidget(
      host(
        const FailureCard(
          tone: FailureTone.warn,
          kicker: 'OFFLINE',
          title: 'Working offline',
          detail:
              'The branch server is unreachable but this till is fine. '
              '14 orders are queued and will sync when it returns.',
        ),
      ),
    );

    expect(borderOf(tester), PosPalette.light.warn);
    expect(borderOf(tester), isNot(PosPalette.light.danger));
  });

  testWidgets('states what is safe, not only what failed', (tester) async {
    // The sentence that stops a cashier re-entering an order they already have
    // is the whole reason the card takes up space.
    await tester.pumpWidget(
      host(
        const FailureCard(
          tone: FailureTone.danger,
          kicker: 'QUEUED',
          title: 'Kitchen ticket did not print',
          detail:
              'Grill station printer did not answer. The round is held in the '
              'queue and will not be dropped.',
        ),
      ),
    );

    expect(find.textContaining('will not be dropped'), findsOneWidget);
  });

  testWidgets('renders every action given to it', (tester) async {
    var retried = false;
    var chose = false;

    await tester.pumpWidget(
      host(
        FailureCard(
          tone: FailureTone.danger,
          kicker: 'QUEUED',
          title: 'Kitchen ticket did not print',
          detail: 'The round is held in the queue.',
          shortcutKey: 'F5',
          actions: [
            FailureAction(label: 'Retry', onPressed: () => retried = true),
            FailureAction(
              label: 'Choose another printer',
              onPressed: () => chose = true,
            ),
            FailureAction(label: 'Mark handled', onPressed: () {}),
          ],
        ),
      ),
    );

    expect(find.text('F5'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Choose another printer'));
    await tester.pump();

    expect(retried, isTrue);
    expect(chose, isTrue);
  });

  testWidgets('a print failure has no dismiss control', (tester) async {
    await tester.pumpWidget(
      host(
        FailureCard(
          tone: FailureTone.danger,
          kicker: 'QUEUED',
          title: 'Kitchen ticket did not print',
          detail: 'The round is held in the queue.',
          actions: [FailureAction(label: 'Retry', onPressed: () {})],
        ),
      ),
    );

    // A failed kitchen print that can be waved away is a failed kitchen print
    // nobody resolves. `Mark handled` is an action with a name against it; a
    // close button is not.
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('a notice may be dismissed', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      host(
        FailureCard(
          tone: FailureTone.warn,
          kicker: 'NOTICE',
          title: 'Licence expires in 6 days',
          detail: 'The till keeps selling until then — a reminder, not a fault.',
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('the tone follows the palette into the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FailureCard(
          tone: FailureTone.warn,
          kicker: 'OFFLINE',
          title: 'Working offline',
          detail: '14 orders queued.',
        ),
        palette: PosPalette.dark,
      ),
    );

    // Not the light warn: a card that named its colour rather than reading it
    // off the palette would be unreadable in one of the two themes.
    expect(borderOf(tester), PosPalette.dark.warn);
    expect(borderOf(tester), isNot(PosPalette.light.warn));
  });
}
