import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/features/sale/widgets/open_item_dialog.dart';

/// The open-item dialog's quantity is a count. With the currency appended
/// ("1 EGP") it did not fit its 36-wide box and wrapped onto two lines.
void main() {
  Future<void> open(WidgetTester tester, {String locale = 'en'}) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(),
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
                onPressed: () => OpenItemDialog.show(context),
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

  for (final locale in ['en', 'ar']) {
    testWidgets('the quantity is a bare count, on one line ($locale)', (
      tester,
    ) async {
      await open(tester, locale: locale);

      expect(find.text('1 EGP'), findsNothing);
      final count = find.text('1');
      expect(count, findsWidgets);
      expect(tester.getSize(count.first).height, lessThan(24));

      await tester.tap(find.text('+').first);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);
      expect(find.text('2 EGP'), findsNothing);
    });
  }
}
