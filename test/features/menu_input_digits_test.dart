import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/features/admin/presentation/menu_editor_widgets.dart';

/// The item editor's price field shows Latin digits on an Arabic till, even
/// when they are typed on an Arabic keyboard: a price is data, not prose.
void main() {
  Future<void> pump(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: buildPosTheme(PosPalette.light),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: field),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a numeric field folds Arabic-Indic digits as they are typed', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pump(
      tester,
      MenuInput(
        fieldKey: const Key('price'),
        controller: controller,
        label: 'السعر',
        mono: true,
      ),
    );

    await tester.enterText(find.byKey(const Key('price')), '١٥٠.٥٠');
    expect(controller.text, '150.50');
  });

  testWidgets('a name field is left alone', (tester) async {
    final controller = TextEditingController();
    await pump(
      tester,
      MenuInput(
        fieldKey: const Key('name'),
        controller: controller,
        label: 'الاسم',
        arabic: true,
      ),
    );

    await tester.enterText(find.byKey(const Key('name')), 'وجبة ١٢٣');
    expect(controller.text, 'وجبة ١٢٣');
  });
}
