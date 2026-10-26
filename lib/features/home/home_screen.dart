import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/labels.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/text/digits.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/ticket.dart';

/// Where a cashier says how this order is sold: one button per order type the
/// back office has enabled (pos-home-screen).
///
/// **The list is not decided here.** It is `branchOrderTypesProvider` — the
/// restaurant's active types in the order it sorted them, intersected with what
/// the branch may sell — which is already what the sale screen's mode switch
/// shows. Turn a type off in the back office and its button goes; turn one on
/// and it arrives, with no restart. The names are the restaurant's own
/// (`OrderTypeConfig.displayName`), falling back to the product's words.
///
/// **A branch that sells one way never sees this screen.** The router skips it
/// (`afterShift`), so a café, a food truck or a delivery-only kitchen goes where
/// Start sent it before. This screen also forwards by itself if the list turns
/// out to hold one type — the restaurant's configuration can arrive a beat
/// after Start has decided — rather than show a single button.
///
/// What a button does is the router's: a seated type opens the floor, any
/// other starts a sale of that type. This screen only reports the choice.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onPick, required this.onBack});

  final void Function(OrderType type) onPick;

  /// Escape: back to Start, where this shift was opened or resumed.
  final VoidCallback onBack;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _forwarded = false;

  /// The key a digit means: 1 is the first button. The typed character first,
  /// so an Arabic layout's `١` works, then the key for a layout that sends
  /// none.
  static int? _indexFor(KeyEvent event) {
    final typed = event.character == null ? null : foldDigits(event.character!);
    if (typed != null && typed.length == 1) {
      final digit = typed.codeUnitAt(0) - 0x30;
      if (digit >= 1 && digit <= 9) return digit - 1;
    }
    final key = event.logicalKey;
    const keys = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
    ];
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].contains(key)) return i;
    }
    return null;
  }

  KeyEventResult _onKey(List<OrderType> types, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onBack();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final index = _indexFor(event);
    if (index == null || index >= types.length) return KeyEventResult.ignored;
    widget.onPick(types[index]);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final types = ref.watch(branchOrderTypesProvider);
    final rules = ref.watch(orderTypeRulesProvider);
    final loading = ref.watch(orderTypeConfigProvider).isLoading;
    final tenant = ref.watch(sessionProvider).valueOrNull?.tenantName ?? '';

    // One way of selling: nothing to choose. Once, after this frame.
    if (!loading && types.length == 1 && !_forwarded) {
      _forwarded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPick(types.single);
      });
    }

    return Scaffold(
      backgroundColor: pos.shell,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(types, event),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: loading
                ? CircularProgressIndicator(color: pos.accent)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(PosSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tenant.isNotEmpty)
                          Text(
                            tenant.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: PosText.ui(
                              size: 28,
                              weight: FontWeight.w800,
                              color: pos.shellText,
                            ),
                          ),
                        const SizedBox(height: PosSpace.md),
                        Text(
                          strings.pointOfSale,
                          textAlign: TextAlign.center,
                          style: PosText.mono(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: pos.shellMuted,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: PosSpace.s28),
                        for (var i = 0; i < types.length; i++) ...[
                          if (i > 0) const SizedBox(height: PosSpace.md),
                          PosButton(
                            key: Key('home-type-${types[i].wire}'),
                            label:
                                rules
                                    .forType(types[i])
                                    ?.displayName(strings.languageCode) ??
                                types[i].label(strings),
                            height: 88,
                            alignLeft: true,
                            autofocus: i == 0,
                            background: pos.accent,
                            foreground: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            padding: const EdgeInsets.symmetric(
                              horizontal: PosSpace.xl,
                            ),
                            trailing: i < 9
                                ? KeyChip('${i + 1}', onShell: true)
                                : null,
                            onPressed: () => widget.onPick(types[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
