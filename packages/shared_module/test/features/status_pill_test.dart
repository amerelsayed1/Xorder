import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';

/// What the top bar's status pill is allowed to claim.
///
/// The bug this pins: an **offline** terminal showed "offline · 0 queued",
/// permanently. That announces a correct and intended state as though it were a
/// fault, beside a counter that can only ever read zero — and it is the first
/// thing a cashier looks at when something feels wrong.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget pill, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: buildPosTheme(PosPalette.light),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: pill)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('an offline terminal', () {
    testWidgets('never says "offline"', (tester) async {
      // It is not offline. It is a till that was installed to run this way.
      await pump(
        tester,
        const BranchServerPill(checking: false, reachable: true),
      );

      expect(find.textContaining('Offline'), findsNothing);
      expect(find.textContaining('offline'), findsNothing);
      expect(find.textContaining('queued'), findsNothing);
    });

    testWidgets('names the branch server when it is healthy', (tester) async {
      await pump(
        tester,
        const BranchServerPill(checking: false, reachable: true),
      );
      expect(find.textContaining('Branch server'), findsOneWidget);
      expect(find.textContaining('unreachable'), findsNothing);
    });

    testWidgets('warns when the branch server is not answering', (
      tester,
    ) async {
      // The one thing that can actually stop this till selling.
      await pump(
        tester,
        const BranchServerPill(checking: false, reachable: false),
      );
      expect(find.textContaining('unreachable'), findsOneWidget);
    });

    testWidgets('says it is checking before the first probe returns', (
      tester,
    ) async {
      // Not "unreachable" — a pill that cried failure for the half second
      // before the first probe came back would be wrong on every launch.
      await pump(
        tester,
        const BranchServerPill(checking: true, reachable: false),
      );
      expect(find.textContaining('Checking'), findsOneWidget);
      expect(find.textContaining('unreachable'), findsNothing);
    });

    testWidgets('renders in Arabic', (tester) async {
      await pump(
        tester,
        const BranchServerPill(checking: false, reachable: false),
        locale: 'ar',
      );
      expect(find.textContaining('خادم الفرع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a cloud terminal', () {
    testWidgets('still reports what it owes the platform', (tester) async {
      // Unchanged: here "offline" means something real — sales this terminal
      // has taken that the platform has not seen.
      await pump(
        tester,
        const SyncPill(online: false, queued: 3),
      );
      expect(find.textContaining('3'), findsOneWidget);
    });

    testWidgets('reports a healthy sync', (tester) async {
      await pump(tester, const SyncPill(online: true, queued: 0));
      expect(find.textContaining('Synced'), findsOneWidget);
    });

    testWidgets('reports an unusable sync state as such', (tester) async {
      await pump(
        tester,
        const SyncPill(online: true, queued: null, hasError: true),
      );
      expect(find.textContaining('unavailable'), findsOneWidget);
    });
  });
}
