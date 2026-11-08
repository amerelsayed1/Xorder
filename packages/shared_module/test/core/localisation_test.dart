import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/terminal_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';
import 'package:shared_module/features/floor/floor_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Guards the two properties the localisation design actually rests on.
///
/// The sealed-class shape already makes a *missing* translation a compile
/// error — that is the whole reason `AppStrings` is not an ARB file. What it
/// cannot catch is a translation that was never asked for: a widget that spells
/// its words out inline is perfectly valid Dart, and ships an English screen to
/// a till somebody set up in العربية.
///
/// So this suite watches the seam rather than the catalogue: no operator-facing
/// literal in the widget layer, and nothing in `ArStrings` still sitting in
/// English.
void main() {
  group('the catalogue', () {
    test('answers in the language it was asked for', () {
      expect(AppStrings.of(const Locale('en')), isA<EnStrings>());
      expect(AppStrings.of(const Locale('ar')), isA<ArStrings>());
      // Anything else is English, deliberately: a till configured into a
      // language nobody translated should still be usable.
      expect(AppStrings.of(const Locale('fr')), isA<EnStrings>());
    });

    test('runs Arabic right to left and English left to right', () {
      expect(const EnStrings().direction, TextDirection.ltr);
      expect(const ArStrings().direction, TextDirection.rtl);
    });

    test('names each language in itself', () {
      expect(const EnStrings().languageName, 'English');
      expect(const ArStrings().languageName, 'العربية');
    });

    test('isolates a name written in the other script', () {
      // The licence summary puts operator data and a count in one line. An
      // Arabic business name inside the English line used to drag the
      // separators and the number with it — «العاصمه» on a two-terminal plan
      // rendered as "2 · العاصمه terminals". FSI…PDI around the name keeps the
      // reordering inside it.
      const fsi = '\u2068';
      const pdi = '\u2069';

      final en = const EnStrings().licenceCoverage('العاصمه', null, 2);
      expect(
        en,
        '$fsi'
        'العاصمه'
        '$pdi · 2 terminals',
      );

      // And the mirror image: a Latin name inside the Arabic line.
      final ar = const ArStrings().licenceCoverage('Capital Grill', 'Pro', 2);
      expect(ar, contains('${fsi}Capital Grill$pdi'));
      expect(ar, contains('${fsi}Pro$pdi'));
      expect(ar, endsWith('جهازان'));
    });

    test('lays the isolated name out at the start of the line', () {
      // The assertion above is about the characters; this one is about where
      // they land, because the bug was never visible in the string — it was
      // the bidi algorithm reordering at layout. Laid out left to right, the
      // name must sit left of the count. Drop the isolates and it does not:
      // the name is pushed right by the width of "2 · ".
      final line = const EnStrings().licenceCoverage('العاصمه', null, 2);
      expect(_leftEdgeOf(line, 'العاصمه'), 0);
      expect(
        _leftEdgeOf(line, 'terminals'),
        greaterThan(_leftEdgeOf(line, 'العاصمه')),
      );
    });

    test('counts terminals the way each language counts', () {
      expect(
        const EnStrings().licenceCoverage('X', null, 1),
        endsWith('one terminal'),
      );
      expect(
        const EnStrings().licenceCoverage('X', null, 6),
        endsWith('6 terminals'),
      );
      // Arabic splits one / two / a few / many, and keeps Western digits.
      expect(
        const ArStrings().licenceCoverage('X', null, 1),
        endsWith('جهاز واحد'),
      );
      expect(
        const ArStrings().licenceCoverage('X', null, 2),
        endsWith('جهازان'),
      );
      expect(
        const ArStrings().licenceCoverage('X', null, 6),
        endsWith('6 أجهزة'),
      );
      expect(
        const ArStrings().licenceCoverage('X', null, 20),
        endsWith('20 جهازاً'),
      );
    });

    test('has no Arabic string left in English', () {
      // Every Arabic value should contain at least one Arabic letter. The
      // exceptions are values that are deliberately not words — a placeholder
      // the operator types over, or a protocol token.
      const notWords = {
        'licenceKeyHint', // XORD-0000-0000-0000
        'notSet', // an em dash
        'listSeparator',
      };

      final arabic = RegExp(r'[؀-ۿ]');
      final untranslated = <String>[];

      for (final entry in _arabicSamples.entries) {
        if (notWords.contains(entry.key)) continue;
        if (!arabic.hasMatch(entry.value)) untranslated.add(entry.key);
      }

      expect(
        untranslated,
        isEmpty,
        reason: 'These read as English on an Arabic till: $untranslated',
      );
    });
  });

  testWidgets('a screen actually renders Arabic, right to left', (
    tester,
  ) async {
    // The checks above read the catalogue. This one drives a real widget
    // through the real delegate, which is the part that would still be broken
    // if `AppLocalizations` were never installed above the tree.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: TableCard(table: DiningTable(id: 1, label: 'T1', seats: 4)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Arabic words, Western digits — a quantity is read across a counter and
    // typed back into a keypad, so it keeps one shape in both languages.
    expect(find.text('4 مقعد'), findsOneWidget);
    expect(find.text('فاضية'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(TableCard))),
      TextDirection.rtl,
    );
  });

  group('the language the operator switches to', () {
    const configured = SavedTerminalConfig(
      deployment: DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
      ),
      terminal: TerminalProfile(
        branchId: 13,
        branchName: 'Maadi',
        terminalName: 'Counter 1',
        terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
        businessId: 7,
        branchCode: 'MAA',
      ),
      languageCode: 'en',
    );

    test('outlives the process that chose it', () async {
      // The bug: `apply` set state and nothing else, so the Settings menu
      // flipped the screen and the next launch read the language the WIZARD
      // wrote. A till switched to العربية came back up in English the
      // following morning, which reads as the switch having been ignored.
      final store = InMemoryTerminalConfigStore()..saved = configured;
      final container = ProviderContainer(
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(localeProvider.notifier).apply('ar');
      // On screen immediately — the write must not be what the frame waits on.
      expect(container.read(localeProvider).languageCode, 'ar');

      await pumpEventQueue();
      expect(store.saved!.languageCode, 'ar');
      // Nothing else about the terminal moved.
      expect(store.saved!.terminal.terminalId, configured.terminal.terminalId);
      expect(store.saved!.deployment.databaseHost, '192.168.1.20');

      // And the next launch boots into it.
      final relaunched = ProviderContainer(
        overrides: [
          terminalBootProvider.overrideWithValue(
            TerminalBoot(config: store.saved),
          ),
        ],
      );
      addTearDown(relaunched.dispose);
      expect(relaunched.read(localeProvider).languageCode, 'ar');
    });

    test('writes nothing on a terminal still inside the wizard', () async {
      // No config yet means setup has not finished. Writing a partial one here
      // would hand the router a configuration nobody completed; the wizard
      // writes the whole file, language included, when it ends.
      final store = InMemoryTerminalConfigStore();
      final container = ProviderContainer(
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(localeProvider.notifier).apply('ar');
      await pumpEventQueue();

      expect(container.read(localeProvider).languageCode, 'ar');
      expect(store.saved, isNull);
      expect(store.writes, 0);
    });
  });

  test('the literal check sees the shapes that hid an English start screen', () {
    // The check below is only worth what its scanner can see, and the three
    // shapes here are the ones a line-anchored, slot-adjacent regex missed for
    // as long as the start screen has existed. Asserting on them directly
    // means the scanner cannot quietly narrow again.
    const source = '''
      Text(
        'POINT OF SALE',
      ),
      PosButton(label: blocked ? 'Renew licence' : 'Manage licence'),
      _cell('TENANT', session.tenantName),
      KeyChip('ENTER', onShell: true),
      Text('\$error'),
      Text(strings.pointOfSale),
      Text(strings.queued.replaceFirst('{count}', '\$n')),
      final label = switch ((online, hasError)) {
        (_, true) => 'Sync status unavailable',
        (true, false) => strings.syncChecking,
      };
      Text(label, style: PosText.mono(size: 11.5)),
      final tag = 'ar';
      Text(tag),
    ''';

    final caught = _captionLiterals(source)
        .where((c) => !_allowed(_withoutInterpolation(c.text)))
        .map((c) => c.text)
        .toSet();

    expect(caught, {
      'POINT OF SALE', // multiline `Text(`
      'Renew licence', // a ternary arm behind `label:`
      'Manage licence',
      'TENANT', // a positional argument
      'ENTER',
      // A switch expression parked in a local and handed to `Text(` one line
      // later — the sync pill's shape, and the one that put an English status
      // in the top bar of an Arabic till. `tag` is followed too, and `'ar'`
      // stays allowed: following the local widens what the check SEES, not
      // what it objects to.
      'Sync status unavailable',
    });
  });

  test('no operator-facing literal survives in the widget layer', () {
    // Read the source rather than the rendered tree: a string only reaches a
    // screen on the branch that builds it, and a test that drove every branch
    // of every dialog would be a slower, less complete version of this.
    final offenders = <String>[];

    for (final file in _widgetLayerFiles()) {
      final path = file.path;
      // The catalogue IS the strings.
      if (path.contains('core/l10n/')) continue;

      final source = _withoutComments(file.readAsStringSync());
      // By offset, because a literal can sit in two nested slots at once —
      // `text: Text('…')` is one mistake, not two.
      final seen = <int>{};
      for (final caption in _captionLiterals(source)) {
        if (!seen.add(caption.offset)) continue;
        if (_allowed(_withoutInterpolation(caption.text))) continue;
        offenders.add(
          "$path:${_lineOf(source, caption.offset)}  '${caption.text}'",
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Operator-facing text belongs in AppStrings, where writing it obliges '
          'somebody to write the Arabic too:\n${offenders.join('\n')}',
    );
  });

  test('a terminal with no configuration yet opens in Arabic', () {
    // The businesses this ships to are in Egypt, and an installer who wants
    // English is one item away in the Settings bar on every screen — including
    // the first one. Only the FALLBACK moves: a terminal that has been set up
    // reads its own `languageCode` and keeps whatever was chosen there.
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(localeProvider).languageCode, 'ar');

    final configured = ProviderContainer(
      overrides: [
        terminalBootProvider.overrideWithValue(
          const TerminalBoot(
            config: SavedTerminalConfig(
              deployment: DeploymentConfig(mode: DeploymentMode.offline),
              terminal: TerminalProfile(
                branchId: 1,
                terminalName: 'Counter 1',
                terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
                businessId: 1,
                branchCode: 'MAIN',
              ),
              languageCode: 'en',
            ),
            hasDatabaseCredential: true,
          ),
        ),
      ],
    );
    addTearDown(configured.dispose);
    expect(configured.read(localeProvider).languageCode, 'en');
  });

  test('and so does the wizard it opens', () {
    expect(const SetupDraft().locale, 'ar');
  });
}

/// A literal sitting in a slot that renders words.
class _Caption {
  const _Caption(this.slot, this.text, this.offset);

  final String slot;
  final String text;
  final int offset;
}

/// The widgets and named arguments that render words, and so must be handed a
/// value from [AppStrings] rather than a literal.
///
/// The call names include the positional-caption widgets — `KeyChip('ENTER')`
/// and the private `_cell('TENANT', …)` both put a word on screen through an
/// argument no `label:` marks.
///
/// Alternatives are ordered longest-first so `hintText:` matches as itself
/// rather than as `hint` with a stray `Text` in front of it.
final _slot = RegExp(
  r'\b(Text|SelectableText|MicroLabel|KeyChip|_cell)\s*\('
  r'|\b(semanticsLabel|confirmLabel|cancelLabel|actionLabel|helperText'
  r'|errorText|hintText|labelText|subtitle|tooltip|summary|message|label'
  r'|title|blurb|hint|help|text)\s*:',
);

/// Every literal sitting in a caption slot, wherever inside the argument it
/// sits.
///
/// Reads the whole file rather than a line at a time, and reads the ARGUMENT
/// rather than the character straight after the slot. Both matter, and both
/// were how an English start screen stayed green for so long:
///
/// * the widget layer wraps, so `Text(` and its caption are routinely on
///   different lines — `Text(\n  'POINT OF SALE',` was invisible to a
///   line-anchored match;
/// * a caption is as often the arm of a ternary — `label: blocked ? … : …` —
///   as it is a bare string, and anchoring on the character after the colon
///   sees only the condition.
Iterable<_Caption> _captionLiterals(String source) sync* {
  for (final match in _slot.allMatches(source)) {
    final slot = match.group(1) ?? match.group(2)!;
    yield* _literalsInArgument(source, match.end, slot);
    // …and the literals of any local the argument merely NAMES. See
    // [_localLiterals] for why the indirection is worth following.
    for (final name in _referencesInArgument(source, match.end)) {
      yield* _localLiterals(source, name, slot);
    }
  }
}

/// The bare identifiers inside one argument — the names a caption is handed
/// instead of a literal.
///
/// Skips anything that is a member access (`strings.openDrawer`), a call
/// (`_label(ink)`) or a named argument's own label, because none of those is a
/// local this file can resolve.
Iterable<String> _referencesInArgument(String source, int start) sync* {
  var depth = 0;
  var i = start;

  while (i < source.length) {
    final char = source[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      i++;
    } else if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) return;
      depth--;
      i++;
    } else if (depth == 0 && char == ',') {
      return;
    } else if (char == "'" || char == '"') {
      // Stepped over rather than read: the literals are the other walk's job,
      // and an identifier inside an interpolation is not a caption.
      final literal = _readLiteral(source, i);
      if (literal == null) return;
      i = literal.end;
    } else if (_isIdentifierStart(char)) {
      final match = _identifier.matchAsPrefix(source, i)!;
      final name = match.group(0)!;
      final before = i == 0 ? '' : source[i - 1];
      final after = _nextMeaningful(source, match.end);
      if (before != '.' && before != r'$' && !'(.:'.contains(after)) {
        yield name;
      }
      i = match.end;
    } else {
      i++;
    }
  }
}

