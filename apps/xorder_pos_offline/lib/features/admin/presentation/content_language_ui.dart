import 'package:flutter/widgets.dart';

import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';

/// How a name box looks in the one language it is written in (XORD-035).
extension ContentLanguagesUi on ContentLanguages {
  /// Arabic runs right to left, English left to right; `both` (a caller that
  /// has not resolved to one language) leaves the screen's own direction.
  TextDirection? get nameDirection => switch (this) {
    ContentLanguages.arabic => TextDirection.rtl,
    ContentLanguages.english => TextDirection.ltr,
    ContentLanguages.both => null,
  };

  /// The words for a name box's label: the box's own language, so an Arabic
  /// box reads `الاسم` and an English one `Name` whatever the screen is
  /// showing. [screen] stands in for `both`.
  AppStrings nameStrings(AppStrings screen) => switch (this) {
    ContentLanguages.arabic => const ArStrings(),
    ContentLanguages.english => const EnStrings(),
    ContentLanguages.both => screen,
  };
}

/// Lays a name field out - label and box together - in the language it is
/// written in, so the box is right-aligned in Arabic and left-aligned in
/// English whatever the rest of the screen is doing (XORD-035).
class NameDirection extends StatelessWidget {
  const NameDirection({
    required this.languages,
    required this.child,
    super.key,
  });

  final ContentLanguages languages;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = languages.nameDirection;
    return direction == null
        ? child
        : Directionality(textDirection: direction, child: child);
  }
}
