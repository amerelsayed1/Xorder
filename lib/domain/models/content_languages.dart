/// Which languages the restaurant writes its content in (XORD-005): the names
/// and descriptions of categories, products, combos and extras.
///
/// Three choices, stored as `pos_restaurants.content_languages`:
///
///   `ar`    Arabic only   - only the Arabic field is asked for
///   `en`    English only  - only the English field is asked for
///   `both`  both          - either one, both shown (today's behaviour)
///
/// **This is content, not the interface.** The till's own language (the bar's
/// Arabic/English switch) says nothing about it; a cashier reads the screen in
/// English while the menu is written in Arabic.
///
/// Switching a language off never deletes what was written in it - see
/// [resolveNames] for how a save treats the hidden field.
library;

enum ContentLanguages {
  arabic('ar'),
  english('en'),
  both('both');

  const ContentLanguages(this.wire);

  final String wire;

  bool get showsArabic => this != english;
  bool get showsEnglish => this != arabic;

  /// An unknown or missing value is `both`: asking for more fields than
  /// necessary is the safe way to be wrong.
  static ContentLanguages fromWire(String? value) => switch (value) {
    'ar' => arabic,
    'en' => english,
    _ => both,
  };

  /// The setting a platform bundle describes, or null when it says nothing.
  ///
  /// The platform keeps two flags: `bilingual`, and the `default_language` that
  /// is the first language when bilingual and the only one when not. An older
  /// platform sends neither `bilingual` nor anything useful, which must leave
  /// whatever the till already has alone - so null, not `both`.
  static ContentLanguages? fromPlatform({
    required bool? bilingual,
    required String? defaultLanguage,
  }) {
    if (bilingual == null) return null;
    if (bilingual) return both;
    return switch (defaultLanguage) {
      'ar' => arabic,
      'en' => english,
      _ => null,
    };
  }
}

/// Whether the name a form is asking for has been typed.
///
/// Only the language the form shows can be required: `both` keeps asking for
/// English, as every dialog did before this setting existed.
bool hasRequiredName({
  required ContentLanguages languages,
  required String typedEn,
  required String typedAr,
}) => switch (languages) {
  ContentLanguages.arabic => typedAr.trim().isNotEmpty,
  ContentLanguages.english ||
  ContentLanguages.both => typedEn.trim().isNotEmpty,
};

/// A machine code (`tray_of_30`) from a name, or [fallback] plus a short
/// suffix when the name has no Latin letters or digits to make one from - an
/// Arabic-only restaurant's names. The code stays editable where the operator
/// knows better; this only keeps a save from being refused for an empty one.
String codeFromName(String name, {required String fallback, DateTime? now}) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isNotEmpty) return slug;
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return '${fallback}_${stamp.toRadixString(36)}';
}

/// The two stored names a save should write, given what the form showed.
///
/// **The hidden language is kept, not blanked.** [previousEn] and [previousAr]
/// are what is stored now; a language the form did not show keeps its value.
///
/// [nameAr] is an empty string, never null, for "no Arabic name": the stores
/// turn '' into null, and `copyWith` reads a null as "unchanged", which would
/// make an Arabic name impossible to clear.
///
/// **`name_en` is NOT NULL in the till's database and every reader assumes it,**
/// so an Arabic-only restaurant cannot leave it empty. When English is switched
/// off the English column mirrors the Arabic name instead - on create always,
/// and on edit only while it was still a mirror (it equalled the old Arabic
/// name), so a real English translation is never overwritten. If English is
/// switched on later, the field shows that Arabic text, ready to be translated.
({String nameEn, String nameAr}) resolveNames({
  required ContentLanguages languages,
  required String typedEn,
  required String typedAr,
  String? previousEn,
  String? previousAr,
}) {
  final en = typedEn.trim();
  final ar = typedAr.trim();

  switch (languages) {
    case ContentLanguages.both:
      return (nameEn: en, nameAr: ar);

    case ContentLanguages.english:
      // Arabic is hidden: whatever is stored stays.
      return (nameEn: en, nameAr: previousAr ?? '');

    case ContentLanguages.arabic:
      final wasMirror =
          previousEn == null || previousEn.isEmpty || previousEn == previousAr;
      return (nameEn: wasMirror ? ar : previousEn, nameAr: ar);
  }
}