/// Every literal in the initialiser of a local called [name], anywhere in this
/// file.
///
/// This is what the sync pill needed. Its four states were built as
///
/// ```dart
/// final label = switch ((online, queued, hasError)) { … '● Checking sync…' };
/// return Text(label, …);
/// ```
///
/// — four English sentences, one hop from the `Text(` the check was watching,
/// and so an Arabic till showed an English sync status in the top bar all day.
/// A caption is no less a caption for being named on the way to the screen.
///
/// Deliberately crude in two ways, both of which err toward catching:
///
/// * **By name, not by scope.** Any `final label = …` in the file counts, not
///   just the one in scope. A file with two unrelated `label`s over-reports —
///   but a local named for a caption slot and holding an English sentence is
///   worth a second look wherever it sits.
/// * **The initialiser only.** A local that is declared empty and assigned
///   later is not followed, and neither is a field or a parameter. This is a
///   net, not a proof; the sealed catalogue is what makes a MISSING string
///   impossible, and this only catches a string nobody thought to ask for.
///
/// Measured against the widget layer as it stands, following locals adds no
/// false positives at all: of the 196 identifiers sitting in caption slots,
/// seven resolve to a local with a literal in it, and every one of those is a
/// shape [_allowed] already passes — a language tag, a separator, an empty
/// string. The rule costs nothing and would have caught the pill.
Iterable<_Caption> _localLiterals(
  String source,
  String name,
  String slot,
) sync* {
  final declaration = RegExp(
    r'\b(?:final|var|const)\s+(?:[\w<>,?\s.]*\s)?' +
        RegExp.escape(name) +
        r'\s*=',
  );

  for (final match in declaration.allMatches(source)) {
    yield* _literalsInInitialiser(source, match.end, slot);
  }
}

