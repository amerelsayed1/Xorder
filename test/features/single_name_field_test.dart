import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_menu_pane.dart';
import 'package:xorder_pos/features/admin/presentation/menu_editor_widgets.dart'
    show MenuDialog;

import '../support/fakes.dart';

/// XORD-035 — one name box on every form, in the language of the till or of
/// the restaurant's own choice: labelled in that language, running in its
/// direction, with nothing to translate.
///
/// The pane is opened with the content-language setting NOT overridden where
/// the case is a fresh install - that is the configuration this ticket was
/// about, and the earlier tests always handed the form a language.
void main() {
  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.catalogManage},
    ),
  );

  setUpAll(() {
    registerFallbackValue(const Category(id: 0, nameEn: ''));
    registerFallbackValue(manager);
  });

  late _Repo repo;

  /// Opens the Categories pane on a till whose screen is [screen] ('ar'/'en').
  /// [stored] is what the restaurant row holds; null = nothing answered yet,
  /// the situation of a fresh install (no database, so the provider's own
  /// fallback applies).
  Future<void> pump(
    WidgetTester tester, {
    required String screen,
    ContentLanguages? stored,
    List<Category> categories = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    repo = _Repo();
    when(() => repo.saveCategory(any(), by: any(named: 'by'))).thenAnswer((i) async {
      repo.saved = i.positionalArguments.first as Category;
      return AdminResult.done(repo.saved!);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(english: false),
          localeProvider.overrideWith(() => _Terminal(screen)),
          catalogAdminRepositoryProvider.overrideWithValue(repo),
          if (stored != null) contentLanguagesProvider.overrideWith((ref) async => stored),
          taxGroupsAllProvider.overrideWith((ref) async => const []),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: categories,
              products: const [],
              modifierGroups: const [],
              syncedAt: DateTime.utc(2026),
            ),
          ),
        ],
        child: MaterialApp(
          locale: Locale(screen),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ManagementMenuPane(admin: manager, mode: MenuPaneMode.sections),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openNew(WidgetTester tester, String screen) async {
    final add = screen == 'ar' ? const ArStrings().addCategory : const EnStrings().addCategory;
    await tester.tap(find.text(add));
    await tester.pumpAndSettle();
  }

  Finder boxes() => find.descendant(
    of: find.byType(MenuDialog),
    matching: find.byType(TextField),
  );

  List<String> dialogTexts(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(of: find.byType(MenuDialog), matching: find.byType(Text)),
    ))
      if (t.data != null) t.data!,
  ];

  TextDirection directionOfBox(WidgetTester tester) =>
      Directionality.of(tester.element(boxes()));

  group('a fresh install (nothing stored): exactly one box, in the till language', () {
    testWidgets('Arabic till: one الاسم box, right to left, no translation box', (tester) async {
      await pump(tester, screen: 'ar');
      await openNew(tester, 'ar');

      expect(boxes(), findsOneWidget);
      expect(dialogTexts(tester), contains('الاسم'));
      expect(dialogTexts(tester).where((t) => t.contains('بالعربية') || t.contains('اختياري')), isEmpty);
      expect(directionOfBox(tester), TextDirection.rtl);
    });

    testWidgets('English till: one Name box, left to right, no second language box', (tester) async {
      await pump(tester, screen: 'en');
      await openNew(tester, 'en');

      expect(boxes(), findsOneWidget);
      expect(dialogTexts(tester).map((t) => t.toLowerCase()), contains('name'));
      expect(dialogTexts(tester).where((t) => t.toLowerCase().contains('arabic') || t.toLowerCase().contains('optional')), isEmpty);
      expect(directionOfBox(tester), TextDirection.ltr);
    });
  });

  group('the restaurant has chosen a language', () {
    testWidgets('chosen Arabic on an English screen: the box and its label are Arabic', (tester) async {
      await pump(tester, screen: 'en', stored: ContentLanguages.arabic);
      await openNew(tester, 'en');

      expect(boxes(), findsOneWidget);
      expect(dialogTexts(tester), contains('الاسم'));
      expect(directionOfBox(tester), TextDirection.rtl);
    });

    testWidgets('chosen English on an Arabic screen: the box and its label are English, left to right', (tester) async {
      await pump(tester, screen: 'ar', stored: ContentLanguages.english);
      await openNew(tester, 'ar');

      expect(boxes(), findsOneWidget);
      expect(dialogTexts(tester).map((t) => t.toLowerCase()), contains('name'));
      expect(directionOfBox(tester), TextDirection.ltr);
    });
  });

  group('records that already exist', () {
    const old = Category(id: 4, nameEn: 'Coffee');
    const both = Category(id: 5, nameEn: 'Tea', nameAr: 'شاي');

    Future<void> openFirstForEdit(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
    }

    testWidgets('Arabic till: an English-only record opens with its name, and saving keeps the data', (tester) async {
      await pump(tester, screen: 'ar', categories: const [old]);
      await openFirstForEdit(tester);

      expect(tester.widget<TextField>(boxes()).controller!.text, 'Coffee');

      await tester.tap(find.byKey(const Key('menu-dialog-save')));
      await tester.pumpAndSettle();

      expect(repo.saved!.nameEn, 'Coffee');
      expect(repo.saved!.nameAr ?? '', isEmpty, reason: 'no Arabic name is invented');
    });

    testWidgets('Arabic till: renaming it writes the Arabic name and keeps the English one', (tester) async {
      await pump(tester, screen: 'ar', categories: const [old]);
      await openFirstForEdit(tester);

      await tester.enterText(boxes(), 'قهوة');
      await tester.tap(find.byKey(const Key('menu-dialog-save')));
      await tester.pumpAndSettle();

      expect(repo.saved!.id, 4);
      expect(repo.saved!.nameAr, 'قهوة');
      expect(repo.saved!.nameEn, 'Coffee');
    });

    testWidgets('English till: a record with both names loses neither when edited', (tester) async {
      await pump(tester, screen: 'en', categories: const [both]);
      await openFirstForEdit(tester);

      expect(tester.widget<TextField>(boxes()).controller!.text, 'Tea');
      await tester.enterText(boxes(), 'Green tea');
      await tester.tap(find.byKey(const Key('menu-dialog-save')));
      await tester.pumpAndSettle();

      expect(repo.saved!.nameEn, 'Green tea');
      expect(repo.saved!.nameAr, 'شاي');
    });

    testWidgets('Arabic till: a record with both names loses neither when edited', (tester) async {
      await pump(tester, screen: 'ar', categories: const [both]);
      await openFirstForEdit(tester);

      expect(tester.widget<TextField>(boxes()).controller!.text, 'شاي');
      await tester.enterText(boxes(), 'شاي أخضر');
      await tester.tap(find.byKey(const Key('menu-dialog-save')));
      await tester.pumpAndSettle();

      expect(repo.saved!.nameAr, 'شاي أخضر');
      expect(repo.saved!.nameEn, 'Tea', reason: 'a real English name is kept');
    });
  });
}

class _Terminal extends TerminalLocaleController {
  _Terminal(this._code);
  final String _code;

  @override
  Locale build() => Locale(_code);
}

class _Repo extends Mock implements CatalogAdminRepository {
  Category? saved;
}
