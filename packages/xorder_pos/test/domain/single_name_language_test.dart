import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';

/// XORD-035 — the POS writes names in one language: the business's own
/// choice when it made one, the till's language when it did not.
void main() {
  group('which single language a form is written in', () {
    test('fromLocale: Arabic for ar, English for everything else', () {
      expect(ContentLanguages.fromLocale('ar'), ContentLanguages.arabic);
      expect(ContentLanguages.fromLocale('ar-EG'), ContentLanguages.arabic);
      expect(ContentLanguages.fromLocale('en'), ContentLanguages.english);
      expect(ContentLanguages.fromLocale('fr'), ContentLanguages.english);
    });

    test('a stored choice wins; "both" is read as the till language', () {
      expect(ContentLanguages.arabic.resolvedFor('en'), ContentLanguages.arabic);
      expect(ContentLanguages.english.resolvedFor('ar'), ContentLanguages.english);
      expect(ContentLanguages.both.resolvedFor('ar'), ContentLanguages.arabic);
      expect(ContentLanguages.both.resolvedFor('en'), ContentLanguages.english);
    });

    for (final (locale, stored, expected) in [
      ('ar', ContentLanguages.both, ContentLanguages.arabic),
      ('en', ContentLanguages.both, ContentLanguages.english),
      ('en', ContentLanguages.arabic, ContentLanguages.arabic),
      ('ar', ContentLanguages.english, ContentLanguages.english),
    ]) {
      test('provider: till $locale, stored ${stored.wire} -> ${expected.wire}', () async {
        final container = ProviderContainer(
          overrides: [
            localeProvider.overrideWith(() => _Terminal(locale)),
            contentLanguagesProvider.overrideWith((ref) async => stored),
          ],
        );
        addTearDown(container.dispose);
        await container.read(contentLanguagesProvider.future);

        expect(container.read(contentLanguagesNowProvider), expected);
      });
    }

    test('provider: while the setting is still loading it is never "both"', () {
      final container = ProviderContainer(
        overrides: [
          localeProvider.overrideWith(() => _Terminal('ar')),
          contentLanguagesProvider.overrideWith((ref) async => ContentLanguages.english),
        ],
      );
      addTearDown(container.dispose);

      // The future has not completed: the answer is the till's language.
      expect(container.read(contentLanguagesNowProvider), ContentLanguages.arabic);
    });
  });

  group('an Arabic-only form opening an older record', () {
    test('a record with only an English name opens with it', () {
      expect(
        initialArabicName(languages: ContentLanguages.arabic, nameAr: null, nameEn: 'Coffee'),
        'Coffee',
      );
      expect(
        initialArabicName(languages: ContentLanguages.arabic, nameAr: '', nameEn: 'Coffee'),
        'Coffee',
      );
    });

    test('a record with an Arabic name opens with that', () {
      expect(
        initialArabicName(languages: ContentLanguages.arabic, nameAr: 'قهوة', nameEn: 'Coffee'),
        'قهوة',
      );
    });

    test('other modes never borrow the English name', () {
      expect(
        initialArabicName(languages: ContentLanguages.both, nameAr: null, nameEn: 'Coffee'),
        '',
      );
      expect(
        initialArabicName(languages: ContentLanguages.english, nameAr: null, nameEn: 'Coffee'),
        '',
      );
    });

    test('saving it unchanged invents no Arabic name and keeps the English one', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'Coffee',
        previousEn: 'Coffee',
        previousAr: null,
      );

      expect(names.nameEn, 'Coffee');
      expect(names.nameAr, '');
    });

    test('renaming it writes the Arabic name and keeps the English one', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'قهوة',
        previousEn: 'Coffee',
        previousAr: null,
      );

      expect(names.nameEn, 'Coffee', reason: 'a real English name is kept');
      expect(names.nameAr, 'قهوة');
    });

    test('a record that already has an Arabic name is untouched by the stand-in rule', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'Coffee',
        previousEn: 'Coffee',
        previousAr: 'قهوة',
      );

      expect(names.nameAr, 'Coffee', reason: 'typed over an existing Arabic name');
    });
  });
}

class _Terminal extends TerminalLocaleController {
  _Terminal(this._code);
  final String _code;

  @override
  Locale build() => Locale(_code);
}