/// Walks a declaration's initialiser to the `;` that ends it, yielding the
/// string literals inside.
///
/// Bracket-aware, because the initialiser worth following is exactly the one
/// with a body — a `switch` expression's arms end in commas and the whole
/// thing in `};`, and a walker that stopped at the first `;` or `,` would read
/// none of it.
Iterable<_Caption> _literalsInInitialiser(
  String source,
  int start,
  String slot,
) sync* {
  var depth = 0;
  var i = start;

  while (i < source.length) {
    final char = source[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      i++;
    } else if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) return;
      depth--;
      i++;
    } else if (depth == 0 && char == ';') {
      return;
    } else if (char == "'" || char == '"') {
      final literal = _readLiteral(source, i);
      if (literal == null) return;
      yield _Caption(slot, literal.text, i);
      i = literal.end;
    } else {
      i++;
    }
  }
}

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

bool _isIdentifierStart(String char) =>
    RegExp(r'[A-Za-z_]').hasMatch(char);

/// The next character that is not whitespace, or the empty string at the end.
String _nextMeaningful(String source, int i) {
  while (i < source.length && (source[i] == ' ' || source[i] == '\n' ||
      source[i] == '\t' || source[i] == '\r')) {
    i++;
  }
  return i < source.length ? source[i] : '';
}

