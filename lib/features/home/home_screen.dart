import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/labels.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/money/money.dart';
import '../../core/text/digits.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/ticket.dart';
import '../cash/presentation/day_close_dialog.dart';
import '../shift/presentation/shift_dialogs.dart';

/// Where somebody lands after signing in (pos-signin-first-home): start a
/// shift, say how this order is sold, or close the day — each shown only to the
/// person who may.
///
/// **Signing in is not opening a shift.** Start only asks who you are; this
/// screen is where a shift is started (`shift.open`) and where the day is
/// closed (`day.close`), so a manager can close the night without ever opening
/// a drawer. Without a shift the order-type buttons are there but dead, with the
/// reason beside them; a branch that sells one way has nothing to choose, so
/// before a shift it shows only Start shift.
///
/// **The list of order types is not decided here.** It is
/// `branchOrderTypesProvider` — the business's active types in the order it
/// sorted them, intersected with what the branch may sell — which is already
/// what the sale screen's mode switch shows. Turn a type off in the back office
/// and its button goes; turn one on and it arrives, with no restart. The names
/// are the business's own (`OrderTypeConfig.displayName`), falling back to the
/// product's words.
///
/// **A branch that sells one way and has a shift open never sees this
/// screen.** The router skips it (`afterSignIn`), so a café, a food truck or a
/// delivery-only kitchen goes where Start sent it before. This screen also
/// forwards by itself if the list turns out to hold one type with a shift open —
/// the business's configuration can arrive a beat after Start has decided.
///
/// **Close the day** is shown only while a trading day is open and only when the
/// signed-in staff member holds `day.close`. Hiding it is courtesy; the dialog
/// asks for the permission again before it closes anything.
///
/// What a type button does is the router's: a seated type opens the floor, any
/// other starts a sale of that type. This screen only reports the choice.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onPick,
    required this.onBack,
    this.onShiftOpened,
  });

  final void Function(OrderType type) onPick;

  /// Escape and Sign out: the person is signed out first, then this is called,
  /// and the router takes the till to Start.
  final VoidCallback onBack;

  /// A shift was just opened from here.
  final VoidCallback? onShiftOpened;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _forwarded = false;

  /// The float dialog is open: it opens the shift before it closes, and Home
  /// must not forward a one-type branch under it (the dialog's own result does).
  bool _starting = false;

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

  KeyEventResult _onKey(
    List<OrderType> types,
    KeyEvent event, {
    required bool shiftOpen,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _signOut();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    // The number keys are the buttons, and the buttons are dead without a shift.
    if (!shiftOpen) return KeyEventResult.ignored;
    final index = _indexFor(event);
    if (index == null || index >= types.length) return KeyEventResult.ignored;
    widget.onPick(types[index]);
    return KeyEventResult.handled;
  }

  /// Signing out is what leaving Home means: Start is the signed-out door, and
  /// an unattended Home would be somebody's permissions left on a counter.
  void _signOut() {
    ref.read(signedInStaffProvider.notifier).signOut();
    widget.onBack();
  }

  Future<void> _startShift() async {
    final staff = ref.read(signedInStaffProvider);
    if (staff == null) return;
    _starting = true;
    final opened = await OpenShiftDialog.show(context, by: staff);
    _starting = false;
    if (opened && mounted) widget.onShiftOpened?.call();
  }

  Future<void> _closeDay() async {
    final closed = await DayCloseDialog.show(context);
    if (closed == null || !mounted) return;
    posToast(
      context,
      context.strings.dayClosed(
        (closed.gross ?? Money.zero).format(withCurrency: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final staff = ref.watch(signedInStaffProvider);
    final shiftOpen = ref.watch(shiftProvider).valueOrNull != null;
    final mayOpenShift = ref
        .watch(canProvider(PosCapability.shiftOpen))
        .isAllowed;
    final licence = ref.watch(licenceEntitlementProvider).valueOrNull;
    // Only the next shift is blocked by a lapsed licence — never the open one,
    // never cash-up, never closing the day.
    final licenceBlocked = licence != null && !licence.canOpenShift;
    final mayCloseDay =
        ref.watch(canProvider(PosCapability.dayClose)).isAllowed &&
        ref.watch(businessDayProvider).valueOrNull != null;
    final types = ref.watch(branchOrderTypesProvider);
    final rules = ref.watch(orderTypeRulesProvider);
    final loading = ref.watch(orderTypeConfigProvider).isLoading;
    final tenant = ref.watch(sessionProvider).valueOrNull?.tenantName ?? '';

    // One way of selling and a shift open: nothing to choose. Once, after this
    // frame. Without a shift there is something to do here (Start shift).
    if (!loading &&
        shiftOpen &&
        !_starting &&
        types.length == 1 &&
        !_forwarded) {
      _forwarded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPick(types.single);
      });
    }

    // A branch that sells one way has no choice to show before a shift.
    final showTypes = shiftOpen || types.length > 1;

    return Scaffold(
      backgroundColor: pos.shell,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(types, event, shiftOpen: shiftOpen),
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
                        if (staff != null) ...[
                          const SizedBox(height: PosSpace.lg),
                          Text(
                            strings.signedInAs(staff.name),
                            key: const Key('home-signed-in-as'),
                            textAlign: TextAlign.center,
                            style: PosText.ui(size: 13, color: pos.shellMuted),
                          ),
                          Align(
                            child: PosButton(
                              key: const Key('home-sign-out'),
                              label: strings.signOut,
                              height: PosSize.minTouchTarget,
                              foreground: pos.shellMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              onPressed: _signOut,
                            ),
                          ),
                        ],
                        const SizedBox(height: PosSpace.s28),
                        if (!shiftOpen) ...[
                          if (mayOpenShift) ...[
                            PosButton(
                              key: const Key('home-start-shift'),
                              label: licenceBlocked
                                  ? strings.licenceRequired
                                  : strings.startShift,
                              height: 72,
                              alignLeft: true,
                              autofocus: true,
                              background: licenceBlocked
                                  ? pos.shellCard
                                  : pos.accent,
                              foreground: licenceBlocked
                                  ? pos.shellMuted
                                  : Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              padding: const EdgeInsets.symmetric(
                                horizontal: PosSpace.xl,
                              ),
                              trailing: licenceBlocked
                                  ? null
                                  : KeyChip(strings.enterKeyCap, onShell: true),
                              onPressed: licenceBlocked ? null : _startShift,
                            ),
                            const SizedBox(height: PosSpace.md),
                            Text(
                              licenceBlocked
                                  ? strings.cashUpStillAvailable
                                  : strings.startShiftHelp,
                              textAlign: TextAlign.center,
                              style: PosText.ui(
                                size: 12,
                                color: pos.shellMuted,
                              ),
                            ),
                          ] else if (staff != null)
                            Text(
                              strings.notPermittedToOpenShift(staff.name),
                              key: const Key('home-cannot-open-shift'),
                              textAlign: TextAlign.center,
                              style: PosText.ui(
                                size: 12,
                                color: pos.shellMuted,
                              ),
                            ),
                          if (showTypes) ...[
                            const SizedBox(height: PosSpace.lg),
                            Text(
                              strings.startShiftToSell,
                              key: const Key('home-start-shift-to-sell'),
                              textAlign: TextAlign.center,
                              style: PosText.ui(
                                size: 12,
                                color: pos.shellMuted,
                              ),
                            ),
                            const SizedBox(height: PosSpace.md),
                          ],
                        ],
                        if (showTypes)
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
                              autofocus: shiftOpen && i == 0,
                              background: shiftOpen
                                  ? pos.accent
                                  : pos.shellCard,
                              foreground: shiftOpen
                                  ? Colors.white
                                  : pos.shellMuted,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              padding: const EdgeInsets.symmetric(
                                horizontal: PosSpace.xl,
                              ),
                              trailing: shiftOpen && i < 9
                                  ? KeyChip('${i + 1}', onShell: true)
                                  : null,
                              onPressed: shiftOpen
                                  ? () => widget.onPick(types[i])
                                  : null,
                            ),
                          ],
                        if (mayCloseDay) ...[
                          const SizedBox(height: PosSpace.s28),
                          Align(
                            child: PosButton(
                              key: const Key('home-close-day'),
                              label: strings.dayCloseTitle,
                              height: PosSize.minTouchTarget,
                              foreground: pos.shellMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              onPressed: _closeDay,
                            ),
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
