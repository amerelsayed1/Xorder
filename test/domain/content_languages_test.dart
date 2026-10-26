import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';

/// XORD-005 — which languages the menu is written in, and what a save keeps.
void main() {
  group('the setting', () {
    test('three values, each saying which fields to ask for', () {
      expect(ContentLanguages.arabic.showsArabic, isTrue);
      expect(ContentLanguages.arabic.showsEnglish, isFalse);
      expect(ContentLanguages.english.showsEnglish, isTrue);
      expect(ContentLanguages.english.showsArabic, isFalse);
      expect(ContentLanguages.both.showsArabic, isTrue);
      expect(ContentLanguages.both.showsEnglish, isTrue);
    });

    test('an unknown or missing value asks for both: more fields is the safe error', () {
      expect(ContentLanguages.fromWire(null), ContentLanguages.both);
      expect(ContentLanguages.fromWire('fr'), ContentLanguages.both);
      expect(ContentLanguages.fromWire('ar'), ContentLanguages.arabic);
      expect(ContentLanguages.fromWire('en'), ContentLanguages.english);
    });

    test('the platform\'s two flags map onto it, and silence maps onto nothing', () {
      ContentLanguages? from(bool? bilingual, String? lang) =>
          ContentLanguages.fromPlatform(bilingual: bilingual, defaultLanguage: lang);

      expect(from(true, 'ar'), ContentLanguages.both);
      expect(from(true, 'en'), ContentLanguages.both);
      expect(from(false, 'ar'), ContentLanguages.arabic);
      expect(from(false, 'en'), ContentLanguages.english);
      // An older platform sends no `bilingual`: leave the till's setting alone.
      expect(from(null, 'ar'), isNull);
      expect(from(false, null), isNull);
      expect(from(false, 'fr'), isNull);
    });
  });

  group('what a save writes', () {
    test('both: exactly what was typed, an empty Arabic name clearing it', () {
      final names = resolveNames(
        languages: ContentLanguages.both,
        typedEn: ' Espresso ',
        typedAr: '',
        previousEn: 'Espresso',
        previousAr: 'اسبريسو',
      );
      expect(names.nameEn, 'Espresso');
      expect(names.nameAr, '');
    });

    test('Arabic only, new: the English column mirrors the Arabic name', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'قهوة',
      );
      expect(names.nameAr, 'قهوة');
      expect(names.nameEn, 'قهوة', reason: 'name_en is NOT NULL and every reader assumes it');
    });

    test('Arabic only, editing: a real English translation is never overwritten', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'قهوة ساخنة',
        previousEn: 'Coffee',
        previousAr: 'قهوة',
      );
      expect(names.nameEn, 'Coffee');
      expect(names.nameAr, 'قهوة ساخنة');
    });

    test('Arabic only, editing a mirror: it follows the rename, so it never goes stale', () {
      final names = resolveNames(
        languages: ContentLanguages.arabic,
        typedEn: '',
        typedAr: 'قهوة ساخنة',
        previousEn: 'قهوة',
        previousAr: 'قهوة',
      );
      expect(names.nameEn, 'قهوة ساخنة');
    });

    test('English only: the hidden Arabic name is kept, not blanked', () {
      final names = resolveNames(
        languages: ContentLanguages.english,
        typedEn: 'Coffee',
        typedAr: '',
        previousEn: 'Coffee',
        previousAr: 'قهوة',
      );
      expect(names.nameEn, 'Coffee');
      expect(names.nameAr, 'قهوة');
    });

    test('English only, new: no Arabic name, as an empty string', () {
      final names = resolveNames(
        languages: ContentLanguages.english,
        typedEn: 'Coffee',
        typedAr: '',
      );
      expect(names.nameAr, '');
    });
  });
}