/// Walks exactly ONE argument — to the comma that ends it, or to the bracket
/// that closes the call — yielding the string literals inside it.
///
/// One argument rather than the whole call, so a `style:` or an `onPressed:`
/// further down the same widget cannot drag unrelated literals in.
Iterable<_Caption> _literalsInArgument(
  String source,
  int start,
  String slot,
) sync* {
  var depth = 0;
  var i = start;

  while (i < source.length) {
    final char = source[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      i++;
    } else if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) return;
      depth--;
      i++;
    } else if (depth == 0 && char == ',') {
      return;
    } else if (char == "'" || char == '"') {
      final literal = _readLiteral(source, i);
      if (literal == null) return;
      yield _Caption(slot, literal.text, i);
      i = literal.end;
    } else {
      i++;
    }
  }
}

class _Literal {
  const _Literal(this.text, this.end);

  final String text;
  final int end;
}

/// Reads one Dart string literal, interpolation and all.
///
/// Interpolation has to be walked rather than scanned past, because a `${…}`
/// may itself contain quotes — `'${n.padLeft(2, '0')}/'` is one literal, not
/// two — and a reader that stopped at the first inner quote would resynchronise
/// on the wrong side of every literal after it.
_Literal? _readLiteral(String source, int start) {
  final quote = source[start];
  final buffer = StringBuffer();
  var i = start + 1;

  while (i < source.length) {
    final char = source[i];
    if (char == r'\') {
      buffer.write(source.substring(i, (i + 2).clamp(0, source.length)));
      i += 2;
    } else if (char == quote) {
      return _Literal(buffer.toString(), i + 1);
    } else if (char == r'$' && i + 1 < source.length && source[i + 1] == '{') {
      final end = _skipInterpolation(source, i + 2);
      if (end == null) return null;
      buffer.write(source.substring(i, end));
      i = end;
    } else if (char == '\n') {
      // Unterminated on its line: not a literal this check can reason about.
      return null;
    } else {
      buffer.write(char);
      i++;
    }
  }
  return null;
}

