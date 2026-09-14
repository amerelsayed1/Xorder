import 'package:flutter/services.dart';
import 'package:xorder_pos/core/ui/tokens.dart';

/// The bundled faces, not the test font, for a test that claims something
/// fits.
///
/// The test font draws every glyph a full em wide, which is a measurement of
/// nothing: "fits at 1100 px" is a claim about IBM Plex Sans Arabic, in both
/// of its scripts. The same load `back_office_shell_test.dart` does, shared so
/// a pane test does not carry a fourth copy of the face list.
Future<void> loadBundledFonts() async {
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
