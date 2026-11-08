import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/ui/tokens.dart';

/// The bundled faces, in place of the test font, for a test that draws the
/// window's bar or the back office — or claims anything else fits.
///
/// **The one copy.** Eight suites carried the face list inline and a second
/// helper (`bundled_fonts.dart`, from `pos/ia-screens`) did the same load
/// under another name; a face added to the app and to only some of them would
/// have made "fits at 1100 px" true in one test and false in the next.
///
/// **The test font is a measurement of nothing.** It draws every glyph a full
/// em wide, so ten English tab words overflowed, at 1440 px, the back office's
/// tab strip that the real IBM Plex Sans Arabic fitted into 1006 px at 1100
/// (the owner's map, 14 Sep 2026). The strip is gone (15 Sep 2026); the same
/// ten words are the window's bar now, measured at 1100 in
/// `settings_bar_test.dart`, and every page the bar reaches is laid out there
/// in `back_office_shell_test.dart`. Widening a budget to suit a fake font
/// was the alternative, and would have cost real room on the narrowest real
/// screen for a problem only the test harness has.
///
/// Call once, from `setUpAll`.
Future<void> loadPosFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ui = FontLoader(PosFonts.ui);
  for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    ui.addFont(_font('assets/fonts/IBMPlexSansArabic-$face.ttf'));
  }
  await ui.load();
  final mono = FontLoader(PosFonts.mono);
  for (final face in ['Regular', 'Medium', 'SemiBold']) {
    mono.addFont(_font('assets/fonts/IBMPlexMono-$face.ttf'));
  }
  await mono.load();
}

/// A bundled font file, from wherever this test run keeps it.
///
/// Run from `packages/xorder_pos` the fonts are the package's own assets, at
/// the bare path. Run from an app (`apps/xorder_pos_*`), whose tests also use
/// this helper, the same files are bundled under the dependency prefix Flutter
/// gives a package's assets. Try the bare path first and fall back.
Future<ByteData> _font(String path) async {
  try {
    return await rootBundle.load(path);
  } on FlutterError {
    return rootBundle.load('packages/xorder_pos/$path');
  }
}