/// The offset just past the `}` closing a `${` that opened at [i].
int? _skipInterpolation(String source, int i) {
  var depth = 1;
  while (i < source.length) {
    final char = source[i];
    if (char == '{') {
      depth++;
      i++;
    } else if (char == '}') {
      depth--;
      i++;
      if (depth == 0) return i;
    } else if (char == "'" || char == '"') {
      final nested = _readLiteral(source, i);
      if (nested == null) return null;
      i = nested.end;
    } else {
      i++;
    }
  }
  return null;
}

/// What is left when the data is taken out.
///
/// `Text('$error')` puts no English on screen — the words are the repository's,
/// and `lib/app/labels.dart` is where a coded refusal becomes a sentence. But
/// `'cached · $itemCount items'` is a caption with a number in it, and the word
/// "items" needs an Arabic twin. Stripping the interpolation is what tells the
/// two apart.
String _withoutInterpolation(String text) => text
    .replaceAll(RegExp(r'\$\{[^{}]*\}'), '')
    .replaceAll(RegExp(r'\$\w+'), '');

/// Blanks comment lines while keeping the line count, so offsets still map to
/// the line numbers a failure prints.
String _withoutComments(String source) =>
    source.split('\n').map((l) => _isComment(l) ? '' : l).join('\n');

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

bool _isComment(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('//') || trimmed.startsWith('///');
}

/// Not every literal is a word somebody reads as language.
bool _allowed(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return true;

  // Glyphs and punctuation — a close cross, an em dash, a separator.
  if (!RegExp(r'[A-Za-z]').hasMatch(trimmed)) return true;

  // A single lower-case token is an identity, not a caption: 'password',
  // 'owner', 'manager', 'database' and the other form keys and placeholders.
  if (RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(trimmed)) return true;

  // Technical placeholders shown in an empty field, and the product's own
  // name, which is a brand rather than a word.
  const literals = {
    'XOrder POS',
    'XORD-0000-0000-0000',
    'Counter 1',
    'MAADI-7Q42',
    'EGP',
    // Key names. Not translated because they are what is printed on the
    // keyboard: an Arabic till has the same F-keys as an English one, and a
    // chip that said something else would be naming a key nobody has.
    'F2',
    'F7',
    'F9',
    'CLR',
    'SKU',
  };
  if (literals.contains(trimmed)) return true;

  // A URL or a host:port skeleton.
  if (RegExp(r'^https?://').hasMatch(trimmed)) return true;

  // A substitution placeholder — `'{count}'` in a `replaceFirst`. The words
  // around it are the catalogue's; this is the hole they are poured into.
  if (RegExp(r'^\{\w+\}$').hasMatch(trimmed)) return true;

  return false;
}

