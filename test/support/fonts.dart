import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/ui/tokens.dart';

/// The bundled faces, in place of the test font, for a test that draws the
/// back office's tab strip — or claims anything else fits.
///
/// **The one copy.** Eight suites carried the face list inline and a second
/// helper (`bundled_fonts.dart`, from `pos/ia-screens`) did the same load
/// under another name; a face added to the app and to only some of them would
/// have made "fits at 1100 px" true in one test and false in the next.
///
/// **The test font is a measurement of nothing.** It draws every glyph a full
/// em wide, so ten English tab words overflow a strip at 1440 px that the real
/// IBM Plex Sans Arabic fits into 1006 px at 1100 (the owner's map, 14 Sep
/// 2026; measured in `back_office_shell_test.dart`). A test that opens the
/// back office as an offline owner draws all ten, and without this it reports
/// an overflow no till would ever show. Widening the strip's budget to suit a
/// fake font was the alternative, and would have cost real room on the
/// narrowest real screen for a problem only the test harness has.
///
/// Call once, from `setUpAll`.
Future<void> loadPosFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ui = FontLoader(PosFonts.ui);
  for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    ui.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$face.ttf'));
  }
  await ui.load();
  final mono = FontLoader(PosFonts.mono);
  for (final face in ['Regular', 'Medium', 'SemiBold']) {
    mono.addFont(rootBundle.load('assets/fonts/IBMPlexMono-$face.ttf'));
  }
  await mono.load();
}
