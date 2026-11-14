import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  Widget arabic(Widget child) => MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: const [
      AppLocalizations(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 400, child: child)),
  );

  testWidgets('does not call an unresolved backlog synced', (tester) async {
    await tester.pumpWidget(app(const SyncPill(online: true, queued: null)));
    expect(find.text('● Checking sync…'), findsOneWidget);
    expect(find.textContaining('Synced'), findsNothing);
  });

  testWidgets('does not call a failed backlog synced', (tester) async {
    await tester.pumpWidget(
      app(const SyncPill(online: true, queued: null, hasError: true)),
    );
    expect(find.text('● Sync status unavailable'), findsOneWidget);
    expect(find.textContaining('Synced'), findsNothing);
  });

  group('on a till set up in العربية', () {
    // The pill sits in the top bar, so whatever it says is on screen for the
    // whole service. It spelled its four states out in English inline, which
    // meant an Arabic till reported its sync status in a language the cashier
    // did not choose — the one part of the bar that never changed language.
    testWidgets('says every state in Arabic', (tester) async {
      for (final (pill, expected) in [
        (
          const SyncPill(online: true, queued: null, hasError: true),
          '● تعذّرت معرفة حالة المزامنة',
        ),
        (const SyncPill(online: true, queued: null), '● جارٍ التحقق من المزامنة…'),
        (const SyncPill(online: true, queued: 4), '● تمت المزامنة · 4 في الانتظار'),
        (const SyncPill(online: false, queued: 4), '● غير متصل · 4 في الانتظار'),
        // A till that cannot count its backlog says so rather than showing a
        // zero it has not earned.
        (const SyncPill(online: false, queued: null), '● غير متصل · — في الانتظار'),
      ]) {
        await tester.pumpWidget(arabic(pill));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget, reason: expected);
      }
    });

    testWidgets('keeps the queue count in Western digits', (tester) async {
      // Read across a counter and typed back into a keypad, so both languages
      // render one digit shape.
      await tester.pumpWidget(arabic(const SyncPill(online: true, queued: 12)));
      await tester.pumpAndSettle();

      expect(find.textContaining('12'), findsOneWidget);
      expect(find.textContaining('١٢'), findsNothing);
    });

    testWidgets('lays the pill out right to left', (tester) async {
      await tester.pumpWidget(arabic(const SyncPill(online: true, queued: 1)));
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(SyncPill))),
        TextDirection.rtl,
      );
    });
  });
}
