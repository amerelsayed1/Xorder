import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/content_languages.dart';
import 'package:shared_module/domain/models/option_group.dart';
import 'package:shared_module/domain/models/order_type_config.dart';
import 'package:shared_module/domain/models/pos_unit.dart';
import 'package:shared_module/domain/models/service_charge.dart';
import 'package:shared_module/domain/models/stock_item.dart';
import 'package:shared_module/domain/models/supplier.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:xorder_pos_offline/features/admin/presentation/menu_editor_widgets.dart';
import 'package:xorder_pos_offline/features/admin/presentation/order_type_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/service_charge_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/stock_item_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/supplier_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/tax_group_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/tender_type_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/unit_dialog.dart';

/// XORD-005 — every dialog that carries a name in two languages asks only for
/// the languages the business writes in, and a save never erases what a
/// hidden language already holds.
void main() {
  const en = EnStrings();
  const arabicName = 'قهوة';
  const englishName = 'Coffee';

  /// One dialog under test: how to open it, where its fields and Save are,
  /// and how to read the names it handed back.
  ///
  /// [fill] types whatever else the dialog insists on before it will save.
  final dialogs = <_Case>[
    _Case(
      'tax group',
      english: 'tax-group-name',
      arabic: 'tax-group-name-ar',
      save: 'tax-group-save',
      open: (languages, {existing}) => TaxGroupDialog(
        languages: languages,
        group: existing == null
            ? null
            : TaxGroup(
                id: 4,
                nameEn: existing.$1,
                nameAr: existing.$2,
                rateBp: 1400,
              ),
      ),
      fill: (tester) async {
        await tester.enterText(find.byKey(const Key('tax-group-rate')), '14');
      },
      names: (r) => ((r as TaxGroup).nameEn, r.nameAr),
    ),
    _Case(
      'order type',
      english: 'order-type-name',
      arabic: 'order-type-name-ar',
      save: 'order-type-save',
      open: (languages, {existing}) => OrderTypeDialog(
        languages: languages,
        config: OrderTypeConfig(
          type: OrderType.takeaway,
          nameEn: existing?.$1 ?? '',
          nameAr: existing?.$2,
        ),
      ),
      names: (r) => ((r as OrderTypeConfig).nameEn, r.nameAr),
    ),
    _Case(
      'unit',
      english: 'unit-name',
      arabic: 'unit-name_ar',
      save: 'unit-save',
      open: (languages, {existing}) => UnitDialog(
        languages: languages,
        unit: existing == null
            ? null
            : PosUnit(
                id: 3,
                code: 'tray',
                nameEn: existing.$1,
                nameAr: existing.$2,
              ),
      ),
      names: (r) => ((r as PosUnit).nameEn, r.nameAr),
    ),
    _Case(
      'payment method',
      english: 'tender-name',
      arabic: 'tender-name-ar',
      save: 'tender-save',
      open: (languages, {existing}) => TenderTypeDialog(
        languages: languages,
        method: existing == null
            ? null
            : TenderMethod(
                id: 5,
                code: 'voucher',
                nameEn: existing.$1,
                nameAr: existing.$2,
              ),
      ),
      names: (r) => ((r as TenderMethod).nameEn, r.nameAr),
    ),
    _Case(
      'service charge',
      english: 'charge-name',
      arabic: 'charge-name-ar',
      save: 'charge-save',
      open: (languages, {existing}) => ServiceChargeDialog(
        languages: languages,
        charge: existing == null
            ? null
            : ServiceCharge(
                id: 6,
                nameEn: existing.$1,
                nameAr: existing.$2,
                rateBp: 1200,
              ),
      ),
      names: (r) => ((r as ServiceCharge).nameEn, r.nameAr),
    ),
    _Case(
      'stock item',
      english: 'item-name',
      arabic: 'item-name_ar',
      save: 'item-save',
      open: (languages, {existing}) => StockItemDialog(
        languages: languages,
        units: const [],
        item: existing == null
            ? null
            : StockItem(id: 7, nameEn: existing.$1, nameAr: existing.$2),
      ),
      names: (r) => ((r as StockItem).nameEn, r.nameAr),
    ),
    _Case(
      'supplier',
      english: 'supplier-name',
      arabic: 'supplier-name_ar',
      save: 'supplier-save',
      open: (languages, {existing}) => SupplierDialog(
        languages: languages,
        supplier: existing == null
            ? null
            : Supplier(id: 8, nameEn: existing.$1, nameAr: existing.$2),
      ),
      names: (r) => ((r as Supplier).nameEn, r.nameAr),
    ),
  ];

  for (final dialog in dialogs) {
    group(dialog.label, () {
      testWidgets('both languages: the two name fields, as always', (
        tester,
      ) async {
        await _open(tester, dialog.open(ContentLanguages.both));

        expect(find.byKey(Key(dialog.english)), findsOneWidget);
        expect(find.byKey(Key(dialog.arabic)), findsOneWidget);
      });

      testWidgets('Arabic only: one name field, and it is the Arabic one', (
        tester,
      ) async {
        await _open(tester, dialog.open(ContentLanguages.arabic));

        expect(find.byKey(Key(dialog.english)), findsNothing);
        expect(find.byKey(Key(dialog.arabic)), findsOneWidget);
      });

      testWidgets('English only: one name field, and it is the English one', (
        tester,
      ) async {
        await _open(tester, dialog.open(ContentLanguages.english));

        expect(find.byKey(Key(dialog.english)), findsOneWidget);
        expect(find.byKey(Key(dialog.arabic)), findsNothing);
      });

      // XORD-035: the box runs in the language it is written in, whatever the
      // screen is showing (this app is English).
      testWidgets('Arabic only: the box runs right to left', (tester) async {
        await _open(tester, dialog.open(ContentLanguages.arabic));

        expect(
          Directionality.of(tester.element(find.byKey(Key(dialog.arabic)))),
          TextDirection.rtl,
        );
      });

      testWidgets('English only: the box runs left to right', (tester) async {
        await _open(tester, dialog.open(ContentLanguages.english));

        expect(
          Directionality.of(tester.element(find.byKey(Key(dialog.english)))),
          TextDirection.ltr,
        );
      });

      testWidgets('Arabic only: a record with only an English name opens with it', (
        tester,
      ) async {
        await _open(
          tester,
          dialog.open(ContentLanguages.arabic, existing: ('Old name', null)),
        );

        expect(
          tester
              .widget<TextField>(find.byKey(Key(dialog.arabic)))
              .controller!
              .text,
          'Old name',
        );
      });

      testWidgets(
        'Arabic only, new: saves with just the Arabic name; English mirrors it',
        (tester) async {
          final result = await _openAndSave(
            tester,
            dialog,
            ContentLanguages.arabic,
            type: {dialog.arabic: arabicName},
          );

          expect(dialog.names(result), (arabicName, arabicName));
        },
      );

      testWidgets('English only, new: saves with just the English name', (
        tester,
      ) async {
        final result = await _openAndSave(
          tester,
          dialog,
          ContentLanguages.english,
          type: {dialog.english: englishName},
        );

        expect(dialog.names(result).$1, englishName);
        expect(dialog.names(result).$2, anyOf(isNull, isEmpty));
      });

      testWidgets(
        'English only, editing: the hidden Arabic name survives the save',
        (tester) async {
          final result = await _openAndSave(
            tester,
            dialog,
            ContentLanguages.english,
            existing: ('Old', 'قديم'),
            type: {dialog.english: 'New'},
          );

          expect(dialog.names(result), ('New', 'قديم'));
        },
      );

      testWidgets(
        'Arabic only, editing: a real English translation is never overwritten',
        (tester) async {
          final result = await _openAndSave(
            tester,
            dialog,
            ContentLanguages.arabic,
            existing: ('Old', 'قديم'),
            type: {dialog.arabic: 'جديد'},
          );

          expect(dialog.names(result), ('Old', 'جديد'));
        },
      );
    });
  }

  group('a code made from a name', () {
    testWidgets('a new Arabic-only unit still gets a valid code', (
      tester,
    ) async {
      final unit = await _openAndSave(
        tester,
        dialogs.firstWhere((d) => d.label == 'unit'),
        ContentLanguages.arabic,
        type: {'unit-name_ar': 'صينية'},
      ) as PosUnit;

      expect(
        PosUnit.codePattern.hasMatch(unit.code),
        isTrue,
        reason: unit.code,
      );
    });

    testWidgets('a new Arabic-only payment method still gets a code', (
      tester,
    ) async {
      final method = await _openAndSave(
        tester,
        dialogs.firstWhere((d) => d.label == 'payment method'),
        ContentLanguages.arabic,
        type: {'tender-name-ar': 'قسيمة'},
      ) as TenderMethod;

      expect(method.code, isNotEmpty);
    });

    test('an English name still makes the readable code it always did', () {
      expect(codeFromName('Tray of 30', fallback: 'unit'), 'tray_of_30');
    });

    test('a name with no Latin letters falls back, and stays unique-ish', () {
      final a = codeFromName(
        'صينية',
        fallback: 'unit',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final b = codeFromName(
        'صينية',
        fallback: 'unit',
        now: DateTime.fromMillisecondsSinceEpoch(1700000001000),
      );
      expect(a, startsWith('unit_'));
      expect(a, isNot(b));
      expect(PosUnit.codePattern.hasMatch(a), isTrue);
    });
  });

  group('the required name', () {
    testWidgets('order type, Arabic only: an empty Arabic name is refused', (
      tester,
    ) async {
      final saved = await _openAndSave(
        tester,
        dialogs.firstWhere((d) => d.label == 'order type'),
        ContentLanguages.arabic,
        type: {},
        expectSaved: false,
      );

      expect(saved, isNull);
      expect(find.text(en.orderTypeNeedsAName), findsOneWidget);
    });

    testWidgets(
      'order type, English only: a stored Arabic name does not satisfy it',
      (tester) async {
        final saved = await _openAndSave(
          tester,
          dialogs.firstWhere((d) => d.label == 'order type'),
          ContentLanguages.english,
          existing: ('Old', 'قديم'),
          type: {'order-type-name': ''},
          expectSaved: false,
        );

        expect(saved, isNull);
        expect(find.text(en.orderTypeNeedsAName), findsOneWidget);
      },
    );

    testWidgets('tax group, Arabic only: the Arabic name satisfies it', (
      tester,
    ) async {
      final saved = await _openAndSave(
        tester,
        dialogs.firstWhere((d) => d.label == 'tax group'),
        ContentLanguages.arabic,
        type: {'tax-group-name-ar': 'معفى'},
      );

      expect(saved, isNotNull);
    });
  });

  group('extras and sizes (the shared group editor)', () {
    const stored = OptionGroupDraft(
      id: 2,
      nameEn: 'Milk',
      nameAr: 'حليب',
      displayNameEn: 'Pick a milk',
      displayNameAr: 'اختر الحليب',
      options: [
        OptionDraft(id: 10, nameEn: 'Oat', nameAr: 'شوفان', price: Money(500)),
      ],
    );

    OptionGroupDraft draftOf(EditableGroup group, ContentLanguages languages) {
      final (:draft, :error) = group.toDraft(en, languages: languages);
      expect(error, isNull);
      return draft!;
    }

    test('both languages: exactly what was typed, as before', () {
      final group = EditableGroup.from(stored)
        ..nameEn.text = 'Dairy'
        ..nameAr.text = '';
      addTearDown(group.dispose);

      final draft = draftOf(group, ContentLanguages.both);

      expect(draft.nameEn, 'Dairy');
      expect(draft.nameAr, anyOf(isNull, isEmpty));
      expect(draft.displayNameEn, 'Pick a milk');
    });

    test('English only: the hidden Arabic names are kept, not blanked', () {
      final group = EditableGroup.from(stored)..nameEn.text = 'Dairy';
      // The Arabic boxes are not on screen, so nothing could have emptied
      // them; clear them anyway to show the save does not read them.
      group.nameAr.text = '';
      group.displayAr.text = '';
      group.options.first.nameAr.text = '';
      addTearDown(group.dispose);

      final draft = draftOf(group, ContentLanguages.english);

      expect(draft.nameEn, 'Dairy');
      expect(draft.nameAr, 'حليب');
      expect(draft.displayNameAr, 'اختر الحليب');
      expect(draft.options.first.nameAr, 'شوفان');
    });

    test('Arabic only: a real English translation is kept', () {
      final group = EditableGroup.from(stored)..nameAr.text = 'ألبان';
      group.nameEn.text = '';
      group.displayEn.text = '';
      group.options.first.nameEn.text = '';
      addTearDown(group.dispose);

      final draft = draftOf(group, ContentLanguages.arabic);

      expect(draft.nameAr, 'ألبان');
      expect(draft.nameEn, 'Milk');
      expect(draft.displayNameEn, 'Pick a milk');
      expect(draft.options.first.nameEn, 'Oat');
    });

    test('Arabic only, new: the English column mirrors the Arabic name', () {
      final group = EditableGroup.blank()
        ..nameAr.text = 'إضافات'
        ..options.add(EditableOption.blank()..nameAr.text = 'جبنة');
      addTearDown(group.dispose);

      final draft = draftOf(group, ContentLanguages.arabic);

      expect(draft.nameEn, 'إضافات');
      expect(draft.options.single.nameEn, 'جبنة');
    });

    testWidgets('the option rows draw only the enabled name cells', (
      tester,
    ) async {
      for (final (languages, hasEn, hasAr) in [
        (ContentLanguages.both, true, true),
        (ContentLanguages.arabic, false, true),
        (ContentLanguages.english, true, false),
      ]) {
        final group = EditableGroup.from(stored);
        addTearDown(group.dispose);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: OptionRows(
                group: group,
                keyPrefix: 'x',
                onChanged: () {},
                languages: languages,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // XORD-035: a cell runs in the language it is written in.
        if (languages == ContentLanguages.arabic) {
          expect(
            Directionality.of(
              tester.element(find.byKey(const Key('x-option-0-name-ar'))),
            ),
            TextDirection.rtl,
          );
        }
        if (languages == ContentLanguages.english) {
          expect(
            Directionality.of(
              tester.element(find.byKey(const Key('x-option-0-name'))),
            ),
            TextDirection.ltr,
          );
        }

        expect(
          find.byKey(const Key('x-option-0-name')),
          hasEn ? findsOneWidget : findsNothing,
          reason: '$languages English cell',
        );
        expect(
          find.byKey(const Key('x-option-0-name-ar')),
          hasAr ? findsOneWidget : findsNothing,
          reason: '$languages Arabic cell',
        );
      }
    });
  });
}

class _Case {
  const _Case(
    this.label, {
    required this.english,
    required this.arabic,
    required this.save,
    required this.open,
    required this.names,
    this.fill,
  });

  final String label;
  final String english;
  final String arabic;
  final String save;

  /// The dialog; [existing] is the (English, Arabic) pair already stored.
  final Widget Function(ContentLanguages, {(String, String?)? existing}) open;
  final Future<void> Function(WidgetTester)? fill;
  final (String, String?) Function(Object? result) names;
}

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    theme: buildPosTheme(PosPalette.light),
    localizationsDelegates: const [
      AppLocalizations(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Opens [dialog] over a page and returns what it pops, once it has.
Future<Object?> _open(WidgetTester tester, Widget dialog) async {
  tester.view
    ..physicalSize = const Size(1440, 1600)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Object? popped;
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await showDialog<Object>(
                context: context,
                builder: (_) => dialog,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return Future.value(popped);
}

Future<Object?> _openAndSave(
  WidgetTester tester,
  _Case dialog,
  ContentLanguages languages, {
  (String, String?)? existing,
  required Map<String, String> type,
  bool expectSaved = true,
}) async {
  tester.view
    ..physicalSize = const Size(1440, 1600)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Object? popped;
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await showDialog<Object>(
                context: context,
                builder: (_) => dialog.open(languages, existing: existing),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  for (final entry in type.entries) {
    await tester.enterText(find.byKey(Key(entry.key)), entry.value);
  }
  await dialog.fill?.call(tester);
  await tester.pumpAndSettle();

  final save = find.byKey(Key(dialog.save));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();

  if (expectSaved) expect(popped, isNotNull, reason: 'the dialog should save');
  return popped;
}