/// Everything that draws, plus the controllers that hand it words.
///
/// `lib/data/` is deliberately outside this. Repositories answer with a
/// machine-readable code beside an English sentence, and it is the app layer —
/// `provisioningRefusal` in `lib/app/labels.dart` — that turns the code into
/// words. The English sentence is the fallback for a code THIS build has never
/// seen, which is worth more to somebody at a half-configured till than a
/// translated "something went wrong". Forbidding it here would delete that.
Iterable<File> _widgetLayerFiles() => ['lib/features', 'lib/app', 'lib/core']
    .map(Directory.new)
    .where((d) => d.existsSync())
    .expand((d) => d.listSync(recursive: true))
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Every Arabic value, by member name, so the "still in English" check has
/// something to read. Built by reflection-free enumeration because Dart has no
/// mirrors on this target — adding a string here is not required, but a string
/// absent from it is simply unchecked.
final _arabicSamples = <String, String>{
  for (final entry in _sample(const ArStrings()).entries)
    entry.key: entry.value,
};

Map<String, String> _sample(AppStrings s) => {
  'cancel': s.cancel,
  'done': s.done,
  'back': s.back,
  'continueLabel': s.continueLabel,
  'orderTypeDineIn': s.orderTypeDineIn,
  'orderTypeTakeaway': s.orderTypeTakeaway,
  'nothingToCharge': s.nothingToCharge,
  'ticketVoided': s.ticketVoided,
  'searchHint': s.searchHint,
  'customAmount': s.customAmount,
  'noItemsMatch': s.noItemsMatch,
  'openDrawer': s.openDrawer,
  'syncingWithPlatform': s.syncingWithPlatform,
  'syncStatusUnavailable': s.syncStatusUnavailable,
  'syncOfflineQueued': s.syncOfflineQueued(3),
  'syncOfflineUnknown': s.syncOfflineQueued(null),
  'syncChecking': s.syncChecking,
  'syncSyncedQueued': s.syncSyncedQueued(0),
  'lock': s.lock,
  'closeShift': s.closeShift,
  'categories': s.categories,
  'allItems': s.allItems,
  'openTickets': s.openTickets,
  'tables': s.tables,
  'changeTable': s.changeTable,
  'cartEmptyHelp': s.cartEmptyHelp,
  'newRound': s.newRound,
  'subtotal': s.subtotal,
  'addToTicket': s.addToTicket,
  'tenderCash': s.tenderCash,
  'tenderCard': s.tenderCard,
  'payment': s.payment,
  'amountDue': s.amountDue,
  'tendersHeading': s.tendersHeading,
  'amount': s.amount,
  'exact': s.exact,
  'clear': s.clear,
  'takePayment': s.takePayment,
  'backToTicket': s.backToTicket,
  'receiptThanks': s.receiptThanks,
  'newSale': s.newSale,
  'printAndNew': s.printAndNew,
  'pickATable': s.pickATable,
  'pickATableHelp': s.pickATableHelp,
  'terminalLocked': s.terminalLocked,
  'wrongPin': s.wrongPin,
  'signIn': s.signIn,
  'signInHelp': s.signInHelp,
  'openTheDrawer': s.openTheDrawer,
  'openShift': s.openShift,
  'openingFloat': s.openingFloat,
  'emptyDrawer': s.emptyDrawer,
  'countTheDrawer': s.countTheDrawer,
  'countedInDrawer': s.countedInDrawer,
  'zSales': s.zSales,
  'zGrossTaken': s.zGrossTaken,
  'zCounted': s.zCounted,
  'licence': s.licence,
  'activate': s.activate,
  'activateOnline': s.activateOnline,
  'checkForRenewal': s.checkForRenewal,
  'cannotCheckForRenewal': s.cannotCheckForRenewal,
  'licenceKeyHint': s.licenceKeyHint,
  'notSet': s.notSet,
  'listSeparator': s.listSeparator,
  'listAnd': s.listAnd,
  'capOperate': s.capOperate,
  'capStaffManage': s.capStaffManage,
  'capShiftClose': s.capShiftClose,
  'capGroupSelling': s.capGroupSelling,
  'capGroupBackOffice': s.capGroupBackOffice,
  'refusalRoleIsSystemDefined': s.refusalRoleIsSystemDefined,
  'refusalWouldLockEveryoneOut': s.refusalWouldLockEveryoneOut,
  'backToTill': s.backToTill,
  // Admin Mode's password (ADR-006b slice D).
  'adminPasswordLabel': s.adminPasswordLabel,
  'adminPasswordFirstTime': s.adminPasswordFirstTime,
  'adminSetPasswordTitle': s.adminSetPasswordTitle,
  'adminSetPasswordHelp': s.adminSetPasswordHelp(10),
  'adminNewPassword': s.adminNewPassword,
  'adminConfirmPassword': s.adminConfirmPassword,
  'adminSavePassword': s.adminSavePassword,
  'adminPasswordStepExpired': s.adminPasswordStepExpired,
  'passwordSameAsPin': s.passwordSameAsPin,
  'passwordTooShort': s.passwordTooShort(10),
  'passwordTooLong': s.passwordTooLong(128),
  'passwordSameAsUsername': s.passwordSameAsUsername,
  'passwordsDoNotMatch': s.passwordsDoNotMatch,
  'technicianResetLink': s.technicianResetLink,
  'technicianResetTitle': s.technicianResetTitle,
  'technicianResetHelp': s.technicianResetHelp,
  'technicianResetAction': s.technicianResetAction,
  'technicianResetDone': s.technicianResetDone('Amer'),
  'technicianResetNobody': s.technicianResetNobody,
  'clearPasswordAction': s.clearPasswordAction,
  'clearPasswordTitle': s.clearPasswordTitle('Amer'),
  'clearPasswordConsequence': s.clearPasswordConsequence,
  'keepPassword': s.keepPassword,
  'passwordSetLabel': s.passwordSetLabel,
  'refusalOwnerPasswordIsTheirs': s.refusalOwnerPasswordIsTheirs,
  'actStaffPasswordSet': s.actStaffPasswordSet,
  'actStaffPasswordCleared': s.actStaffPasswordCleared,
  'paneStaff': s.paneStaff,
  'paneRoles': s.paneRoles,
  'paneActivity': s.paneActivity,
  'paneMenu': s.paneMenu,
  'addSomebody': s.addSomebody,
  'notSaved': s.notSaved,
  'close': s.close,
  'you': s.you,
  'resetPin': s.resetPin,
  'disable': s.disable,
  'enable': s.enable,
  'noRole': s.noRole,
  'fieldName': s.fieldName,
  'fieldUsername': s.fieldUsername,
  'fieldPin': s.fieldPin,
  'fieldRole': s.fieldRole,
  'fieldSku': s.fieldSku,
  'add': s.add,
  'setPin': s.setPin,
  'save': s.save,
  'discard': s.discard,
  'edit': s.edit,
  'rename': s.rename,
  'addCategory': s.addCategory,
  'addItem': s.addItem,
  'offSale': s.offSale,
  'backOnSale': s.backOnSale,
  'supervisorApproval': s.supervisorApproval,
  'notPermittedTitle': s.notPermittedTitle,
  'terminalNotSetUp': s.terminalNotSetUp,
  'switchToLight': s.switchToLight,
  'switchToDark': s.switchToDark,
  'windowMenu': s.windowMenu,
  'settings': s.settings,
  'syncNow': s.syncNow,
  'management': s.management,
  'stepLanguage': s.stepLanguage,
  'stepConnection': s.stepConnection,
  'englishBlurb': s.englishBlurb,
  'arabicBlurb': s.arabicBlurb,
  'modeCloud': s.modeCloud,
  'modeOffline': s.modeOffline,
  'notLicensedBadge': s.notLicensedBadge,
  'theDatabase': s.theDatabase,
  'databaseHost': s.databaseHost,
  'databasePassword': s.databasePassword,
  'testConnection': s.testConnection,
  'platformAddress': s.platformAddress,
  'platformCaps': s.platformCaps,
  'business': s.business,
  'setupCode': s.setupCode,
  'username': s.username,
  'password': s.password,
  'terminalName': s.terminalName,
  'terminalNameHint': s.terminalNameHint,
  'whichTillIsThis': s.whichTillIsThis,
  'aNewTill': s.aNewTill,
  'useThisTill': s.useThisTill,
  'registered': s.registered,
  'findPrinters': s.findPrinters,
  'testPrint': s.testPrint,
  'cashDrawerAttached': s.cashDrawerAttached,
  'scannerAttached': s.scannerAttached,
  'currency': s.currency,
  'serviceCharge': s.serviceCharge,
  'vat': s.vat,
  'rounding': s.rounding,
  'downloadMenu': s.downloadMenu,
  'readMenu': s.readMenu,
  'summaryLanguage': s.summaryLanguage,
  'summaryThisMachine': s.summaryThisMachine,
  'summaryAttached': s.summaryAttached,
  'none': s.none,
  'ownerDbAccessTitle': s.ownerDbAccessTitle,
  'ownerDbAccessHelp': s.ownerDbAccessHelp,
  'adminAccountIs': s.adminAccountIs('pos_admin'),
  'ownerAccountTitle': s.ownerAccountTitle,
  'ownerAccountHelp': s.ownerAccountHelp,
  'ownerNameLabel': s.ownerNameLabel,
  'usernameLabel': s.usernameLabel,
  'signInPinLabel': s.signInPinLabel,
  'confirmPinLabel': s.confirmPinLabel,
  'pinExactHelp': s.pinExactHelp(4),
  'pinsDoNotMatch': s.pinsDoNotMatch,
  'showSecret': s.showSecret,
  'hideSecret': s.hideSecret,
  'createDatabaseAndContinue': s.createDatabaseAndContinue,
  'databaseCreated': s.databaseCreated,
  'noDatabaseYet': s.noDatabaseYet,
  'installLicenceFirst': s.installLicenceFirst,
  'schemaAlreadyCurrent': s.schemaAlreadyCurrent,
  'schemaUpgradeFailed': s.schemaUpgradeFailed('relation "pos_units"'),
  'missingBranch': s.missingBranch,
  'nothingRecordedYet': s.nothingRecordedYet,
  'noRolesYet': s.noRolesYet,
  'menuComesFromPlatform': s.menuComesFromPlatform,
  'nothingInCategoryYet': s.nothingInCategoryYet,
  // The start screen and the wizard header. Every one of these was translated
  // and then never called — the widgets spelled the English out inline — so
  // they are named here to keep them checked now that they are wired.
  'pointOfSale': s.pointOfSale,
  'renewLicence': s.renewLicence,
  'manageLicence': s.manageLicence,
  'licenceRequired': s.licenceRequired,
  'startShift': s.startShift,
  'resumeShift': s.resumeShift('S-12'),
  'cashUpStillAvailable': s.cashUpStillAvailable,
  'startShiftHelp': s.startShiftHelp,
  'resumeShiftHelp': s.resumeShiftHelp('Rana'),
  'tenantCell': s.tenantCell,
  'branchCell': s.branchCell,
  'terminalCell': s.terminalCell,
  'catalogCell': s.catalogCell,
  'catalogSyncing': s.catalogSyncing,
  'catalogCachedItems': s.catalogCachedItems(12),
  'terminalSetup': s.terminalSetup,
  'openTheTill': s.openTheTill,
  'optionalField': s.optionalField('X'),
  'paneReportsBlurb': s.paneReportsBlurb,
  'reportPeriodToday': s.reportPeriodToday,
  'reportPeriodWeek': s.reportPeriodWeek,
  'reportPeriodMonth': s.reportPeriodMonth,
  'reportPeriodCustom': s.reportPeriodCustom,
  'reportVsPrevious': s.reportVsPrevious,
  'reportNoComparison': s.reportNoComparison,
  'reportKpiRefunds': s.reportKpiRefunds,
  'reportRefundCount': s.reportRefundCount(3),
  'reportTrend': s.reportTrend,
  'reportTopProducts': s.reportTopProducts,
  'reportTopProductsNote': s.reportTopProductsNote,
  'reportRankQuantity': s.reportRankQuantity,
  'reportRankAmount': s.reportRankAmount,
  'reportColumnQuantity': s.reportColumnQuantity,
  'reportColumnAmount': s.reportColumnAmount,
  'reportNoProducts': s.reportNoProducts,
  'reportPayments': s.reportPayments,
  'reportOnAccount': s.reportOnAccount,
  'reportNoPayments': s.reportNoPayments,
  'reportTerminals': s.reportTerminals,
  'reportBranchTotal': s.reportBranchTotal,
  'reportUnregistered': s.reportUnregistered,
  'reportInsights': s.reportInsights,
  'reportInsightBestDay': s.reportInsightBestDay,
  'reportInsightTopTerminal': s.reportInsightTopTerminal,
  'reportInsightGrowth': s.reportInsightGrowth,
  'reportInsightsNone': s.reportInsightsNone,
  'reportUnavailable': s.reportUnavailable,
  'reportNoDatabase': s.reportNoDatabase,
};

/// Where [needle] actually renders inside [text], laid out left to right.
double _leftEdgeOf(String text, String needle) {
  final painter = TextPainter(
    text: TextSpan(text: text),
    textDirection: TextDirection.ltr,
  )..layout();
  final start = text.indexOf(needle);
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + needle.length),
  );
  return boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
}
